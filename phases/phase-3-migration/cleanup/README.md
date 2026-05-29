# Pre-Migration Readiness Checklist — Redmine → Jira Cloud

The human companion to **`jiraops assess`**. Models the Jira Cloud Migration Assistant's *pre-migration checks*: you don't migrate until the source is clean. Work top to bottom; every box must be ✅ (or a documented, accepted exception) before cutover. `jiraops assess` automates the starred (★) items — run it, fix with `jiraops clean --apply`, and re-run until it reports **0 findings**.

> Scope: the protected core (Redmine → Jira Cloud). The same discipline applies to the other legs.

## 1. User & access hygiene
- [ ] ★ **Unique emails** — no two accounts share an email (Cloud keys users by a **case-insensitive** address; `Bob@x` and `bob@x` collide).
- [ ] ★ **Routable emails** — no blank / placeholder / non-routable addresses (`@localhost`, `@invalid`, `@test`); these won't match a Cloud account.
- [ ] Inactive / departed users deactivated so they don't consume Cloud seats.

## 2. Project & scope
- [ ] ★ **Dead projects archived, not migrated** — stale/legacy/decommissioned projects are archived at the source (don't carry junk into Cloud).
- [ ] Migration scope + batching decided (≤250 rows/CSV for non-admin import); wave order documented.

## 3. Data quality & field mapping
- [ ] ★ **Required fields populated** — no issues missing a value the Jira target requires (e.g., Severity); the import preview only validates the first 30 rows, so blanks deeper in the file fail mid-import.
- [ ] Field map built: 1:1 where possible; the 3 custom fields (Severity / Target Release / Story Points) explicitly mapped; status-consolidation map defined.
- [ ] ★ **Attribution valid** — Assignee/Reporter resolve to a real, routable email (else they import as "Anonymous"/unassigned).
- [ ] Date formats and encoding (UTF-8) normalized; `Redmine ID` reconciliation-anchor column present.

## 4. Ecosystem parity
- [ ] **App & ecosystem assessment done** — Marketplace-app equivalents identified (or gaps accepted), and the config objects JCMA won't carry (automation, integrations/webhooks, filter subscriptions, dashboards) inventoried for rebuild. See **`app-and-ecosystem-assessment.md`**.
- [ ] Custom-field **contexts** audited (global → project-scoped where appropriate) — `jiraops audit-fields`.
- [ ] Attachments reachable via public URLs at import time.

## 5. Readiness gate
- [ ] **`jiraops assess` returns 0 findings** (exit 0). This is the go/no-go input for `docs/runbooks/cutover-runbook.md`.
- [ ] Test migration into a throwaway Cloud site succeeded; error log reviewed.

---
*Run:* `python jiraops-cli/jiraops_assess.py assess --base https://redmine.lab.local --key <KEY> --insecure` → `… clean --apply` → re-`assess`.
