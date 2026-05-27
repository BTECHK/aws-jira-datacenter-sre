---
type: entity
title: "Redmine (lab instance)"
kind: application
tags: [operations, migration, aws]
created: 2026-05-26
updated: 2026-05-26
sources: [readme, phase-1-redmine-debrief, cutover-runbook]
---

# Redmine (lab instance)

The issue-tracking application in the OSS toolchain — the analog of Jira and the **protected core** of the migration. A Ruby/Rails app served by **Puma**, fronted by nginx + TLS, backed by the shared RDS PostgreSQL (`redmine` database).

## Lab specifics

- Installed at **version 5.1 deliberately** so Phase 2 has a real cross-boundary upgrade (Redmine 5.1 → 6.1, the Ruby/Rails boundary).
- Right-sized at `t3.small` (minimum-viable; production reference is `t3.large`+ / multi-node).
- In the as-built lab, co-located with Gitea on `mds-tools-redmine` (`10.20.10.106`): Gitea on `:3000`, Redmine moved to `:3001`; the dedicated `mds-tools-gitea` box (`.146`) sits empty. See the topology gotcha in [[phase-1-redmine-debrief]].

## Operational gotchas (Phase 1)

Standing it up took ~10 failed starts — all hidden couplings, not big bugs: service-account permissions on the gem cache, a transitive `concurrent-ruby` break against pinned Rails 6.1, `puma` excluded via a `:test`-group `--without`, a port clash with Gitea, and a systemd crash loop. The meta-lesson — fix the dependency graph at the common ancestor — is [[hidden-dependency-graph]].

## Migration

Source for the **Redmine → Jira Cloud** leg via REST/CSV, validated with [[jiraops-cli]] and executed per [[cutover-runbook]]. Rollback floor is an RDS snapshot + `pg_dump`; the source is only frozen read-only during cutover, never destroyed.
