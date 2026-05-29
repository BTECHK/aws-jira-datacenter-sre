# jiraops-cli

A small Python CLI for **migration parity validation** — comparing a self-hosted source system against its Atlassian Cloud destination after a migration. Its primary use in this project is the **Redmine → Jira Cloud** leg (the protected core); the same inventory/diff approach applies to the other legs.

This CLI deliberately mirrors the **Jira Cloud Migration Assistant (JCMA)** pattern — *assess → clean → (test) migrate → validate* — even though JCMA itself can't read Redmine. Modeling its workflow is the point: it's how you speak to migration readiness in an interview.

## Commands

- `jiraops assess` — **JCMA-style pre-migration assessment report.** Scans the Redmine source for the classic Jira-Cloud blockers and prints a PASS/FAIL report: **email collisions** (case-insensitive duplicate — Cloud keys users by unique email), **placeholder/non-routable emails**, **dead projects** that should be archived not migrated, **issues missing a required custom field**, and **issues attributed to a bad-email user**. Exits non-zero when findings remain, so it doubles as a cutover go/no-go gate.
- `jiraops clean [--apply]` — remediate what `assess` found, in the source, so a re-run comes back clean: make emails unique + routable, archive dead projects, set missing required values to a default. Dry-run by default.
- `jiraops inventory --site source` / `--site cloud` — count projects, issues, comments, attachments, users, and custom fields on each side (source via the Redmine REST API, destination via the Jira Cloud REST API).
- `jiraops parity` — diff the source vs. destination inventories and report deltas. Compares by **counts/keys/content**, not entity IDs (IDs regenerate in Cloud; the original Redmine ID is carried in a Jira custom field as the reconciliation anchor).
- `jiraops audit-fields` — list Jira custom fields and flag global-context ones.
- `jiraops whoami` — verify authentication on each side.

> The migration-readiness loop: **`assess` → `clean --apply` → `assess` (0 findings) → migrate → `parity`.** `assess`/`clean` are implemented in `jiraops_assess.py` (run `python jiraops_assess.py assess --base https://redmine.lab.local --key <KEY> --insecure`); the dirty data they operate on is planted by `salt_dirty()` in the Phase-1 seed.

## Notes

- Authenticate with an API token; load it from AWS Secrets Manager rather than hardcoding.
- Uses `requests` for the source and Jira REST APIs and `boto3` for AWS.
- The `parity` output backs the migration validation report.
