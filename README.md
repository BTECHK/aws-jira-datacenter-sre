# AWS Atlassian Data Center → Cloud Migration Lab

A hands-on lab that self-hosts the **Atlassian suite — Jira, Confluence, and Bitbucket Data Center — on AWS (Linux)**, operates it like a real platform (patching, version upgrades, backup/restore, SSO/LDAP), and **migrates it to Atlassian Cloud** using the official migration assistants — with an **AI-assisted migration-planning** component built on Amazon Bedrock.

**Author:** [Your Name] · **Cloud:** AWS · **OS:** Amazon Linux 2023

---

## Overview

Atlassian Data Center reaches end-of-life in **March 2029**, and many organizations that historically self-hosted (often for compliance reasons) are now moving to Atlassian Cloud. This project models that journey end to end:

1. **Stand up** the self-hosted Atlassian suite on AWS Linux — each product on its own host, fronted by a reverse proxy with TLS.
2. **Operate** it — Linux patching, a major Jira version upgrade with rollback, backup/restore, and enterprise identity (LDAP + SAML SSO).
3. **Migrate** the suite to Atlassian Cloud — Jira via **JCMA**, Confluence via **CCMA**, Bitbucket via Cloud import — and validate data parity.
4. **Plan with AI** — an Amazon Bedrock knowledge base grounds a migration plan on best-practice checklists and the instance's own configuration, surfacing gaps before cutover.

> **Scenario:** A fictional regulated organization, *Meridian Defense Systems*, migrating its self-hosted Atlassian suite to Cloud ahead of Data Center end-of-life.

---

## Architecture

```
                         ┌─────────────── nginx (reverse proxy + TLS) ───────────────┐
                         │                                                           │
   Internet ──HTTPS──►  ALB/nginx  ──►  EC2: Jira DC      ─┐
                                        EC2: Confluence DC ─┼──►  RDS PostgreSQL (3 databases)
                                        EC2: Bitbucket DC  ─┘
   Access: AWS SSM Session Manager (no SSH)        Secrets: AWS Secrets Manager
   Monitoring: Amazon CloudWatch                   AI: Amazon Bedrock (Knowledge Base on S3 Vectors)
                          │
                          └──► Migration: JCMA / CCMA / Bitbucket import ──► Atlassian Cloud
```

**Each product runs on its own EC2 instance** (as in production — independent scaling, patching, and upgrade blast-radius), sharing a single RDS instance with separate databases.

### Sizing — minimum-viable (this lab) vs. production reference

This lab is sized for **functional demonstration, not load** (no real users or performance testing), so it uses the smallest practical footprint. A production deployment would be substantially larger and clustered.

| Component | This lab (minimum viable) | Production reference |
|---|---|---|
| App hosts (×3) | `t3.medium` (single node each) | `t3.xlarge`+ / multi-node clusters |
| Database | one shared `db.t3.small` RDS, 3 databases | per-product, larger, HA/Multi-AZ |
| High availability | none (single node per product) | clustered (Hazelcast) + load balancing |
| TLS / ingress | nginx reverse proxy | nginx/ALB, WAF, hardened |

---

## Phases

| Phase | Focus |
|-------|-------|
| **1 — Foundation** | Provision the suite on AWS with Terraform + Ansible: 3 EC2 hosts, shared RDS, nginx + TLS, SSM access, CloudWatch, Application Links between products, seeded data. (Jira installed at an older LTS so Phase 2 has a real upgrade.) |
| **2 — Patch & Upgrade** | Linux patching (Ansible), backup/restore procedure, and a major Jira version upgrade (10.3 → 11.x, Java 17 → 21) with a tested rollback. |
| **3 — AI-Assisted Migration** | Migrate the suite to Atlassian Cloud (JCMA / CCMA / Bitbucket import) with parity validation; a Bedrock knowledge base drafts and refines the migration plan and flags pre-migration cleanup. |
| **4 — Enterprise Auth** | LDAP user directory + SAML SSO via Keycloak. Optional: a 2-node cluster with a zero-downtime rolling upgrade. |

---

## Tech Stack

| Category | Tools |
|----------|-------|
| **Cloud** | AWS — EC2 (×3), RDS PostgreSQL (shared), SSM, Secrets Manager, S3, CloudWatch, Bedrock (Knowledge Base on S3 Vectors) |
| **Linux** | Amazon Linux 2023 — systemd, JVM/heap tuning, `dnf` patching |
| **IaC / Config / CI** | Terraform, Ansible, GitHub Actions |
| **Applications** | Jira, Confluence, Bitbucket Data Center → Atlassian Cloud |
| **Migration** | JCMA (Jira), CCMA (Confluence), Bitbucket Cloud import; REST-based parity validation |
| **Identity** | LDAP directory + SAML SSO (Keycloak) |
| **Scripting** | Python (REST + parity tooling), Bash |

---

## Key Architecture Decisions

- **Self-hosted Data Center → Cloud:** models the real migration path organizations face ahead of DC end-of-life (March 2029).
- **One EC2 per product:** mirrors production — heavy JVM apps are isolated for independent scaling, patching, and upgrade blast-radius.
- **Shared RDS with separate databases:** a cost/isolation trade-off appropriate for a lab; production would separate (and likely cluster) the databases.
- **Minimum-viable sizing:** the lab demonstrates functionality without load, so it uses the smallest practical instances; the table above documents what production would use instead.
- **SSM Session Manager over SSH:** key-less, auditable host access with a smaller attack surface.
- **AI for migration *planning*, not ticket triage:** a grounded knowledge base assists migration readiness — the genuinely useful place for AI in this workflow.
- **Major Jira upgrade as the upgrade exercise:** the Java 17 → 21 jump (10.3 → 11.x) exercises the full upgrade/rollback process; Confluence/Bitbucket are installed at current stable versions.

---

## Repository Structure

```
aws-jira-datacenter-sre/
├── .github/workflows/        # CI (Terraform/Ansible validation)
├── docs/
│   ├── runbooks/             # Operational procedures
│   └── exercises/            # Evidence / screenshots per phase
├── jiraops-cli/              # Python CLI for Jira REST + migration parity checks
├── phases/
│   ├── phase-1-jiradc-foundation/   # terraform/ ansible/ confluence/ bitbucket/ scripts/
│   ├── phase-2-jiradc-upgrade/      # ansible/ backup/
│   ├── phase-3-jiradc-migration/    # jcma/ ecosystem/ validation/ ai/ cleanup/
│   └── phase-4-jiradc-auth/         # keycloak/ ldap/ cluster/
├── .gitignore
└── README.md
```

---

## Getting Started

**Prerequisites:**
- An AWS account (the lab runs ~$4–6/day at minimum-viable sizing; **stop instances between sessions**).
- Atlassian Data Center **trial licenses** (free, 30-day) for Jira, Confluence, and Bitbucket, from [my.atlassian.com](https://my.atlassian.com).
- Free Atlassian **Cloud** sites (Jira/Confluence/Bitbucket) as migration destinations.
- Local tooling: Terraform, Ansible, AWS CLI, Docker, Python 3, git.

**High-level steps:**
1. Provision the infrastructure (Phase 1) with Terraform; configure the hosts with Ansible.
2. Install the Atlassian suite, wire the reverse proxy + TLS, and connect Application Links.
3. Work through patching/upgrade (Phase 2), then the migration to Cloud (Phase 3).
4. Add LDAP + SSO (Phase 4).
5. Tear down (or stop) resources when done.

Each phase folder holds the infrastructure and configuration for that stage. Operational procedures live in `docs/runbooks/`.

---

## Cost

At minimum-viable sizing: roughly **$4–6/day** (3× `t3.medium` + one `db.t3.small` RDS) when running. Trial and Cloud-Free licenses are $0. Stop instances between sessions and tear down at the end to stay well within a small budget.

---

## License

Educational portfolio project. Provided as-is for reference and reuse.
