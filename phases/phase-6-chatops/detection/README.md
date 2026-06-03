# detection/ — scheduled compliance checks (the "detect" front-end)

Generates the findings that flow into the Slack engine. Read-only against Jira Cloud; emits findings as Jira issues.

## Checks (when built)
- `access_review.py` — pull Jira Cloud users / groups / project roles via REST; diff against an **approved baseline** (`baseline.yml`, checked in); flag stale or over-broad grants.
- `control_hygiene.py` — issues missing a required compliance field; global custom-field contexts that hurt performance (the `jiraops audit-fields` idea).

## Contract
- **Input:** live Jira Cloud (REST) + `baseline.yml`.
- **Output:** a finding per drift item → create/update a Jira finding issue (severity + SLA due date) → handed to `../slack-app/`.
- **Schedule:** cron / EventBridge (batch, not long-running).

## Note
These may graduate into the existing `jiraops-cli/` as `jiraops access-review` / `jiraops control-hygiene` instead of living here permanently — decide at build time.
