# Jira Data Center — HA / Clustering Interview Ammo

> Verbal companion to the **Phase 3 (High Availability)** build. The lab clusters **Redmine** (the Jira analog) hands-on — 2 nodes + HAProxy + shared EFS home + RDS Multi-AZ + failover/rolling-upgrade drills — which gives you a *real* "I did this" story for the cluster topology, load balancing, and multi-node upgrade. This doc maps those reps onto **Jira-DC-specific vocabulary** and covers the parts the Redmine cluster can't exercise hands-on: Hazelcast cache coordination, node sizing at scale, the Windows↔Linux move, and the on-call recovery flow.
>
> Sibling doc: `jira-cloud-admin.md` (what changes when you give all this up for Cloud). The two connect: **HA is the burden you operate on DC; the Cloud migration retires it.**
>
> Targets the coach's questions: **#4 HA clustering · #8 multi-node upgrades · #11 node sizing · #10 on-call recovery · #3 Windows↔Linux move.**

---

## 1. Jira DC cluster architecture (the diagram you draw on the whiteboard)

A Jira Data Center cluster is **four tiers**:

```
        ┌─────────────┐
client →│ Load Balancer│  (sticky sessions + /status health check)
        └──────┬───────┘
        ┌──────┴───────┬──────────────┐
     ┌──┴──┐        ┌──┴──┐        (N app nodes, each with a LOCAL home)
     │node1│◄──────►│node2│   ← Hazelcast: cache coordination + cluster locks (node-to-node)
     └──┬──┘        └──┬──┘
        └──────┬───────┘
       ┌───────┴────────┐        ┌──────────────────┐
       │ Shared DB (HA) │        │ Shared home (NFS)│  attachments, plugins,
       └────────────────┘        └──────────────────┘  import/export, avatars, index snapshots
```

| Component | What it holds / does | Lab analog (Phase 3) |
|---|---|---|
| **App nodes** | Stateless-ish Jira instances; each has a **local home** (its own **Lucene search index**, caches, logs, tmp) | 2 Redmine nodes, one per AZ |
| **Shared home (NFS)** | **attachments, installed plugins, import/export, avatars/logos, index snapshots** — anything that must be identical across nodes | **EFS** holding Redmine `files/` |
| **Shared DB** | The single source of truth; all nodes read/write it | **RDS** (Multi-AZ) |
| **Load balancer** | Distributes traffic, **sticky sessions**, evicts unhealthy nodes via a **health check** | **HAProxy** (cookie stickiness + `httpchk`) |
| **Hazelcast** | **Inter-node cache replication + cache invalidation + cluster locks + membership** — the node-to-node coordination layer | *No Redmine analog* — discussed via XWiki/JGroups (§5) |

**The two nuances that signal you actually know DC (not just "it has nodes"):**
- **The search index is LOCAL to each node, not on the shared home.** Each node keeps its own Lucene index; updates propagate via an **index-replication journal**, and a node that joins/recovers can rebuild from an **index snapshot stored in the shared home**. People wrongly assume the index lives on NFS — it doesn't (NFS is too slow for index I/O). *This is the #1 "have you really run DC" tell.*
- **The shared home is the shared *state*; Hazelcast is the shared *cache coherence*.** Two different problems: NFS makes durable artifacts (attachments, plugins) identical; Hazelcast makes the in-memory caches across nodes agree.

> **Senior framing:** *"DC is multiple app nodes over one shared DB and one shared NFS home, fronted by a load balancer with sticky sessions, and the nodes coordinate their caches over Hazelcast. The subtlety is the Lucene index is per-node with replication — not on the shared home — so node recovery means restoring an index snapshot and catching up the journal."*

---

## 2. Load balancer — and the vocabulary that travels (HAProxy ↔ F5 ↔ ALB)

Jira DC supports any LB that does **session affinity** + an **HTTP health check**. Atlassian's docs name **HAProxy, nginx, Apache `mod_proxy_balancer`, AWS ELB/ALB, and hardware F5 BIG-IP / Citrix**. In the lab you ran **HAProxy** — and its concepts are the same everywhere, so learn the map:

| Concept | **HAProxy** (lab) | **F5 BIG-IP** (enterprise on-prem) | **AWS ALB** (Jira-on-AWS) |
|---|---|---|---|
| Group of backends | `backend` | **pool** | **target group** |
| A backend node | `server` | pool **member** | **target** |
| Health check | `option httpchk GET /status` | **health monitor** | health check (path) |
| Session affinity | `cookie … insert` | **persistence profile** | **stickiness** (app cookie) |
| Public entry point | `frontend` / `bind` | **virtual server (VIP)** | **listener** |

- **Health check target for real Jira DC = `/status`** (returns `200` + JSON `{"state":"RUNNING"}`). In the lab you used Redmine's `/login` returning 200 — same idea.
- **Sticky sessions are required** so a logged-in user keeps hitting the node that holds their session. HAProxy does **cookie-insert** stickiness natively (the method Jira DC documents); that's why the lab uses HAProxy over OSS nginx (nginx free only does `ip_hash`).

**"Who load-balances the load balancer?" (the SPOF follow-up):** in real on-prem you run **two HAProxy/F5 boxes with a virtual IP via keepalived (VRRP)** — VRRP elects a master that owns the VIP; if it dies, the backup takes the VIP in seconds. On AWS, ALB is itself managed/redundant so you don't. *Mention keepalived even though the lab runs one HAProxy — it shows you know the LB is otherwise a SPOF.*

---

## 3. Node sizing — "how many nodes?" (#11)

There is **no fixed formula** — and saying so, then giving the factors, is the strong answer:

- **Start at 2.** Two is the floor for HA (one can fail or be drained). One node is "clustered" in name only.
- **Concurrent/peak active users + request throughput** — the primary driver. Measure it (don't guess); add nodes when a node's CPU/heap/response-time degrades under peak.
- **N+1 (or N+2) redundancy** — size so that with one node **down or drained for a rolling upgrade**, the remaining nodes still carry peak load. "Capacity you need, **plus one**."
- **Failure domain** — protect against a *node* (2+ nodes) and, on cloud, against an *AZ* (spread nodes across AZs — the lab puts the 2nd Redmine in the other AZ).
- **Workload shape** — heavy REST/automation/integration traffic, large attachments, and reindex load all push you toward more/bigger nodes.
- **Vertical vs horizontal** — sometimes a bigger node (more heap) beats another node; balance both.
- **NOT licensing.** DC is licensed by **user tier**, not node count — you can add nodes without paying per node. (Common misconception; correct it.)

> **Senior framing:** *"I'd start with two for redundancy, baseline the real concurrent-user and request load, and size to peak + 1 so a rolling upgrade or a node failure doesn't degrade service. Spread across AZs for the cloud failure domain. Node count is driven by load and redundancy, not licensing — DC is per-user-tier."*

---

## 4. Upgrades in a cluster — rolling / ZDU and its hard limit (#8)

**Two kinds of upgrade, and the distinction is the whole answer:**

- **Rolling / Zero-Downtime Upgrade (ZDU)** — supported for **bug-fix and feature releases *within the same major platform version***. The cluster runs in a temporary **mixed state**: you put the cluster into upgrade mode, then **drain → upgrade → rejoin one node at a time** while the others serve. No downtime. *This is exactly the lab's Step-7 drill on Redmine.*
- **Downtime upgrade** — required for a **major / platform upgrade** or anything with **incompatible DB-schema or JVM changes** (e.g. the Phase-2 **Java 17→21** XWiki jump). You can't run two nodes against a changed schema at once, so the whole cluster goes down, you upgrade, you reindex, you come back.

**The multi-node rolling procedure (what you'd narrate):**
1. Take a backup / DB snapshot first (rollback floor).
2. Enable upgrade mode (Jira DC: "Cluster upgrade" / ZDU mode).
3. **Drain node 1** at the LB (stop new sessions; let existing drain).
4. Stop Jira on node 1, upgrade the binaries, start, confirm `/status` RUNNING + healthy.
5. **Return node 1** to the LB; **repeat** for each node.
6. Finalize the upgrade mode; verify version + index health across all nodes.

> **The bridge to the migration story:** *"ZDU only works minor-within-major. Our big upgrades — a major version or a JVM bump — still force downtime even with a cluster. That recurring downtime + the operational cost of running the cluster is a real reason we looked at Cloud, where Atlassian absorbs the upgrade."* (Hands off to `jira-cloud-admin.md`.)

---

## 5. Hazelcast / distributed cache + split-brain (the concept the lab discusses, not builds)

Redmine's HA is **stateless-app + sticky sessions** — it doesn't coordinate caches between nodes. Jira DC does, via **Hazelcast**; **XWiki's analog is JGroups** (so XWiki is where you'd *see* this if you built it — we chose not to, it's the finicky time-sink).

- **Why it's needed:** each node caches data in memory. A write on node A must **invalidate or replicate** to node B, or B serves stale data. Hazelcast is the distributed cache + **cluster-wide locks** + **membership** layer that does this.
- **Discovery on AWS:** AWS has **no multicast**, so Hazelcast uses **TCP/IP discovery** (Atlassian ships an AWS discovery mechanism; the lab's XWiki analog would use a TCP stack like **TCPPING / JDBC_PING**). Good concrete detail to drop.
- **Split-brain:** if the cluster network partitions, two halves can each think they're the cluster and **diverge**. Jira DC uses cluster-membership / **split-brain protection (quorum)** — a node that loses contact with the cluster will **shut itself down** rather than serve divergent data ("cluster panic"). The fix is almost always **network/Hazelcast-port connectivity** between nodes, not the app.

> **Senior framing:** *"Stateless web tier is the easy part — the hard part of clustering a stateful app is cache coherence. Jira uses Hazelcast to invalidate caches and hold cluster locks across nodes; XWiki uses JGroups. On AWS there's no multicast so discovery is TCP-based, and you design for split-brain with quorum so a partitioned node parks itself instead of corrupting state."*

---

## 6. On-call recovery — "Jira isn't working, what do you do?" (#10)

A **layered triage**, narrated calmly — scope first, mitigate fast, root-cause after:

1. **Scope it.** One node or all? Hit the LB, then each node's **`/status`** directly. "Is it down, or degraded?"
2. **Walk the tiers top-down:** LB healthy? → each node's app (`/status`) → DB reachable (connections, failover state) → **shared home mounted** (NFS) → Hazelcast inter-node connectivity.
3. **Check the usual killers:** **disk full** (logs/attachments on the shared home), **DB connection pool exhausted**, **heap/GC** (OOM, long GC pauses), and **"what changed?"** (recent deploy/config/plugin).
4. **Read the logs:** `atlassian-jira.log`, `catalina.out`, GC logs, `journalctl -u …`, and the LB health log.
5. **Mitigate by blast radius:**
   - **One bad node →** *drain it from the LB* — the cluster keeps serving — then restart/investigate and rejoin. (This is the lab's failover drill: one node dies, HAProxy evicts it, sessions survive.)
   - **All nodes bad →** it's shared: **DB**, **shared home/NFS**, or **network/SG**. Check RDS status (failover?), the NFS mount, security groups.
   - **Cluster panic / split-brain →** check the **Hazelcast port** connectivity between nodes.
6. **Communicate** status + ETA; **capture the timeline** for the post-incident review.

> **Senior framing:** *"Scope before I touch anything — one node or all? If it's one node I drain it at the LB so users never notice and debug it out of rotation. If it's all nodes it's shared state — DB, NFS home, or the cluster network — so I check those before restarting blindly. Mitigate first, root-cause after, and write the timeline."*

---

## 7. Moving a deployment Windows ↔ Linux (#3 — verbal; no lab analog)

Jira is **Java**, so the *application* is portable — the work is the **environment around it**:

- **What moves cleanly:** the **database** (dump/restore — DB-engine-portable), the **shared home + local home** contents (attachments, plugins, config).
- **What you have to fix on the target OS:**
  - **Paths & separators** — Windows `C:\jira\home` ↔ Linux `/var/atlassian/...`; update `jira-home`, `dbconfig.xml`, `cluster.properties`, log paths.
  - **Line endings / encoding** — config files written on Windows (CRLF) vs Linux (LF); UTF-8.
  - **Case sensitivity** — Linux filesystems are case-sensitive; Windows isn't — a latent path-casing bug surfaces on Linux.
  - **Service management** — Windows **service** (`JiraService`) ↔ Linux **systemd unit**; the run-as **service account** and file ownership/permissions.
  - **JVM config** — `setenv.bat` ↔ `setenv.sh` (heap, GC, `JAVA_HOME`); reapply tuning.
  - **Reindex** on the target (the Lucene index is OS/path-specific; rebuild it).
- **Procedure shape:** install the **same Jira version** on the target OS → restore DB + home → fix the paths/config above → set up the service → start → **reindex** → validate. Often the *reason* for the move is getting off Windows onto a supported Linux/RHEL standard.

> **Senior framing:** *"Because Jira's Java, the app is portable — I'd stand up the identical version on Linux, restore the DB and the home directories, then fix the OS-specific layer: paths, line endings, the systemd service and service account, `setenv.sh` JVM args, and case-sensitivity gotchas. Then reindex on the target and validate. The DB and attachments port cleanly; the environment is the work."*

---

## 8. The DC → Cloud HA delta (where this doc hands off)

Everything above is **your** responsibility on DC. On **Atlassian Cloud you give it all up** — which is the trade the migration (Phase 4) makes:

| DC (you operate) | Cloud (Atlassian operates) |
|---|---|
| You run N nodes + shared home + LB + Hazelcast | **No nodes** — Atlassian runs the platform; RTO/RPO are theirs |
| You size the cluster | **No sizing** — capacity is Atlassian's problem |
| You schedule rolling/ZDU upgrades (downtime for majors) | Atlassian rolls out continuously; **release tracks + sandbox** are your control surface |
| You own backup/restore + failover | **Managed**; manual export only, no self-service PITR |
| You debug split-brain / NFS / GC at 2am | You **file a ticket** |

> **The full-circle line:** *"The HA cluster is exactly the operational burden the Cloud migration retires. We traded control — release tracks instead of scheduling our own upgrades, an export instead of PITR — for not running nodes, shared home, and Hazelcast ourselves. And the FedRAMP/Guard gap closing is what finally made that trade viable for a regulated shop."* (→ continue in `jira-cloud-admin.md`.)

---

## Likely interview Q&A (rapid-fire)

- **"Components of a Jira DC cluster?"** → App nodes (each with a local Lucene index), shared DB, shared NFS home (attachments/plugins/import-export/index-snapshots), load balancer with sticky sessions + `/status` health check, Hazelcast for cache coordination.
- **"Where does the search index live?"** → **Local to each node**, replicated via a journal; snapshots in the shared home for recovery. *Not* on NFS.
- **"How many nodes?"** → Start at 2; size to peak concurrent load **+1** for N+1; spread across AZs; not driven by licensing (per-user-tier).
- **"Rolling upgrade — when can't you?"** → ZDU is minor/feature-within-major; major/platform or schema/JVM changes need downtime (e.g. Java 17→21).
- **"How does the LB detect a dead node?"** → `/status` health check; it stops routing there. Sticky sessions pin users; a dead node's sessions move (and survive only because shared session state isn't node-local).
- **"What's Hazelcast for / split-brain?"** → Inter-node cache invalidation + locks + membership; on a partition, quorum/split-brain protection parks a node rather than letting it diverge. TCP discovery on AWS (no multicast).
- **"On-call, Jira's down?"** → Scope (one node vs all) → walk tiers (LB→app→DB→NFS→Hazelcast) → check disk/connections/heap/recent-change → drain one bad node or fix shared state → communicate + timeline.
- **"Move Jira Windows→Linux?"** → Same version + restore DB/home; fix paths, line endings, case-sensitivity, systemd service + account, `setenv.sh`, then reindex + validate.
- **"How is this different in Cloud?"** → You don't run any of it; HA/DR is Atlassian's; you get release tracks + sandbox + managed export instead.
