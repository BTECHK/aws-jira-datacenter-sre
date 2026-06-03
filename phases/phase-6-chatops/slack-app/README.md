# slack-app/ — the Jira↔Slack ChatOps engine (Option B core)

The bidirectional engine: Slack notifies, the user acts, the change is written back to Jira.

## What lives here (when built)
- `app.py` — Slack **Bolt** listener over **Socket Mode** (no public endpoint). Handles:
  - the **action buttons** on a finding card: Resolve / Reassign / Snooze / Escalate
  - the **Resolve modal**: closure date, evidence link, file upload, resolution note
  - the **slash command** `/mds close MDS-123`
- `jira_writeback.py` — Jira Cloud REST writes: transition the issue, set custom fields (closure date, evidence link), upload the attachment, add the comment **attributed to the acting user**.
- `blocks/` — Block Kit JSON templates (finding card, resolve modal, closed-state update).

## Contract
- **Input:** a "finding" (Jira issue key + metadata) from `../detection/`, or a live Jira webhook.
- **Output:** a Jira issue transitioned + fields/attachment/comment written; the Slack message edited to closed state; an audit event emitted to `../dashboard/`.

## Decisions
- **Socket Mode** → persistent `systemd` service on an EC2 box (it holds an outbound WebSocket). Not Lambda.
- **Idempotent** — dedupe double-clicks; reconcile by issue key; a re-submit must not double-transition.
- **Secrets** (`SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`, `SLACK_SIGNING_SECRET`, `JIRA_API_TOKEN`) from Secrets Manager — never in code.

## Prototype-early note
Develop against **Redmine's REST API** before Phase 4, then repoint the write-back to Jira Cloud.
