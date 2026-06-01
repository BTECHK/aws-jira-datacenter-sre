# Phase 3 (HA) — Incident & Recovery Drill Catalog

> Break/fix drills themed to **real Jira Data Center cluster failures**. Each is *inject → observe → detect → recover*, so they double as on-call reps (interview Q **#10**, "Jira's down, what do you do?"). Run them against the 2-node Redmine cluster from the Phase-3 guide.
>
> **The on-call reflex these build:** *scope first (one node or all?), mitigate by blast radius (drain one bad node vs. fix shared state), root-cause after, write the timeline.* Keep a watch loop running during every drill:
> ```bash
> while true; do curl -ks -o /dev/null -w "%{http_code} %{time_total}s\n" https://redmine.lab.local/; sleep 1; done
> ```

Placeholders: `YOUR_REDMINE1_IP` / `YOUR_REDMINE2_IP`, `YOUR_EFS_ID`, `YOUR_RDS_HOSTNAME`. Run app/box commands 📦 via SSM.

---

## Drill 1 — Node down (LB health-check eviction)
**Simulates:** a Jira node crashing / OOMing in a cluster. **The cluster should absorb it with zero user impact.**

- **Inject** (on `redmine-a`): `sudo systemctl stop redmine`
- **Observe:** the watch loop keeps returning `200` (node B serves); your browser session stays logged in.
- **Detect:**
  ```bash
  echo "show stat" | sudo socat stdio /run/haproxy/admin.sock | cut -d, -f1,2,18   # redmine-a → DOWN
  ```
- **Recover:** `sudo systemctl start redmine` on A → HAProxy health check flips it back to **UP**; it rejoins the pool.
- **Takeaway:** *"One bad node? I drain/lose it at the LB and the cluster keeps serving — users never notice. I debug it out of rotation, then rejoin."* This is the whole point of N+1.

## Drill 2 — Session secret mismatch (logged-out-on-failover)
**Simulates:** the classic "why does my clustered app keep logging people out?" — nodes signing session cookies with **different `secret_key_base`**.

- **Inject** (on `redmine-b` only): regenerate a *different* secret so the nodes disagree —
  ```bash
  cd /opt/redmine-app && sudo -u redmine RAILS_ENV=production bundle exec rake generate_secret_token && sudo systemctl restart redmine
  ```
- **Observe:** log in (you're pinned to one node); when HAProxy routes you to the other node (or after Drill 1's failover) you're **silently logged out / "invalid authenticity token."**
- **Detect:** compare the secret on both nodes (the `secret_token.rb` value / `SECRET_KEY_BASE`); they differ.
- **Recover:** distribute the **same** secret to both nodes (copy the file / set identical `Environment=SECRET_KEY_BASE=` / render from Secrets Manager), restart both.
- **Takeaway:** *"Session signing key is shared cluster state — in Jira DC it lives in the shared home. Every node must use the same one, or every rebalance logs users out."*

## Drill 3 — Shared home lost (EFS unmounts)
**Simulates:** the **NFS shared home** going away — attachments/plugins vanish cluster-wide. The #1 "all nodes degraded at once" cause.

- **Inject** (on both nodes): `sudo umount -l /mnt/efs/redmine-files`
- **Observe:** existing issues load, but **attachments 404** and new uploads fail — on *both* nodes (it's shared state, not one node).
- **Detect:**
  ```bash
  df -h | grep efs            # mount missing
  mount | grep redmine-files  # gone
  sudo ss -tn | grep 2049     # NFS connection state
  ```
  Then check the SG (2049 from app SG) and that a **mount target exists in this node's AZ**.
- **Recover:** `sudo mount -a` (re-applies the `_netdev` fstab entry); confirm `df -h` shows it on both nodes; retry an upload.
- **Takeaway:** *"Attachments down on every node = shared state, not a node — so I check NFS/EFS, the 2049 SG path, and the per-AZ mount target before touching the app."*

## Drill 4 — HAProxy can't reach backends (SELinux)
**Simulates:** the LB up but **no backend reachable** — a config/SELinux fault that takes the *whole* service down even though the nodes are healthy.

- **Inject** (on the proxy box): `sudo setsebool haproxy_connect_any off` then `sudo systemctl restart haproxy`
- **Observe:** the watch loop returns `503` — HAProxy is up but every backend shows DOWN/`L4` connection refused.
- **Detect:**
  ```bash
  echo "show stat" | sudo socat stdio /run/haproxy/admin.sock | cut -d, -f1,2,18,38   # both DOWN, L4 errors
  sudo ausearch -m avc -ts recent | grep haproxy                                       # SELinux denial
  getsebool haproxy_connect_any                                                        # → off
  ```
- **Recover:** `sudo setsebool -P haproxy_connect_any 1`; restart HAProxy; backends return UP.
- **Takeaway:** *"LB up but 503 on everything = it's the LB→backend path, not the apps. On RHEL that's almost always SELinux (`haproxy_connect_any`) or a SG/port — same lesson as nginx's `httpd_can_network_connect`."*

## Drill 5 — Node never joins (wrong health check / app port)
**Simulates:** a freshly-provisioned node that **won't enter the pool** — the silent "I added a node but traffic won't go to it."

- **Inject:** point a node's health check at a bad path (edit `option httpchk GET /nope`) **or** stop Redmine on the new node while leaving it defined.
- **Observe:** the node sits **DOWN** in stats and takes no traffic; capacity doesn't increase.
- **Detect:**
  ```bash
  curl -s -o /dev/null -w "%{http_code}\n" http://YOUR_REDMINE2_IP:3000/login   # is the app actually answering 200?
  echo "show stat" | sudo socat stdio /run/haproxy/admin.sock | grep redmine
  ```
  Walk it: app up on 3000? in the app SG? health-check path returns 200?
- **Recover:** fix the check path (`GET /login` + `http-check expect status 200`) / start Redmine; node flips UP.
- **Takeaway:** *"A node that won't take traffic is almost always the health check or a firewall path — I verify the app answers 200 on its port directly, then the LB's check definition."*

## Drill 6 — RDS Multi-AZ failover
**Simulates:** the database failing over to its standby — the data-tier HA story (RTO/RPO).

- **Inject:** `aws rds reboot-db-instance --db-instance-identifier mds-tools-db --force-failover`
- **Observe:** a **brief** error window in the watch loop (seconds) as the DB endpoint swaps to the standby, then `200`s resume — the app reconnects automatically.
- **Detect:**
  ```bash
  aws rds describe-db-instances --db-instance-identifier mds-tools-db \
    --query 'DBInstances[0].{AZ:AvailabilityZone,MultiAZ:MultiAZ,Status:DBInstanceStatus}'   # AZ flipped
  sudo journalctl -u redmine --since "2 min ago" | grep -i "connection"   # the reconnect blip
  ```
- **Recover:** nothing to do — failover is automatic; the standby is now primary. (Capture the short error window as your **RTO** evidence.)
- **Takeaway:** *"Multi-AZ failover is automatic — the endpoint DNS swaps to the synchronous standby in the other AZ. The app sees a seconds-long blip, not data loss. That's the managed RDS HA story I'd otherwise hand-build with streaming replication + a failover script."*

---

## Mapping to interview answers
| Drill | Proves you can answer |
|---|---|
| 1, 5 | "A node fails / won't join — what happens / what do you check?" (#4, #10) |
| 2 | "What's shared cluster state? Why do users get logged out?" (#4) |
| 3 | "All nodes degraded at once — where do you look?" (#10) |
| 4 | "LB is up but everything 503s." (#4, #10) |
| 6 | "How is the database highly available? What's your RTO?" (#4, #11) |
| 1 + the rolling-upgrade drill (guide Step 7) | "Walk me through a multi-node upgrade." (#8) |
