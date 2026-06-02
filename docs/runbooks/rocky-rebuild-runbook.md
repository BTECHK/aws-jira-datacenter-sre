# Runbook — Rebuild the lab onto Rocky Linux 9 (from Amazon Linux 2023)

> **When to use:** your EC2 boxes are still **Amazon Linux 2023** but the Phase-1 IMPLEMENTATION-GUIDE (and Phases 2–5) are written for **Rocky Linux 9**. This runbook gets you from AL2023 boxes → fresh Rocky 9 boxes, then points you back into the existing guide to reinstall. It does **not** replace the install steps — those are already Rocky in the guide; this just orchestrates the cutover.
>
> **Run-from legend:** 🐧 WSL (Terraform/AWS CLI/Ansible) · 📦 box via SSM · 🪟 Windows (hosts file only)
>
> **Do this BEFORE seeding (Phase-1 Step 12).** `terraform apply -replace` **destroys and recreates** each EC2 — anything installed on the box is wiped. Pre-seed there's no lab data to lose, so the only cost is re-running the install steps. The longer you wait, the more you throw away.

---

## Why a rebuild is needed (and why it's per-box `-replace`, not a normal apply)

Your `ec2.tf` defaults every box to AL2023 and only puts a box on Rocky when you (a) pin `rocky_ami_id` and (b) list its service in `rocky_services`, then **force-replace** it. The `lifecycle { ignore_changes = [ami, user_data] }` block means a plain `terraform apply` will **never** swap a running box's OS — migration is deliberate and explicit. So you flip the variables, then `-replace` each instance: Terraform builds a brand-new EC2 on the Rocky AMI, and you reinstall on the blank box.

## What is and isn't destroyed

| Survives the rebuild | Destroyed / rebuilt |
|---|---|
| **RDS** + the 3 databases (not an EC2 — untouched) | The 3 app EC2s + the proxy EC2 |
| VPC, subnets, SGs, IAM, NAT, the dynamic Ansible inventory | Everything installed on those boxes (Gitea, Redmine, nginx, configs) |
| `tags` (Name/Service) → inventory still auto-discovers the new boxes | The instance IDs + **the proxy's public IP** (auto-assigned, changes) |

Because the **databases survive**, your reinstalled apps reconnect to the same `redmine`/`gitea`/`xwiki` DBs. Pre-seed that schema is just the apps' own tables — reuse it as-is, or drop+recreate for a pristine start (see R5).

---

## R1 — Find + pin an older Rocky 9 AMI
**▶ 🐧 WSL.** Pick a Rocky minor a couple behind newest, so Phase-2 `dnf` patching does real work.
```bash
aws ec2 describe-images --region us-east-1 \
  --filters "Name=name,Values=Rocky-9-EC2-Base-9.*x86_64*" "Name=state,Values=available" \
  --query 'reverse(sort_by(Images,&CreationDate))[*].[Name,ImageId,OwnerId,CreationDate]' --output table
```
Note an **older** 9.x `ImageId` (e.g. a 9.4 when 9.6 exists).

## R2 — Flip the Terraform variables
**▶ 🐧 WSL.** In `phases/phase-1-foundation/terraform/terraform.tfvars` (create if absent), set the uniform-Rocky end state:
```hcl
rocky_ami_id   = "ami-XXXXXXXXXXXXXXXXX"   # from R1
rocky_services = ["gitea", "xwiki", "redmine"]
rocky_proxy    = true
```
- The `precondition` in `ec2.tf` will block the apply if `rocky_services`/`rocky_proxy` are set without `rocky_ami_id` — that's the guard working.

## R3 — Rebuild every box onto Rocky (one apply)
**▶ 🐧 WSL.** Force-replace all four instances. The `-var my_ip` keeps your admin IP on the proxy SG's 443 rule:
```bash
cd phases/phase-1-foundation/terraform
terraform apply \
  -replace='aws_instance.app["gitea"]' \
  -replace='aws_instance.app["xwiki"]' \
  -replace='aws_instance.app["redmine"]' \
  -replace='aws_instance.proxy' \
  -var="my_ip=$(curl -s -4 https://ifconfig.me/ip)/32"
```
- Review the plan: it should show **4 instances replaced** (and nothing destroyed in the RDS/VPC/SG/IAM tier). Confirm.
- Grab the new outputs after apply: `terraform output` → new `proxy_public_ip` + `app_private_ips`.

## R4 — Post-rebuild checks (do these before reinstalling)
1. **SSM agent lag (Rocky-specific):** Rocky AMIs **don't preinstall** the SSM agent — the `user_data` installs it on first boot. Wait **~2–3 min**, then confirm each box is reachable: `aws ssm describe-instance-information --query 'InstanceInformationList[].[InstanceId,PingStatus,PlatformName]' --output table` (PlatformName should read **Rocky**).
2. **Confirm the OS:** 📦 on a box, `cat /etc/os-release` → `Rocky Linux 9.x`.
3. **Update hosts files with the NEW proxy IP** (it changed on replace): 🪟 Windows `C:\Windows\System32\drivers\etc\hosts` **and** 🐧 WSL `/etc/hosts` — repoint `git.lab.local`, `redmine.lab.local`, `wiki.lab.local` to the new `proxy_public_ip`.

## R5 — Reinstall on the fresh Rocky boxes (back to the Phase-1 guide)
The install steps are already Rocky — just re-run them on the new boxes, in order:

| Re-run | Phase-1 guide step | Notes |
|---|---|---|
| Base prep all 3 hosts | **Step 3** | Dynamic inventory re-discovers the new boxes by `Service` tag — no inventory edit. |
| Gitea | **Step 4** | — |
| Redmine | **Step 5** | Reuses the existing `redmine` DB. The `rake db:migrate` is idempotent if the version matches. |
| nginx + TLS | **Step 6** | New self-signed cert on the new proxy box. |
| XWiki | **Step 7** | The heavy one; you hadn't reached it yet. |

- **Step 2 (databases): do NOT redo** — RDS survived. **Optional clean slate:** since you're pre-seed, you *may* drop + recreate the `redmine`/`gitea` DBs (per Step 2) so the fresh installs initialize cleanly; only do this if a reused DB gives you trouble.
- **Rocky-vs-AL2023 reinstall differences are already handled in the guide** — they're the reason the rebuild matters: SELinux is **enforcing** (nginx needs `httpd_can_network_connect`; the guide sets it), Ruby comes from a **dnf module stream** (`ruby:3.1`) not a package, the SSM-agent user_data above, and `openldap-clients`/`nfs-utils` naming later. If a command "from memory" fails, it's probably an AL2023-ism — follow the guide's Rocky form.

## R6 — Resume normal Phase 1
Once Steps 3–7 are green on Rocky, continue the guide straight through: **Step 8** (verify Gitea over HTTPS) → **9** (CloudWatch) → **10** (CI) → **11** (3 Redmine custom fields) → **12** (seed data) → Phase 2.

---

## Rollback / safety
- If a box won't come back, you can `-replace` just that one again, or temporarily drop its service from `rocky_services` to rebuild it on AL2023 (the AMI flips back). The RDS is never touched by these `-replace`s.
- Take a quick RDS snapshot first only if you've created data you care about — pre-seed you haven't, so skip it.
