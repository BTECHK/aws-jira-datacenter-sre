# Phase 6 (optional) — Day-2 Governance: Jira↔Slack ChatOps

> **Optional capstone, fenced from Phases 1–5.** Phases 1–5 stand up, operate, and migrate the toolchain to Atlassian Cloud. This phase is what happens *after* cutover: turning the live **Jira Cloud** instance into a continuously-governed platform operated from **Slack** — notify on Jira activity, **act on and close tickets without leaving Slack**, and write the closure (date, evidence link, attachment, comment) back to Jira.
>
> **Why it exists:** a migration ends at cutover, but governance is ongoing — this models the real "Day-2" gap. It also exercises a genuinely *bidirectional* Slack↔Jira integration end to end, which is the new engineering vs. the rest of the lab.
>
> **Status: SCAFFOLDED — design agreed, build not started.** Each subdir README states its contract; the step-by-step build lives in the gitignored `.planning/phases/phase-6-chatops/IMPLEMENTATION-GUIDE.md`.
>
> **Gated behind Phase 4 (migration)** — it targets the migrated Jira Cloud instance. The notify/close engine can be prototyped against **Redmine's REST API** earlier, then repointed.

---

## The loop

```
detect → route → act → escalate → log/report
```

| Stage | Where | What it does |
|---|---|---|
| **Detect** | `detection/` | Scheduled `access-review` + `control-hygiene` checks against Jira Cloud (REST) vs. an approved baseline → emit findings as Jira issues (severity + SLA due date). |
| **Route** | `slack-app/` | Block Kit card to the owner in Slack: **[Resolve] [Reassign] [Snooze] [Escalate]**. |
| **Act** ⭐ | `slack-app/` | **Resolve** opens a Slack **modal** (closure date, evidence link, file, note) → bot **writes back to Jira**: transition + custom fields + attachment + comment, **attributed to the acting user** → edits the Slack message to "✅ closed by @x on …". Slash command: `/mds close MDS-123`. |
| **Escalate** | `slack-app/` | SLA timer: 24h no-ack → reminder + cc manager; 48h → raise priority / open P1. |
| **Log/report** | `dashboard/` | Append-only audit trail (the evidence artifact) + a posture view: open findings by severity, MTTR, SLA adherence. |

---

## Scope (locked)

**IN:** the two-way close-from-Slack engine (the core); scheduled detection that feeds it; a dashboard + audit log.

**OUT (YAGNI / deliberately not built):**
- **AI / Bedrock plain-English summaries** — dropped by choice (most gimmick-prone; can be added later as a stretch).
- Data lineage / catalog tooling, multi-framework rule engines, real-time streaming dashboards — README name-drops, not build hours.

---

## Architecture decisions

- **Socket Mode, not an HTTP endpoint.** The Slack app dials *out* over a WebSocket → **no public ingress, no inbound firewall hole**. It does need a **persistent listener**, so it runs as a `systemd` service on an always-on box (not Lambda).
- **Scheduled detection is batch** — cron or EventBridge, separate from the long-running listener.
- **Idempotent write-back** — dedupe double-clicks; reconcile by Jira issue key; a re-submit must never double-transition.
- **Secrets in AWS Secrets Manager** (Slack bot/app tokens, signing secret, Jira API token) — never in code.
- **Terraform extends the single Phase-1 stack** (one state), additive only — same pattern as Phase 3.
- **Target = migrated Jira Cloud**; prototypable against Redmine REST before Phase 4.

---

## Subdirectory map

| Dir | Holds |
|---|---|
| `slack-app/` | The Bolt Socket Mode listener — buttons, the Resolve modal, the slash command, and the Jira write-back. **The Option B core.** |
| `detection/` | Scheduled `access-review` + `control-hygiene` checks that generate findings. |
| `dashboard/` | Audit log + posture metrics. |
| `terraform/` | Additive infra: Secrets Manager, IAM, the listener host, the detection schedule. |
| `breaks/` | Inject→detect→recover drills for ChatOps failure modes (429, idempotency, reconnect, partial write). |

---

## Build order (when you reach it)

1. **Slack app + Socket Mode** — scopes, tokens → Secrets Manager (`detection/`-independent).
2. **Detection checks** — `access-review` + `control-hygiene` → findings as Jira issues.
3. **Notify + close engine** — finding card → Resolve modal → Jira write-back (the core).
4. **SLA escalation timer.**
5. **Dashboard + audit log.**
6. **Breaks drills.**

> Steps 1 + 3 can be built and demoed first against Redmine REST — that's the fastest path to a working two-way loop.

---

## Interview value

One loop touches Python automation, REST integration, Slack API, workflow automation, dashboards, access management, and audit-grade logging at once. It also converts the "Jira↔Slack escalation pipeline" résumé line from an architecture-level talking point into a shipped artifact.
