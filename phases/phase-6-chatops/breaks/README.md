# Phase 6 (ChatOps) — Incident & Recovery Drill Catalog (skeleton)

> Break/fix drills themed to **real Slack↔Jira integration failures**. Same shape as the Phase-3 catalog: *inject → observe → detect → recover*. Bodies filled at build time — the drill *list* below is the contract.

Placeholders: `YOUR_FINDING_KEY` (e.g. `MDS-142`), the listener box, the Slack workspace.

---

## Drill 1 — Jira REST rate-limited (429 mid-write) — TODO
**Simulates:** the write-back hitting Jira Cloud's cost-based rate limit. Should back off (`Retry-After` + jitter) and **not lose** the user's resolution.

## Drill 2 — Double-click / re-submit (idempotency) — TODO
**Simulates:** the user clicks Resolve twice (or the modal re-submits). Must **not** double-transition or duplicate the attachment/comment.

## Drill 3 — Socket Mode disconnect / token expiry — TODO
**Simulates:** the listener's WebSocket drops or `SLACK_APP_TOKEN` expires. Should reconnect cleanly; in-flight actions shouldn't be silently lost.

## Drill 4 — Write-back partial failure — TODO
**Simulates:** the transition succeeds but the attachment upload fails. Define the rollback / retry / "flag for manual" behavior so Jira and Slack don't end up disagreeing.

## Drill 5 — Stale Slack message (issue changed in Jira directly) — TODO
**Simulates:** someone closes the issue in Jira itself; the Slack card is now stale. Reconcile on the next poll / webhook.

---

## Mapping to interview answers — TODO
*(Fill once drills are written — these map to "how do you make an integration reliable / idempotent / observable?")*
