# AWS OSS-Toolchain → Atlassian Cloud Migration Lab

A hands-on lab that self-hosts a **legacy open-source toolchain — Redmine, XWiki, and Gitea — on AWS (Linux)**, operates it like a real platform (patching, a major application upgrade, backup/restore, SSO/LDAP), and **migrates it to the Atlassian Cloud suite** (Jira, Confluence, Bitbucket) — with an **AI-assisted migration-planning** component built on Amazon Bedrock.

**Author:** [Your Name] · **Cloud:** AWS · **OS:** Amazon Linux 2023

---

## Overview

Many organizations that historically self-hosted open-source tools (often for compliance reasons) are consolidating onto a single managed Cloud suite. This project models that journey end to end:

1. **Stand up** a self-hosted OSS toolchain on AWS Linux — issue tracking (Redmine), documentation (XWiki), and source control (Gitea), each on its own host, fronted by a reverse proxy with TLS, backed by managed PostgreSQL.
2. **Operate** it — Linux patching, two major application upgrades across runtime/framework version boundaries (Ruby/Rails and Java/JVM) with rollback, backup/restore, and enterprise identity (LDAP + SAML SSO).
3. **Migrate** the toolchain to Atlassian Cloud — Redmine → Jira, XWiki → Confluence, Gitea → Bitbucket — and validate data parity.
4. **Plan with AI** — an Amazon Bedrock knowledge base grounds a migration plan on best-practice checklists and the instance's own configuration, surfacing gaps before cutover.

> **Scenario:** A fictional regulated organization, *Meridian Defense Systems*, consolidating its self-hosted open-source toolchain onto Atlassian Cloud.

---

## Architecture

```
                         ┌─────────────── nginx (reverse proxy + TLS) ───────────────┐
                         │                                                           │
   Internet ──HTTPS──►  nginx  ──►  EC2: Redmine (Puma)  ─┐
                                    EC2: XWiki (Tomcat)   ─┼──►  RDS PostgreSQL (3 databases)
                                    EC2: Gitea            ─┘
   Access: AWS SSM Session Manager (no SSH)        Secrets: AWS Secrets Manager
   Monitoring: Amazon CloudWatch                   AI: Amazon Bedrock (Knowledge Base on S3 Vectors)
                          │
                          └──► Migration: REST/CSV · XAR ETL · git mirror ──► Atlassian Cloud
```

**Each application runs on its own EC2 instance** (as in production — independent scaling, patching, and upgrade blast-radius), sharing a single RDS instance with separate databases.

### Sizing — minimum-viable (this lab) vs. production reference

This lab is sized for **functional demonstration, not load** (no real users or performance testing), so it uses the smallest practical footprint per workload. A production deployment would be substantially larger and clustered.

| Component | This lab (minimum viable) | Production reference |
|---|---|---|
| Redmine host | `t3.small` | `t3.large`+ / multi-node |
| XWiki host (JVM/Tomcat) | `t3.medium` | `t3.xlarge`+ / clustered |
| Gitea host | `t3.small` | `t3.medium`+ |
| Database | one shared `db.t3.micro` RDS, 3 databases | per-app, larger, HA/Multi-AZ |
| High availability | none (single node per app) | clustered + load balancing |
| TLS / ingress | nginx reverse proxy | nginx/ALB, WAF, hardened |

---

## Phases

| Phase | Focus |
|-------|-------|
| **1 — Foundation** | Provision the toolchain on AWS with Terraform + Ansible: 3 right-sized EC2 hosts, shared RDS, nginx + TLS, SSM access, CloudWatch, and realistic seeded data in each app. (Redmine and XWiki installed at older versions so Phase 2 has real upgrades.) |
| **2 — Patch & Upgrade** | Linux patching (Ansible), backup/restore procedure, and **two major application upgrades, each with a tested rollback** — **Redmine 5.1 → 6.1** (Ruby/Rails boundary) and a **major XWiki LTS upgrade across Java 17 → 21** on Tomcat. |
| **3 — High Availability** | Cluster Redmine (the Jira analog) as **2 nodes behind HAProxy** with sticky sessions + health-checked failover, a **shared EFS home**, and **RDS Multi-AZ** — the legacy HA topology operated *before* migrating. Proven failover + rolling-upgrade drills. |
| **4 — AI-Assisted Migration** | Migrate the toolchain to Atlassian Cloud (Redmine→Jira via REST/CSV, XWiki→Confluence via export/ETL, Gitea→Bitbucket via git mirror) with parity validation; a Bedrock knowledge base drafts and refines the migration plan and flags pre-migration cleanup. Migrating *retires* the Phase-3 HA cluster (HA/DR becomes Atlassian-managed). |
| **5 — Enterprise Auth** | LDAP user directory + SAML SSO via Keycloak. |

---

## Tech Stack

| Category | Tools |
|----------|-------|
| **Cloud** | AWS — EC2 (×3), RDS PostgreSQL (shared), SSM, Secrets Manager, S3, CloudWatch, Bedrock (Knowledge Base on S3 Vectors) |
| **Linux** | Amazon Linux 2023 — systemd, JVM/heap tuning, `dnf` patching |
| **IaC / Config / CI** | Terraform, Ansible, GitHub Actions |
| **Applications** | Redmine, XWiki, Gitea → Atlassian Cloud (Jira, Confluence, Bitbucket) |
| **Migration** | Redmine REST + CSV import; XWiki XAR export + REST loader; Gitea → Bitbucket git mirror; REST-based parity validation |
| **Identity** | LDAP directory + SAML SSO (Keycloak) |
| **Scripting** | Python (REST + parity tooling), Bash |

---

## Key Architecture Decisions

- **Self-hosted OSS toolchain → Atlassian Cloud:** models the real consolidation path organizations face — moving from self-managed open-source sprawl to a single managed suite.
- **One EC2 per application:** mirrors production — applications are isolated for independent scaling, patching, and upgrade blast-radius. Right-sized per workload (XWiki's JVM is the heavy one).
- **Shared RDS PostgreSQL with separate databases:** managed data tier matching the standard AWS reference pattern; one instance hosts three isolated databases — a cost/isolation trade-off appropriate for a lab. HA/DR path (Multi-AZ + automated snapshots/PITR) is documented.
- **Minimum-viable sizing:** the lab demonstrates functionality without load, so it uses the smallest practical instances; the table above documents what production would use instead.
- **Consistent resource naming + tagging:** `mds-tools-<service>` names with `Project`/`Environment`/`Service`/`ManagedBy` tags across all resources — production-style and traceable.
- **SSM Session Manager over SSH:** key-less, auditable host access with a smaller attack surface.
- **AI for migration *planning*, not ticket triage:** a grounded knowledge base assists migration readiness — the genuinely useful place for AI in this workflow.
- **Major application upgrades as the upgrade exercise:** two reps on two stacks — the Redmine 5.1 → 6.1 jump (Ruby/Rails boundary) on the Jira analog backs the *upgrade-then-migrate* story, and the XWiki LTS jump across Java 17 → 21 on Tomcat exercises a JVM-boundary upgrade with the `setenv.sh`-wiped gotcha; Gitea runs at recent stable.

---

## Repository Structure

```
aws-jira-datacenter-sre/
├── .github/workflows/        # CI (Terraform/Ansible validation)
├── docs/
│   ├── runbooks/             # Operational procedures
│   └── exercises/            # Evidence / screenshots per phase
├── jiraops-cli/              # Python CLI: JCMA-style pre-migration assess/clean + REST extraction + parity checks
├── phases/
│   ├── phase-1-foundation/   # terraform/ ansible/ seed/ scripts/
│   ├── phase-2-upgrade/      # ansible/ backup/
│   ├── phase-3-ha/           # ansible/ (EFS-mount + HAProxy) terraform/ breaks/ scripts/
│   ├── phase-4-migration/    # redmine-jira/ xwiki-confluence/ gitea-bitbucket/ ai/ validation/
│   └── phase-5-auth/         # keycloak/ ldap/
├── .gitignore
└── README.md
```

---

## Getting Started

**Prerequisites:**
- An AWS account (the lab runs roughly $8–12 total at minimum-viable sizing for a short project; **stop instances between sessions**. The Phase-3 HA additions — 2nd node + EFS + RDS Multi-AZ — add a little while up; tear them down after the drills).
- Free Atlassian **Cloud** sites (Jira / Confluence / Bitbucket) as migration destinations.
- Local tooling: Terraform, Ansible, AWS CLI, Docker, Python 3, git.

**High-level steps:**
1. Provision the infrastructure (Phase 1) with Terraform; configure the hosts with Ansible.
2. Install the OSS toolchain, wire the reverse proxy + TLS, and seed realistic data.
3. Work through patching/upgrade (Phase 2), then cluster Redmine for HA (Phase 3), then the migration to Cloud (Phase 4).
4. Add LDAP + SSO (Phase 5).
5. Tear down (or stop) resources when done.

Each phase folder holds the infrastructure and configuration for that stage. Operational procedures live in `docs/runbooks/`.

---

## Cost

At minimum-viable sizing: roughly **$8–12 total** for a short (7–10 day) project when stopping instances between sessions (~$25–30 if left running 24×7). Atlassian Cloud Free destinations are $0. Stop instances between sessions and tear down at the end to stay well within a small budget. **The Phase 3 (HA) additions** — a 2nd Redmine `t3.small`, an EFS filesystem, and **RDS Multi-AZ** (≈doubles the RDS portion while on) — raise this incrementally only while they're up; they're meant to be torn down after the failover/rolling-upgrade drills.

---

## License

Educational portfolio project. Provided as-is for reference and reuse.
