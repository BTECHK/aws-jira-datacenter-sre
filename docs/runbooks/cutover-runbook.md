# Cutover Runbook — Redmine → Jira Cloud

The go-live runbook for the protected-core leg. Models the JCMA *migrate* phase with explicit gates, a go/no-go scorecard, and a rollback trigger. Times are illustrative; fill `🔲` per run.

- **Migration window:** 🔲  ·  **Coordinator:** 🔲  ·  **Rollback owner:** 🔲
- **Source:** `https://redmine.lab.local`  ·  **Target:** 🔲 Jira Cloud site
- **Rollback floor:** RDS snapshot + `pg_dump` taken in T-1 (source stays intact and read-only — rollback = keep using Redmine).

## T-1 (day before) — readiness gate
| Gate | Check | Owner | ✅ |
|---|---|---|---|
| Data clean | **`jiraops assess` returns 0 findings** (readiness checklist all ✅) | | |
| Test migration | Trial-site import succeeded; error log reviewed | | |
| Backups | RDS snapshot + `pg_dump` of `redmine` captured & verified-restorable | | |
| Target prepped | Issue types, statuses, 3 custom fields + `Redmine ID` anchor pre-created | | |
| Comms sent | Users notified of freeze window + read-only period | | |

## Go / No-Go scorecard (decision point, start of window)
| Criterion | Threshold | Status |
|---|---|---|
| `jiraops assess` | 0 findings | 🔲 |
| Test-migration parity | within agreed delta | 🔲 |
| Backups restorable | verified | 🔲 |
| Rollback owner on call | yes | 🔲 |
| Stakeholder sign-off | yes | 🔲 |

**Decision:** ☐ GO ☐ NO-GO — _all criteria GREEN = GO; any RED = NO-GO, reschedule._

## Cutover steps
1. **Freeze** — set Redmine to read-only / notify; record the freeze timestamp.
2. **Final assess** — re-run `jiraops assess` against the frozen source → must be **0** (no drift since T-1).
3. **Extract** — generate the batched UTF-8 CSV(s) with the `Redmine ID` column.
4. **Migrate** — run the batched External System Import; capture the success/fail log as the **migration report**.
5. **Re-point** — update any automation/integrations to the Cloud base URL + API-token auth.

## Validation gate (before declaring done)
- [ ] **`jiraops parity`** — counts per project/type/status reconcile (via the `Redmine ID` anchor) within the agreed delta.
- [ ] Spot-check: 3 custom fields populated; comments attributed (not "Anonymous"); attachments are files; subtask links intact.
- [ ] Owning teams confirm their projects/boards look right.

## Rollback trigger
**Abort and roll back if:** parity delta exceeds the agreed threshold, attribution is broadly wrong, or a blocking import error can't be cleared inside the window.
**Rollback = do nothing destructive:** the source was only frozen, not changed — lift the read-only freeze, keep using Redmine, communicate the reschedule. (The RDS snapshot/`pg_dump` cover the source if anything *was* touched.)

## Legs B & C — cutover deltas (slippable; run only after Leg A is validated)

The flow above is the **protected core**. Legs B and C reuse the same shape (freeze → migrate → validate → rollback-by-leaving-the-source) with these differences. They can **slip past A's go-live** without blocking it.

**Leg B — XWiki → Confluence Cloud (lossy, pre-accepted):**
- *Mechanism:* not CSV — **XWiki HTML-zip export → Confluence Cloud HTML import** (baseline). No "fails past row 30" class of error.
- *Freeze:* set XWiki read-only; export the HTML zip from the frozen state.
- *Validate:* page / space / **attachment** counts reconcile; spot-check formatting + link resolution; confirm the **loss-ledger** items (macros, history, authorship) are *intentionally* absent.
- *Not a rollback trigger:* flattened hierarchy / dropped macros are **expected and pre-accepted** in the loss ledger. Only a broken import or a wrong page tree is. Rollback = lift the freeze, keep using XWiki.

**Leg C — Gitea → Bitbucket Cloud (easiest):**
- *Mechanism:* `git clone --mirror` → `git push --mirror` — **push LFS objects first** or the mirror hangs.
- *Freeze:* stop pushes to Gitea (announce); mirror from the frozen repos; **set the default branch** in Bitbucket (mirror doesn't carry HEAD).
- *Validate:* `git ls-remote` branch/tag compare; repo size sane.
- *Pre-accepted loss:* PRs / issues / webhooks / permissions stay in Gitea (git history only). Rollback = keep pushing to Gitea.

**Sequencing rule:** A is fully migrated **and parity-validated** before B or C start; a failure in B/C never rolls back A.

## Post-go-live — hypercare (first 24–48h)  *(applies to all legs that went live)*
- [ ] Triage user-reported issues against the parity report; fix mappings/attribution as needed.
- [ ] Confirm re-pointed automation/integrations are firing.
- [ ] After the hypercare window with no blockers: archive the read-only Redmine instance; close the migration.
