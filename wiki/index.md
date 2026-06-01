# Wiki Index

The catalog of all pages in this wiki. Each entry: a wikilink to the page and a one-line summary. The LLM reads this first when answering queries to identify candidate pages.

Keep summaries tight — one line each. The index is engineered to be cheap to read; a fat index defeats its purpose.

When this file exceeds ~300 lines or the wiki passes ~150 pages, shard into `wiki/indexes/<type>.md` and replace this file with a directory of shards. See the `scaling-playbook.md` reference in the `llm-wiki` skill for the migration procedure.

---

## Sources

- [[readme]] — project README: self-host OSS toolchain on AWS, migrate to Atlassian Cloud, AI-assisted planning; 5 phases + topology.
- [[phase-1-redmine-debrief]] — field report on standing up Redmine 5.1; ~10 hidden-coupling failures and their root causes.
- [[cutover-runbook]] — Redmine→Jira Cloud go-live runbook: gates, go/no-go scorecard, non-destructive rollback.

## Entities

- [[redmine]] — the Rails/Puma issue tracker; protected-core migration source; deliberately on v5.1.
- [[jiraops-cli]] — Python CLI for JCMA-style assess/clean/inventory/parity over Redmine↔Jira Cloud.

## Concepts

- [[oss-to-atlassian-migration]] — the project's core architecture and decision rationale (one-EC2-per-app, shared RDS, SSM, AI-for-planning).
- [[hidden-dependency-graph]] — fix the trunk not the leaves: hidden couplings, transitive version breaks, non-local infra effects.
- [[cutover-gate-model]] — assess→clean→migrate→parity; gate on re-runnable checks, reconcile by anchor, non-destructive rollback.

## Synthesis

(populated as query answers are filed back)
