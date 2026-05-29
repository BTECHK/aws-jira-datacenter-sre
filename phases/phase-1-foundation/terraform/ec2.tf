data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# Rocky Linux 9 AMI — PINNED by ID (not a data source). Look it up once (NO instance launch needed):
#   aws ec2 describe-images --filters "Name=name,Values=Rocky-9-EC2-Base-9.*x86_64*" "Name=state,Values=available" \
#     --query 'reverse(sort_by(Images,&CreationDate))[*].[Name,ImageId,OwnerId,CreationDate]' --output table
# Pick an OLDER 9.x minor (a couple behind newest) so Phase-2 `dnf` patching does real work, then set
# rocky_ami_id in terraform.tfvars. Pinning by ID drops the owners/Marketplace question and keeps the OS reproducible.
variable "rocky_ami_id" {
  type        = string
  default     = ""
  description = "Pinned older Rocky 9 minor AMI ID (us-east-1). Required once any box is on Rocky."
}

locals {
  app_types = { redmine = "t3.small", xwiki = "t3.medium", gitea = "t3.micro" }

  # Rocky AMIs do NOT preinstall the SSM agent; without it a box is unreachable (port 22 is closed).
  # This user_data installs + enables it on first boot. VERIFY the RPM URL/region at apply.
  rocky_ssm_userdata = <<-EOT
    #!/bin/bash
    dnf install -y https://s3.${var.region}.amazonaws.com/amazon-ssm-${var.region}/latest/linux_amd64/amazon-ssm-agent.rpm
    systemctl enable --now amazon-ssm-agent
  EOT

  app_ami      = { for svc, _ in local.app_types : svc => contains(var.rocky_services, svc) ? var.rocky_ami_id : data.aws_ami.al2023.id }
  app_userdata = { for svc, _ in local.app_types : svc => contains(var.rocky_services, svc) ? local.rocky_ssm_userdata : null }
}

# Migrate one box at a time: add a service name here (or in terraform.tfvars), then
#   terraform apply -replace='aws_instance.app["<svc>"]' -var="my_ip=$(curl -s -4 https://ifconfig.me/ip)/32"
# Target uniform-Rocky end state: rocky_services = ["gitea","xwiki","redmine"] + rocky_proxy = true.
variable "rocky_services" {
  type        = list(string)
  default     = []
  description = "App service names to run on Rocky 9 (e.g. [\"gitea\"]); any not listed stay on AL2023."
}
variable "rocky_proxy" {
  type        = bool
  default     = false
  description = "Run the proxy box on Rocky 9."
}

resource "aws_instance" "app" {
  for_each               = local.app_types
  ami                    = local.app_ami[each.key]
  instance_type          = each.value
  subnet_id              = aws_subnet.private_a.id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  user_data              = local.app_userdata[each.key]
  root_block_device {
    volume_size = 30
  }
  tags = { Name = "mds-tools-${each.key}", Service = each.key }
  lifecycle {
    # Migration is deliberate, not automatic: flip rocky_services, then `terraform apply -replace`.
    # Ignoring ami+user_data means routine applies never surprise-replace a hand-built box (AL2023 OR Rocky).
    ignore_changes = [ami, user_data]
    precondition {
      condition     = !contains(var.rocky_services, each.key) || length(var.rocky_ami_id) > 0
      error_message = "Set rocky_ami_id (an older Rocky 9 minor AMI) before putting a box on Rocky."
    }
  }
}
resource "aws_instance" "proxy" {
  ami                         = var.rocky_proxy ? var.rocky_ami_id : data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.proxy.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true
  user_data                   = var.rocky_proxy ? local.rocky_ssm_userdata : null
  tags                        = { Name = "mds-tools-proxy", Service = "proxy" }
  lifecycle {
    ignore_changes = [ami, user_data]
    precondition {
      condition     = !var.rocky_proxy || length(var.rocky_ami_id) > 0
      error_message = "Set rocky_ami_id before setting rocky_proxy = true."
    }
  }
}
output "proxy_public_ip" {
  value = aws_instance.proxy.public_ip
}
output "app_private_ips" {
  value = { for k, v in aws_instance.app : k => v.private_ip }
}
output "rds_endpoint" {
  value = aws_db_instance.pg.address
}