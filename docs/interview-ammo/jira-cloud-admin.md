# Jira Cloud Admin — Interview Ammo

> Reference/cheat-sheet for the **Senior Atlassian Infrastructure Engineer** interview. Framed against the MDS reality: a regulated (ITAR/CMMC) defense contractor consolidating an OSS toolchain onto Atlassian Cloud. The senior signal is knowing the **org-vs-product admin split**, **identity/security (Atlassian Guard)**, **data residency / Government Cloud**, and **what changes when you give up the box** (DC→Cloud delta).
>
> Atlassian renames things often (Access→Guard, next-gen→team-managed). Names below are current as of the lab; verify edition-gated features against the current pricing/admin docs.

---

## 1. The admin hierarchy (the #1 "do you actually know Cloud" question)

DC had **one** admin plane (the app's own admin + the server). Cloud splits it:

| Tier | Where | Controls |
|---|---|---|
| **Organization admin** | `admin.atlassian.com` (**Atlassian Administration**) | Managed accounts, verified domains, **security/identity (Guard)**, billing, data residency, audit log, product/site creation — **spans all products** (Jira, Confluence, Bitbucket) |
| **Site / Product admin** | `yoursite.atlassian.net` → Settings | A single Cloud **site** and the products on it: global Jira config (schemes, fields, workflows), users' product access |
| **Project / Space admin** | within a project | Project roles, components, project-scoped permissions/automation |

- A **site** = one Cloud instance (`yourorg.atlassian.net`). An **org** can own multiple sites (Enterprise edition).
- *"Where do I create users / enforce SSO?"* → **org** (admin.atlassian.com). *"Where do I build a workflow scheme?"* → **product/site** admin. Mixing these up is the classic Cloud-newcomer tell.

---

## 2. Identity & security — **Atlassian Guard** (formerly Atlassian Access)

Org-level subscription that turns Atlassian's consumer-style accounts into an enterprise-governed directory. **This is how MDS meets its identity obligations.**

- **SSO** — **SAML** *and* **OIDC** to your IdP (Okta/Entra/Keycloak). Federated login for managed accounts.
- **SCIM provisioning** — auto create/update/**deactivate** users + push groups from the IdP. (Answers "auth vs provisioning": SSO authenticates; SCIM provisions — you need both for lifecycle.)
- **Enforced 2FA**, password policies, **authentication policies** (apply different rules to subsets of users — e.g. service accounts vs humans).
- **IP allowlists** (Guard Premium), **data security policies** (block export/public-share/app-access on sensitive content), **org audit log**, and **Guard Detect** (anomaly/data-exfil detection) in Premium.
- **Managed accounts via verified domains:** claim/verify your email domain → every account on it becomes **managed**, so the policies above actually bind. *No verified domain = you can't enforce anything.*

> **Lockout risk (have the recovery answer ready):** misconfigured SSO/authentication policy can lock admins out. Mitigation: keep a **break-glass admin** on a non-SSO authentication policy, and Atlassian's SSO-bypass recovery URL. This is the Cloud analog of the on-prem "don't lock yourself out of LDAP" rule.

---

## 3. Regulated context — data residency & Government Cloud (MDS-critical)

- **Data residency:** pin a product's in-scope data to a **region** (US, EU, Australia, Germany, …); Atlassian performs a realm move. Covers core product data — **confirm what's in scope vs. out** (some data/ancillary services may not be pinned).
- **Atlassian Government Cloud:** a **separate** offering (not commercial Cloud) running in **AWS GovCloud**, **FedRAMP Moderate authorized** — the relevant path for ITAR/CMMC workloads like MDS. Distinct sign-up, product subset, and feature parity caveats vs. commercial Cloud.
- **Commercial Cloud compliance** (for the non-regulated story): SOC 2, ISO 27001/27018, plus BYOK encryption (Enterprise) — but FedRAMP-scoped workloads belong on **Government Cloud**, not commercial.
- *Senior framing:* *"The thing that unblocked this migration is that Cloud now has a FedRAMP-authorized path (Government Cloud) plus data-residency and Guard — that's what closed the gap that kept us self-hosted. I'd put the ITAR-scoped products on Government Cloud and confirm the in-scope-data boundary, not assume commercial Cloud covers it."*

---

## 4. Editions & change control (Premium/Enterprise = the admin tools)

| Capability | Edition | Why it matters |
|---|---|---|
| **Sandbox** (copy of prod for testing) | Premium/Enterprise | Test config/migration/app changes safely — your "lower environment" in a world with no staging server you control |
| **Release tracks** | Premium/Enterprise | **Batch and delay** Atlassian's feature changes (instead of continuous auto-rollout); preview in sandbox first — this is how you regain *change control* you lost going Cloud |
| **Multiple instances / unlimited automation / data residency options** | Enterprise | Multi-site governance under one org |
| **Standard** | — | Core; limited automation executions, no sandbox/release tracks |

- *"How do you test before prod when Atlassian controls upgrades?"* → **sandbox + release tracks** (Premium+). On Standard you can't fully batch changes — a real reason to size up for a regulated org.

---

## 5. Jira config admin (and the DC→Cloud nuances)

- **Company-managed vs team-managed projects** — the defining Cloud distinction:
  - **Company-managed** = admin-owned **shared schemes** (workflow/permission/notification schemes) — the DC mental model; **JCMA migrates into these**.
  - **Team-managed** = team-owned, **independent** config, simplified roles — flexible but ungoverned; **not a migration target**.
- **Permission model:** company-managed still uses **permission schemes** (Cloud didn't throw these away); team-managed uses simplified project roles. (The "Cloud simplified everything" claim is only true for team-managed.)
- **Custom fields + contexts:** Cloud-specific hygiene — **global contexts across many fields hurt performance**; scope contexts to projects. (This is the `jiraops audit-fields` hook from the migration assessment.)
- Workflows/workflow schemes, screens/field configs, issue-type schemes — all still exist; the editor UI differs from DC.
- **Automation for Jira is native** in Cloud (no app needed) — it replaces a lot of DC Marketplace apps (the migration "Cloud-native replaces it" bucket).

---

## 6. API, integration & extensibility

- **Auth:** **API token** (HTTP basic = email + token) for scripts; **OAuth 2.0 (3LO)** for apps acting as users; **Connect** (remote, descriptor-based) and **Forge** (Atlassian-hosted, FaaS) for building apps.
- **REST API v3** (Jira Cloud platform). **Cost-based rate limits** — design for backoff (`429` + `Retry-After`), exactly like the lab's `jiraops`/seed scripts throttle.
- *DC→Cloud delta:* you **lose direct DB/filesystem access** — no SQL against the Jira DB, no log/file tweaks. Everything programmatic goes through the **REST API**. (This is why the migration is API-driven extraction, not a DB dump.)

---

## 7. Backup / DR in Cloud (know the limits)

- Atlassian **manages** backups, HA, and DR — **RTO/RPO are theirs**, not yours.
- Admins can run a **manual data export** (for portability/cold copy) but there is **no self-service point-in-time restore** — you can't "restore last Tuesday." Design around it: rely on Atlassian's recovery SLAs, keep periodic exports, and use **sandbox** for change rehearsal.
- *Contrast with the lab:* in Phase 2 you owned `pg_dump` + RDS snapshots + a tested restore. In Cloud you **give that up** — a genuine trade-off to articulate: less operational burden, less control over recovery granularity.

---

## 8. The DC → Cloud admin shift (the senior-signal summary)

| You had (DC / self-hosted) | You get (Cloud) |
|---|---|
| Root on the box; tune JVM/`setenv.sh`, app server, OS | No server access — Atlassian operates it |
| Direct DB access / SQL | **REST API only** |
| You schedule + test upgrades | Atlassian rolls out continuously; **release tracks + sandbox** are your control surface |
| You own backups/restore (pg_dump, snapshots) | **Managed**; manual export only, no PITR-by-you |
| One admin plane | **Org (identity/security/billing) vs product (config)** split |
| Marketplace apps install freely | App must have a **Cloud** version + a data-migration path; native Automation/Forge often replaces |
| Your own LDAP/SAML wiring | **Atlassian Guard** (SAML/OIDC + SCIM + policies) |
| Compliance = your responsibility | **Government Cloud (FedRAMP)** + data residency + Guard |

---

## 9. Likely interview Q&A

- **"Org admin vs site/product admin?"** → Org (`admin.atlassian.com`) = identity, security, billing, residency across all products; site/product = the config (schemes, fields, workflows) of one instance.
- **"How do you do SSO and user lifecycle in Cloud?"** → **Atlassian Guard**: SAML/OIDC for login, **SCIM** for provisioning/deprovisioning + group sync, enforced via **verified domains + authentication policies**. SSO ≠ provisioning — you need both.
- **"How does a defense contractor run Atlassian Cloud at all?"** → **Government Cloud** (FedRAMP Moderate, AWS GovCloud) for ITAR-scoped products, **data residency** pinning, **Guard** for zero-trust identity, BYOK on Enterprise — and verify the in-scope-data boundary rather than assuming commercial Cloud qualifies.
- **"How do you change-manage a platform you don't control the upgrades of?"** → **Sandbox + release tracks** (Premium/Enterprise): preview Atlassian's changes in sandbox, batch them into prod on a track instead of continuous auto-rollout.
- **"How do you back up Jira Cloud?"** → You don't, in the DC sense — Atlassian manages DR; admins get a **manual export**, no self-service PITR. Design around the managed SLA and rehearse changes in sandbox.
- **"company-managed vs team-managed?"** → Shared admin-controlled schemes (DC-like, JCMA target) vs independent team-controlled config. Pick company-managed for a governed, migrated platform.
- **"What replaces our Marketplace apps?"** → Cloud version + vendor data migration where it exists; otherwise **native Automation** or a **Forge/Connect** build, or accept the loss — assessed up front (see `app-and-ecosystem-assessment.md`).
