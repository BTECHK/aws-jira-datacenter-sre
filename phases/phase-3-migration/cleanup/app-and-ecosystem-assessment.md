# App & Ecosystem Assessment — DC → Cloud

> The companion to the data-cleanliness checklist (`README.md`) and `jiraops assess`. Those cover **records** (users, issues, fields-populated). This covers the **ecosystem around the records** — Marketplace apps and the config objects (workflows, automation, dashboards, schemes) that the migration assistants either carry, partially carry, or leave behind.
>
> **Why it's here even though the lab can't run it.** MDS's source is OSS (Redmine/XWiki/Gitea) with **zero Atlassian Marketplace apps**, so there is literally nothing for a JCMA app-assessment to scan. That's the point: in a *real* Jira/Confluence DC→Cloud migration the **app assessment is the single biggest scoping risk** — apps don't auto-migrate, many have no Cloud equivalent, and app *data* migration is separate from re-installing the app. This doc demonstrates the process by contrast and maps it onto the analog the OSS source *does* have: **Redmine plugins and XWiki extensions**.
>
> ⚠️ JCMA/CCMA coverage changes release to release — treat the tables below as the **categories to check**, and confirm specifics against Atlassian's current migration support matrix at assessment time.

---

## 1. The app-assessment process (inventory → classify → decide)

On a real DC instance you'd start from **UPM** (Manage apps → User-installed) or the **JCMA pre-migration app-assessment report**, which lists every installed app with a Cloud-availability verdict. The work is to put each app in a bucket and record a decision.

**Inventory** every user-installed app (ignore Atlassian-bundled): name, vendor, version, who uses it, what it touches (fields? workflows? UI? data?).

**Classify** into the standard buckets:

| Bucket | Meaning | Decision |
|---|---|---|
| **Cloud version exists + vendor migration path** | Same app on Cloud *and* the vendor ships a data-migration tool | Install on Cloud, run the vendor's migration, validate app data separately |
| **Cloud version exists, config-only (no data)** | App re-installs but has no portable data | Install + re-configure by hand; no data step |
| **Needs assessment / partial** | Cloud version exists but feature gaps or paid-tier differences | Document the gap; get a user decision before committing |
| **No Cloud equivalent** | App is DC-only or discontinued | Replace with a Cloud-native feature, rebuild, or accept the loss |
| **Cloud-native replaces it** | A built-in Cloud feature now does the job (e.g. **Automation for Jira** is native in Cloud; ScriptRunner-style behaviours often map to automation/Forge) | Decommission the app; rebuild its logic in the native feature |
| **No longer needed** | Stale/unused | Decommission at the source — don't carry it |

**The trap:** "the app is available on Cloud" ≠ "the app's data migrates." Re-installing the app gives you an empty app. Data migration is a *separate*, vendor-specific step — and for some apps it doesn't exist at all.

---

## 2. The OSS analog — source-side plugins/extensions (what this lab actually has)

Marketplace apps have a direct analog here, and the same assess→classify→decide discipline applies:

| Source | Plugin/extension surface | Where to inventory | Migration impact |
|---|---|---|---|
| **Redmine** | Ruby plugins under `plugins/`, schema migrations via `redmine:plugins:migrate` | `plugins/` dir; `Administration → Plugins` | A plugin that adds a tracker/field/workflow is **invisible to a plain CSV export** — its data must be mapped into Jira's native equivalent or dropped. A plugin incompatible with Rails 7.2 also **breaks the Phase-2 upgrade** `db:migrate` (migrate core first, add plugins back one at a time). |
| **XWiki** | Extensions via Extension Manager (e.g. the **LDAP/OIDC authenticators** added in Phase 4) | `Administration → Extensions` | Macros/extensions are the **loss-ledger drivers** for the Confluence leg — XWiki macros have no Confluence equivalent; assess each, rebuild-or-drop. |
| **Gitea** | Minimal (no rich plugin ecosystem) | n/a | Mostly N/A — git history is portable; metadata (PRs/issues/webhooks) is the thing left behind, not "apps." |

**The lab's honest answer:** the seeded instances are plugin-light by design, so the app/plugin assessment is mostly a **no-op on the data** — but the *discipline* (inventory, classify, decide, document) is what you'd carry into a real DC instance, and the Redmine-plugin-breaks-the-upgrade and XWiki-macro-loss-ledger cases are the live demonstrations.

---

## 3. Ecosystem objects — what JCMA/CCMA carry vs. what you rebuild

Even with **zero apps**, a migration is not "just the issues." The configuration *around* the issues is where post-cutover surprises live. Verdicts below are the categories to confirm against the current support matrix:

| Object | Migration-assistant behavior | Your action |
|---|---|---|
| **Issues, comments, attachments** | Carried (JCMA) | Validate by **counts/keys/content** via `jiraops parity` — never IDs |
| **Users & groups** | Carried; **keyed by email**, and managed/SSO requires **Atlassian Guard** | Already gated by the `assess`/cleanup checklist (unique + routable emails) |
| **Custom fields + their *contexts*** | Carried, but **global contexts** are a Cloud performance/anti-pattern | Audit contexts; consolidate before migrating (`jiraops audit-fields` flags global-context fields) |
| **Workflows & workflow schemes** | Carried *with the project*; Cloud status/resolution model differs | Pre-build the **status-consolidation map** (already in the field-map step) |
| **Screens & field configurations** | Carried with the project | Verify required-field rules survive (a required field with no default = failed import rows) |
| **Permission & notification schemes** | Partial / project-scoped | Re-map to Cloud's model; note **company-managed vs team-managed** (see below) |
| **Automation rules** | **Often NOT fully carried** (global/multi-project rules especially) | Inventory and **rebuild in Cloud-native Automation** — also where decommissioned apps' logic lands |
| **Dashboards, filters & their subscriptions** | Partial / optional | Rebuild gadgets; **re-create email subscriptions** (a silent gap users notice on day 2) |
| **Boards & sprints (Jira Software)** | Partial — board config/filters may not survive cleanly | Recreate boards; verify sprint/velocity history |
| **Webhooks & integrations** | **Not carried** | Inventory every outbound integration; **re-point to the Cloud base URL + API-token/OAuth auth** (a cutover step) |
| **Marketplace apps + app data** | **NOT carried by JCMA** | Section 1 — separate per-app path |

**Company-managed vs team-managed projects (a Cloud-specific gotcha):** JCMA migrates into **company-managed** projects (shared schemes — the DC mental model). **Team-managed** projects configure independently and aren't a migration target. Decide the target project style up front; it changes how schemes/permissions map.

---

## 4. Where this plugs in

- **Feeds** the data-cleanliness checklist (`README.md` §4 *Ecosystem parity*) — that section's two bullets expand into this doc.
- **`jiraops audit-fields`** (planned) automates the custom-field-context scan on the Jira side; today, do it by hand in **Settings → Issues → Custom fields** (look for fields with a **global** context that should be project-scoped).
- **Gates** the cutover: any "no Cloud equivalent" app or un-rebuilt automation/integration is a **NO-GO line item** on `docs/runbooks/cutover-runbook.md` until resolved or explicitly accepted.

---

## 5. Interview soundbites

- *"The app assessment is the part that sinks DC→Cloud timelines — not the issues. I inventory every user-installed app, classify it (Cloud version? vendor data-migration path? native replacement? drop?), and the key distinction is **app-available ≠ app-data-migrates** — re-installing gives you an empty app."*
- *"JCMA carries records and project-scoped config; it does **not** carry apps, most automation, integrations/webhooks, or filter subscriptions — those I rebuild and re-point at cutover. Naming what the assistant *won't* do is how you avoid a day-2 surprise."*
- *"Our source was OSS with no Marketplace apps, so the app data assessment was a no-op — but the same discipline caught a Redmine plugin that would've broken the Rails 7.2 upgrade, and the XWiki macros that drove the Confluence loss ledger."*
- *"On Cloud I watch custom-field **contexts** — global contexts across hundreds of fields are a real performance and hygiene problem, so I consolidate before migrating, not after."*
