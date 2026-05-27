# Project Learnings

Working memory for the `aws-jira-datacenter-sre` lab. Read at the start of every task; update after every task. When an entry has been confirmed multiple times or is older than 30 days, graduate it into a `wiki/` page and replace the entry here with a one-line reference. Keep this file lean (under 50KB).

## What Has Worked

- _(nothing recorded yet)_

## What Has Failed

- _(nothing recorded yet)_

## Patterns and Preferences

- **Tech stack (inferred from the codebase, 2026-05-26):** AWS-hosted lab provisioned with **Terraform** (`phases/phase-1-foundation/terraform/` — `ec2.tf`, `rds.tf`, `network.tf`, `sg.tf`, `iam.tf`, `versions.tf`) and configured with **Ansible** (`ansible/` — `prep.yml`, `gitea.yml`, dynamic `inventory.aws_ec2.yml`). Applications: **Redmine, XWiki, Gitea** on Amazon Linux 2023, migrating to **Atlassian Cloud** (Jira, Confluence, Bitbucket). Migration tooling is a **Python CLI** (`jiraops-cli/jiraops_assess.py`) doing JCMA-style pre-migration assess/parity checks. CI via **GitHub Actions**. AI-assisted migration planning on **Amazon Bedrock**.
- **Architectural decisions (inferred from `README.md`):**
  - **One EC2 per application** — isolates scaling/patching/upgrade blast-radius, as in production.
  - **Shared RDS PostgreSQL with separate databases** — one `db.t3.micro` hosts three isolated DBs; a cost/isolation trade-off appropriate for a lab.
  - **Minimum-viable sizing** — smallest practical instances; demonstrates function, not load.
  - **SSM Session Manager over SSH** — key-less, auditable host access, smaller attack surface.
  - **AI for migration *planning*, not ticket triage** — a Bedrock knowledge base grounds migration-readiness on best-practice checklists + the instance's own config.
  - **Deliberately old app versions** (Redmine 5.1) so Phase 2 has real cross-boundary upgrades to perform.
- **Knowledge-stack convention (2026-05-26):** this project runs a three-layer knowledge stack — `learnings.md` (volatile working notes, here), `wiki/` (curated, durable knowledge via the `llm-wiki` skill), and `.gitnexus/` (code knowledge graph). Mature learnings graduate from here into `wiki/`. See [[oss-to-atlassian-migration]] for the architecture overview.

## Open Questions

- _(nothing recorded yet)_
