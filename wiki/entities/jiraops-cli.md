---
type: entity
title: "jiraops-cli"
kind: tool
tags: [migration]
created: 2026-05-26
updated: 2026-05-26
sources: [readme, cutover-runbook]
---

# jiraops-cli

A small Python CLI for **migration parity validation** — comparing a self-hosted source against its Atlassian Cloud destination. Primary use: the **Redmine → Jira Cloud** leg (the protected core). It deliberately mirrors the **Jira Cloud Migration Assistant (JCMA)** workflow — *assess → clean → (test) migrate → validate* — even though JCMA itself can't read Redmine; modeling the workflow is the point.

## Commands

- `jiraops assess` — JCMA-style pre-migration report. Scans the Redmine source for classic Jira-Cloud blockers: **email collisions** (case-insensitive duplicates — Cloud keys users by unique email), **placeholder/non-routable emails**, **dead projects** (archive, don't migrate), **issues missing a required custom field** (Severity), and **bad attribution** (issues owned by a bad-email user → "Anonymous" in Cloud). Exits non-zero while findings remain, so it doubles as a cutover go/no-go gate.
- `jiraops clean [--apply]` — remediate findings in the source so a re-run is clean. Dry-run by default.
- `jiraops inventory --site source|cloud` — count projects/issues/comments/attachments/users/custom-fields per side.
- `jiraops parity` — diff source vs. destination inventories by **counts/keys/content** (not IDs — IDs regenerate in Cloud; the original Redmine ID is carried in a Jira custom field as the reconciliation anchor).
- `jiraops audit-fields` / `jiraops whoami` — list custom fields / verify auth per side.

## Implementation notes

- `assess`/`clean` are implemented in `jiraops-cli/jiraops_assess.py`. Constants: `PLACEHOLDER_DOMAINS`, `DEAD_MARKERS`, `SEVERITY_DEFAULT = "S3"`. Paginates Redmine list endpoints via `get_all()`.
- Auth via API token (`--key`, `REDMINE_API_KEY`, or `--secret` from AWS Secrets Manager via boto3). `--insecure` for the lab's self-signed proxy cert.
- Uses `requests` for both REST APIs; `boto3` for AWS. The dirty data it operates on is planted by `salt_dirty()` in the Phase-1 seed.

## Role in the migration

Backs the gates in the [[cutover-gate-model]] — the readiness loop is `assess → clean --apply → assess (0 findings) → migrate → parity`. See [[cutover-runbook]] and [[oss-to-atlassian-migration]].
