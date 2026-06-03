# terraform/ — infra for the ChatOps engine

> Extends the **single existing stack** in `phases/phase-1-foundation/terraform/` (one state), same as Phase 3 — additive resources, not a new state.

## What it adds (when built)
- **Secrets Manager** entries for the Slack tokens + Jira API token (`mds-tools/chatops/*`).
- **IAM** — a role/policy letting the listener box read those secrets (+ EventBridge/cron perms for the detection schedule).
- **Listener host** — the Socket Mode listener needs an always-on home. Cheapest = a `systemd` service on an existing box; if isolated, a small dedicated `t3.micro`. Decide at build time.
- **EventBridge rule(s)** (or cron on the box) for the scheduled detection checks.

## Out of scope
No public ingress / ALB — Socket Mode dials out, so there is **no inbound endpoint to expose**.
