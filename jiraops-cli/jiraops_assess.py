#!/usr/bin/env python3
"""
jiraops assess / clean — JCMA-style pre-migration assessment for the Redmine -> Jira Cloud leg.

Models the Jira Cloud Migration Assistant's "pre-migration checks / assessment report":
it scans the SOURCE (Redmine) for the data defects that block or corrupt a Cloud migration,
reports them, and (with `clean`) remediates them IN THE SOURCE so a re-run comes back clean.
That audit -> fix -> re-assess loop is the migration-readiness exercise.

Checks (the classic Jira Cloud blockers):
  - Email collisions      : two accounts share an email case-insensitively (Cloud merges/fails)
  - Placeholder emails    : blank / non-routable domains (localhost, invalid, example, test)
  - Dead projects         : open projects flagged dead/legacy that should be archived, not migrated
  - Missing Severity      : issues missing a value for the required custom field (import row fails)
  - Bad attribution       : issues assigned to a collision/placeholder user (-> Anonymous in Cloud)

Usage:
    python jiraops_assess.py whoami --base https://redmine.lab.local --key <API_KEY> --insecure
    python jiraops_assess.py assess --base https://redmine.lab.local --key <API_KEY> --insecure
    python jiraops_assess.py clean  --base https://redmine.lab.local --key <API_KEY> --insecure [--apply]

Auth: pass --key, or set REDMINE_API_KEY, or --secret <aws-secrets-manager-id> (boto3).
TLS:  --insecure for the lab's self-signed proxy cert.
Exit: assess returns 0 when clean, 2 when findings remain (usable as a CI/cutover gate).
"""
import argparse
import json
import os
import sys

import requests

PLACEHOLDER_DOMAINS = {"localhost", "invalid", "example.com", "example.org", "test", "local"}
DEAD_MARKERS = ("dead", "legacy", "decom", "obsolete")
SEVERITY_DEFAULT = "S3"


def session(base, key, insecure):
    s = requests.Session()
    s.headers = {"X-Redmine-API-Key": key, "Content-Type": "application/json"}
    if insecure:
        s.verify = False
        requests.packages.urllib3.disable_warnings()
    s.base = base.rstrip("/")
    return s


def get_all(s, path, root):
    """Paginate a Redmine list endpoint."""
    out, offset = [], 0
    while True:
        r = s.get(f"{s.base}/{path}", params={"offset": offset, "limit": 100, "status_id": "*"})
        r.raise_for_status()
        data = r.json()
        items = data.get(root, [])
        out += items
        offset += 100
        if offset >= data.get("total_count", len(out)) or not items:
            return out


def load_key(args):
    if args.key:
        return args.key
    if os.environ.get("REDMINE_API_KEY"):
        return os.environ["REDMINE_API_KEY"]
    if args.secret:
        import boto3  # only needed for the Secrets Manager path
        val = boto3.client("secretsmanager").get_secret_value(SecretId=args.secret)["SecretString"]
        try:
            return json.loads(val).get("redmine_api_key", val)
        except json.JSONDecodeError:
            return val
    sys.exit("No API key: pass --key, set REDMINE_API_KEY, or use --secret <secret-id>")


def severity_field_id(s):
    r = s.get(f"{s.base}/custom_fields.json")
    r.raise_for_status()
    for f in r.json().get("custom_fields", []):
        if f["name"].strip().lower() == "severity":
            return f["id"]
    return None


def domain_of(mail):
    return mail.rpartition("@")[2].lower() if "@" in (mail or "") else ""


def find_defects(s):
    f = {"email_collisions": [], "placeholder_emails": [], "dead_projects": [],
         "missing_severity": [], "bad_attribution": []}
    by_norm, bad_user_ids = {}, set()
    for u in get_all(s, "users.json", "users"):           # admin-only endpoint
        mail = (u.get("mail") or "").strip()
        if not mail or domain_of(mail) in PLACEHOLDER_DOMAINS:
            f["placeholder_emails"].append((u["id"], u.get("login"), mail))
            bad_user_ids.add(u["id"])
        if mail:
            by_norm.setdefault(mail.lower(), []).append((u["id"], u.get("login")))
    for norm, who in by_norm.items():
        if len(who) > 1:
            f["email_collisions"].append((norm, who))
            bad_user_ids.update(uid for uid, _ in who)

    for p in get_all(s, "projects.json", "projects"):
        if p.get("status", 1) == 1 and any(m in p.get("name", "").lower() for m in DEAD_MARKERS):
            f["dead_projects"].append((p["id"], p.get("identifier"), p.get("name")))

    sev_id = severity_field_id(s)
    for it in get_all(s, "issues.json", "issues"):
        cfs = {c["id"]: c.get("value") for c in it.get("custom_fields", [])}
        if sev_id is not None and not cfs.get(sev_id):
            f["missing_severity"].append((it["id"], it["subject"]))
        a = it.get("assigned_to")
        if a and a.get("id") in bad_user_ids:
            f["bad_attribution"].append((it["id"], it["subject"], a.get("name")))
    return f, bad_user_ids, sev_id


def cmd_assess(s):
    f, _, _ = find_defects(s)
    total = sum(len(v) for v in f.values())
    print("=== jiraops assess — pre-migration assessment report (Redmine -> Jira Cloud) ===\n")

    def section(title, items, fmt):
        print(f"[{'FAIL' if items else 'PASS'}] {title}: {len(items)}")
        for it in items[:10]:
            print("    - " + fmt(it))
        if len(items) > 10:
            print(f"    ... +{len(items) - 10} more")
        print()

    section("Email collisions (case-insensitive dup — Cloud merges/fails)", f["email_collisions"],
            lambda x: f"{x[0]} <- " + ", ".join(l for _, l in x[1]))
    section("Placeholder / non-routable emails (won't match a Cloud account)", f["placeholder_emails"],
            lambda x: f"user {x[1]} ({x[2] or 'BLANK'})")
    section("Dead projects not archived (archive, don't migrate)", f["dead_projects"],
            lambda x: f"{x[1]} — {x[2]}")
    section("Issues missing required Severity (Jira import row fails)", f["missing_severity"],
            lambda x: f"#{x[0]} {x[1]}")
    section("Issues attributed to a bad-email user (-> Anonymous/unassigned)", f["bad_attribution"],
            lambda x: f"#{x[0]} -> {x[2]}")
    verdict = "CLEAN — ready to migrate" if total == 0 else "NOT ready; run `clean --apply`, then re-assess"
    print(f"TOTAL findings: {total}  ->  {verdict}")
    return 0 if total == 0 else 2


def cmd_clean(s, apply):
    f, _, sev_id = find_defects(s)
    plan = []
    for _, who in f["email_collisions"]:
        plan += [("user", uid, {"mail": f"{login}@mds.local"}, f"unique email {login}@mds.local")
                 for uid, login in who]
    plan += [("user", uid, {"mail": f"{login}@mds.local"}, f"routable email {login}@mds.local")
             for uid, login, _ in f["placeholder_emails"]]
    plan += [("project", ident, {"status": 9}, f"archive {ident}")
             for _, ident, _ in f["dead_projects"]]
    if sev_id is not None:
        plan += [("issue", iid, {"custom_fields": [{"id": sev_id, "value": SEVERITY_DEFAULT}]},
                  f"set Severity={SEVERITY_DEFAULT}") for iid, _ in f["missing_severity"]]

    print(f"=== jiraops clean — {'APPLYING' if apply else 'DRY RUN (use --apply)'} {len(plan)} remediations ===")
    paths = {"user": "users", "project": "projects", "issue": "issues"}
    for kind, ident, body, desc in plan:
        print(f"  [{kind}] {ident}: {desc}")
        if apply:
            r = s.put(f"{s.base}/{paths[kind]}/{ident}.json", json={kind: body})
            if r.status_code not in (200, 204):
                print(f"      ! {r.status_code} {r.text[:120]}")
    if not apply and plan:
        print("\nDry run only — re-run with --apply, then `assess` to confirm 0 findings.")
    return 0


def main():
    ap = argparse.ArgumentParser(description="JCMA-style pre-migration assess/clean (Redmine -> Jira Cloud)")
    ap.add_argument("command", choices=["whoami", "assess", "clean"])
    ap.add_argument("--base", default=os.environ.get("REDMINE_BASE", "https://redmine.lab.local"))
    ap.add_argument("--key")
    ap.add_argument("--secret", help="AWS Secrets Manager secret id holding the Redmine API key")
    ap.add_argument("--insecure", action="store_true", help="skip TLS verify (lab self-signed cert)")
    ap.add_argument("--apply", action="store_true", help="clean: actually apply (default is dry-run)")
    args = ap.parse_args()

    s = session(args.base, load_key(args), args.insecure)
    if args.command == "whoami":
        u = s.get(f"{s.base}/users/current.json").json()["user"]
        print(f"Authenticated as {u.get('login')} ({u.get('mail')})")
        return
    sys.exit(cmd_assess(s) if args.command == "assess" else cmd_clean(s, args.apply))


if __name__ == "__main__":
    main()
