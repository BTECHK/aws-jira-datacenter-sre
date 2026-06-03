---
type: concept
title: "OSS-Toolchain → Atlassian Cloud Migration (architecture)"
tags: [architecture, migration, aws]
created: 2026-05-26
updated: 2026-06-03
sources: [readme]
---

# OSS-Toolchain → Atlassian Cloud Migration

> Synthesized from [[readme]].

The project's core thesis and architecture: model the real consolidation path organizations face — moving from self-managed open-source sprawl (Redmine, XWiki, Gitea) on AWS to a single managed Atlassian Cloud suite (Jira, Confluence, Bitbucket).

## Topology

nginx (reverse proxy + TLS) fronts three application EC2s — Redmine/Puma, XWiki/Tomcat, Gitea — all backed by one shared RDS PostgreSQL holding three isolated databases. Host access is via AWS SSM Session Manager (no SSH); secrets in Secrets Manager; monitoring via CloudWatch; AI planning on Amazon Bedrock (knowledge base on S3 Vectors).

## Architecture decisions and their rationale

- **One EC2 per application** — production-like isolation of scaling, patching, and upgrade blast-radius. Right-sized per workload (XWiki's JVM is the heavy one).
- **Shared RDS PostgreSQL, separate databases** — one managed data tier; one instance, three isolated DBs. A cost/isolation trade-off appropriate for a lab; the HA/DR path is **built in Phase 3** (RDS Multi-AZ), with the snapshot/PITR recovery story documented.
- **Minimum-viable sizing** — smallest practical instances; the lab demonstrates function, not load (~$8–12 total when stopping instances between sessions).
- **SSM Session Manager over SSH** — key-less, auditable host access with a smaller attack surface.
- **AI for migration *planning*, not ticket triage** — a Bedrock knowledge base grounds migration-readiness on best-practice checklists + the instance's own config. The genuinely useful place for AI here.
- **Deliberately old app versions** (e.g. Redmine 5.1) — so Phase 2's upgrades are real cross-boundary jumps (Ruby/Rails; Java 17→21 on Tomcat) with tested rollback.
- **Consistent naming + tagging** — `mds-tools-<service>` names with `Project`/`Environment`/`Service`/`ManagedBy` tags across all resources.

## The phases (five core + one optional)

1. **Foundation** — Terraform + Ansible provision the toolchain (3 app EC2s, shared RDS, nginx+TLS, SSM, CloudWatch, seeded data). See [[redmine]].
2. **Patch & Upgrade** — Linux patching + two major app upgrades with rollback.
3. **High Availability** — cluster Redmine (2 nodes + HAProxy + EFS shared home + RDS Multi-AZ) with failover + rolling-upgrade drills; the legacy HA topology the migration later retires.
4. **AI-Assisted Migration** — migrate to Cloud (Redmine→Jira REST/CSV, XWiki→Confluence XAR/REST, Gitea→Bitbucket git mirror) with parity validation via [[jiraops-cli]]; Bedrock drafts/refines the plan. Go-live per [[cutover-runbook]] and [[cutover-gate-model]].
5. **Enterprise Auth** — LDAP + SAML SSO via Keycloak.
6. **Day-2 ChatOps** *(optional)* — post-migration governance operated from Slack: notify on Jira activity, close tickets from Slack (modal → write-back to Jira), SLA escalation, scheduled access-review + control-hygiene checks, and a dashboard + audit log. A fenced, separable capstone on the migrated Jira Cloud.
