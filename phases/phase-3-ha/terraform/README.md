# Phase 3 (HA) — Terraform lives in the Phase-1 stack

**This directory is a pointer, not a second Terraform state.**

The HA infrastructure changes are **added to the single existing stack** in
[`phases/phase-1-foundation/terraform/`](../../phase-1-foundation/terraform/) so there is **one** state file
(adding a second state that references the same VPC/subnets/SGs would be fragile and is deliberately avoided).

The HA additions (see the Phase-3 guide, Step 1) are:

| Change | File in the phase-1 stack |
|---|---|
| EFS shared home + 2 mount targets (one per AZ) + output | new `efs.tf` |
| `multi_az = true` (RDS standby in the other AZ) | edit `rds.tf` |
| 2nd Redmine node (`aws_instance.redmine_b`) in `private_b`, tagged `Service=redmine` | edit `ec2.tf` |
| EFS security group (2049 from the app SG) | edit `sg.tf` |

Apply them from `phases/phase-1-foundation/terraform/` with the usual `terraform plan` / `apply`.
The HA **Ansible** (EFS-mount + HAProxy plays) lives in `../ansible/`.
