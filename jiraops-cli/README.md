# jiraops-cli

A small Python CLI for **Jira REST automation**, used in this project primarily for **migration parity validation** — comparing a source Data Center instance against its Cloud destination after a JCMA migration.

## Commands

- `jiraops inventory --site dc` / `--site cloud` — count projects, issues, comments, attachments, users, and custom fields on each side.
- `jiraops parity` — diff the source vs. destination inventories and report deltas. Compares by **counts/keys/content**, not entity IDs (IDs are regenerated in Cloud).
- `jiraops audit-fields` — list custom fields and flag global-context ones.
- `jiraops whoami` — verify authentication on each side.

## Notes

- Authenticate with an API token; load it from AWS Secrets Manager rather than hardcoding.
- Uses `requests` (or the `jira` library) for Jira REST and `boto3` for AWS.
- The `parity` output backs the migration validation report.
