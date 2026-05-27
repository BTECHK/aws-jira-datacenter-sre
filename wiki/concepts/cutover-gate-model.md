---
type: concept
title: "Cutover Gate Model (assess → clean → migrate → parity)"
tags: [migration]
created: 2026-05-26
updated: 2026-05-26
sources: [cutover-runbook, readme]
---

# Cutover Gate Model

The reusable migration go-live pattern this project models on the **Jira Cloud Migration Assistant (JCMA)**: gate every step on objective, re-runnable checks, keep the source non-destructively recoverable, and validate by reconciliation rather than trust.

## The readiness loop

`assess → clean --apply → assess (0 findings) → migrate → parity`

The `assess`/`clean`/`parity` checks are implemented in [[jiraops-cli]]. `assess` exits non-zero while findings remain, which is what makes it usable as a **gate** rather than just a report.

## The gates (per [[cutover-runbook]])

- **T-1 readiness gate** — data clean (`jiraops assess` = 0), test migration succeeded, backups verified-restorable, target prepped (issue types/statuses/custom fields + a `Redmine ID` anchor field), comms sent.
- **Go/No-Go scorecard** at window start — all GREEN = GO; any RED = NO-GO, reschedule.
- **Cutover** — freeze source read-only → final `assess` (must be 0, proves no drift since T-1) → extract batched UTF-8 CSV with the `Redmine ID` column → migrate via External System Import (keep the log as the migration report) → re-point automation to the Cloud base URL + API-token auth.
- **Validation gate** — `jiraops parity` reconciles counts per project/type/status via the `Redmine ID` anchor; spot-check custom fields, comment attribution, attachments, subtask links.

## Why these design choices

- **Reconcile by counts/keys/content, not entity IDs** — IDs regenerate in Cloud, so the original Redmine ID is carried in a Jira custom field as the reconciliation anchor.
- **Non-destructive rollback** — the source is only *frozen* read-only, never changed, so rollback = lift the freeze and keep using Redmine. The RDS snapshot + `pg_dump` taken at T-1 are the floor if anything *was* touched.
- **Rollback trigger is explicit** — parity delta over threshold, broadly-wrong attribution, or an unclearable blocking import error inside the window.

Fits into the broader [[oss-to-atlassian-migration]] Phase 3.
