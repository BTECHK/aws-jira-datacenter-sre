---
type: source
title: "Cutover Runbook — Redmine → Jira Cloud"
tags: [migration]
authors: [project-author]
url: null
raw: docs/runbooks/cutover-runbook.md
ingested: 2026-05-26
created: 2026-05-26
updated: 2026-05-26
sources: []
---

# Source: Cutover Runbook — Redmine → Jira Cloud

The go-live runbook for the Redmine→Jira leg. Models the JCMA *migrate* phase with explicit gates, a go/no-go scorecard, and a rollback trigger. Rollback floor: an RDS snapshot + `pg_dump` taken at T-1; the source stays intact and read-only, so rollback = keep using Redmine.

## The gate model

- **T-1 readiness gate:** data clean (`jiraops assess` returns 0 findings), trial-site test migration succeeded, backups verified-restorable, target prepped (issue types/statuses/custom fields + a `Redmine ID` anchor), comms sent.
- **Go/No-Go scorecard** at window start: all criteria GREEN = GO; any RED = NO-GO, reschedule.
- **Cutover steps:** freeze (source → read-only) → final `jiraops assess` (must be 0, no drift) → extract batched UTF-8 CSV with `Redmine ID` column → migrate via External System Import (capture log as migration report) → re-point automation/integrations to Cloud base URL + API-token auth.
- **Validation gate:** `jiraops parity` reconciles counts per project/type/status via the `Redmine ID` anchor; spot-check custom fields, comment attribution, attachments, subtask links; owning teams confirm.
- **Rollback trigger:** parity delta over threshold, broadly-wrong attribution, or an unclearable blocking import error inside the window. Rollback is non-destructive — lift the freeze, keep using Redmine.

See [[cutover-gate-model]] for the reusable pattern and [[jiraops-cli]] for the `assess`/`parity` tooling that backs the gates.

## Related

- [[redmine]] — the migration source.
- [[oss-to-atlassian-migration]] — where this leg fits in the overall migration.
