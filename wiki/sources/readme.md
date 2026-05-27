---
type: source
title: "Project README — AWS OSS-Toolchain → Atlassian Cloud Migration Lab"
tags: [architecture, migration, aws]
authors: [project-author]
url: null
raw: README.md
ingested: 2026-05-26
created: 2026-05-26
updated: 2026-05-26
sources: []
---

# Source: Project README

The repo's top-level README. Defines the lab: self-host a legacy OSS toolchain (Redmine, XWiki, Gitea) on AWS Linux, operate it (patching, upgrades, backup/restore, SSO/LDAP), and migrate it to Atlassian Cloud (Jira, Confluence, Bitbucket), with AI-assisted migration planning on Amazon Bedrock. Fictional scenario: *Meridian Defense Systems*, a regulated org consolidating onto Atlassian Cloud.

## Key points

- **Four phases:** (1) Foundation — provision toolchain on AWS via Terraform + Ansible; (2) Patch & Upgrade — Linux patching plus two major app upgrades with rollback (Redmine 5.1→6.1 across the Ruby/Rails boundary; XWiki LTS across Java 17→21); (3) AI-Assisted Migration — move to Atlassian Cloud with parity validation, Bedrock-grounded plan; (4) Enterprise Auth — LDAP + SAML SSO via Keycloak.
- **Topology:** nginx reverse proxy + TLS fronts three app EC2s (Redmine/Puma, XWiki/Tomcat, Gitea), all backed by one shared RDS PostgreSQL holding three databases. Access via SSM Session Manager (no SSH); secrets in Secrets Manager; monitoring via CloudWatch.
- **Migration mechanics:** Redmine→Jira (REST/CSV), XWiki→Confluence (XAR export + REST loader), Gitea→Bitbucket (git mirror); REST-based parity validation.
- **Cost discipline:** ~$8–12 total at minimum-viable sizing for a short project; stop instances between sessions.

## Architecture decisions captured

See [[oss-to-atlassian-migration]] for the consolidated decision rationale (one-EC2-per-app, shared RDS, minimum-viable sizing, SSM-over-SSH, AI-for-planning, deliberately-old versions).

## Related

- [[jiraops-cli]] — the Python CLI doing pre-migration assess/parity.
- [[cutover-runbook]] — the go-live runbook for the Redmine→Jira leg.
