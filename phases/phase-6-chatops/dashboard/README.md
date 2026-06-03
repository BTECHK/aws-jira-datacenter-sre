# dashboard/ — posture view + audit log (the reporting artifact)

## Audit log (when built)
- Append-only record of every loop event: detected → routed → acknowledged → resolved (by whom, with evidence) → escalated. Timestamped. This is the **evidence trail** — the compliance deliverable.
- Store: start simple (SQLite / JSONL on the listener box); DynamoDB if it needs to be durable/shared.

## Dashboard
- Metrics: open findings by severity, **mean-time-to-resolve (MTTR)**, SLA adherence %, escalation rate.
- Render: lightweight — static HTML from the audit log, or QuickSight over the store. No real-time streaming (YAGNI).

## Contract
- **Input:** audit events emitted by `../slack-app/` and `../detection/`.
- **Output:** a readable posture view + an exportable audit trail.
