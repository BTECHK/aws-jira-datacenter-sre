# Wiki Log

Append-only chronological record of operations on the wiki. Each entry begins with `## [YYYY-MM-DD] <op> | <description>` so it's parseable with `grep "^## \[" log.md | tail -N`.

Operations:
- `ingest` — a source was processed into the wiki.
- `query` — a question was answered against the wiki (typically only logged when the answer was filed back as synthesis).
- `lint` — a health check was run.
- `schema` — the schema was modified.
- `shard` — an index was sharded.

---

## [2026-05-26] schema | Set wiki purpose (architecture/API/domain knowledge) + seeded tag taxonomy and in-repo source-handling convention.
## [2026-05-26] ingest | README.md → [[readme]] + [[oss-to-atlassian-migration]].
## [2026-05-26] ingest | docs/lessons/phase-1-redmine-debrief.md → [[phase-1-redmine-debrief]] + [[redmine]] + [[hidden-dependency-graph]].
## [2026-05-26] ingest | docs/runbooks/cutover-runbook.md → [[cutover-runbook]] + [[cutover-gate-model]] + [[jiraops-cli]].
