# A single EC2 instance configured as a pgclerk-managed PG host.
# Caller passes the network (subnet + SG) and the role (pg|etcd|backup).
# The instance gets a public IP and a tagged Name so jit-seed picks it
# up from the AWS describe-instances reply emitted by the parent
# topology module.
#
# AMI is resolved at apply time from the operator's preferred family
# (Rocky 9 today). Operators can override via `ami_id` or pin a family
# via `ami_owner` + `ami_name_pattern`.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

variable "name" { type = string }
variable "subnet_id" { type = string }
variable "security_group_id" { type = string }
variable "instance_type" { type = string }
variable "key_name" { type = string }
variable "role" { type = string }

variable "data_volume_gib" {
  type    = number
  default = 20
}

# Per-role disk knobs pgclerk's dispatcher injects via TF_VAR_*.
# Operators can override defaults from the wizard's disk card. EBS
# accepts iops on gp3/io1/io2 and throughput on gp3 — leave them at
# 0 to let AWS use the default for the chosen volume_type.
variable "disk_type" {
  type        = string
  default     = "gp3"
  description = "EBS volume type for the data volume. gp3 / gp2 / io1 / io2 / st1 / sc1."
}

variable "disk_iops" {
  type        = number
  default     = 0
  description = "Provisioned IOPS. Honoured for gp3 (3000-16000) / io1 / io2. 0 = AWS default."
}

variable "disk_throughput_mbps" {
  type        = number
  default     = 0
  description = "Throughput MB/s. Honoured for gp3 (125-1000). 0 = AWS default."
}

variable "use_spot" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "ami_id" {
  type        = string
  default     = ""
  description = "Override AMI id. Empty = look up Rocky 9 via the AMI data source."
}

# Operator-supplied SSH public keys that pgclerk's cloud-init layer
# writes into authorized_keys for every standard user that exists on
# the AMI. The base key (var.base_ssh_public_key) is the pgclerk
# Bootstrap key — Ansible uses it for every connection. The extra
# keys are admin keys the operator wants to keep direct SSH access
# with (one OpenSSH line per element).
variable "base_ssh_public_key" {
  type        = string
  description = "OpenSSH public key Ansible uses for first contact. Required."
}

variable "extra_ssh_keys" {
  type        = list(string)
  default     = []
  description = "Additional OpenSSH public key lines authorised on every standard user."
}

variable "extra_ssh_users" {
  type        = list(string)
  default     = ["rocky", "ec2-user", "ubuntu", "admin", "centos", "root"]
  description = "User accounts whose authorized_keys gets the base + extra keys appended at first boot. Missing users are skipped — cloud-init's ssh_authorized_keys + write_files runs idempotently."
}

# Rocky Linux 9 official AMIs (publisher 792107900819).
data "aws_ami" "rocky9" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["792107900819"]
  filter {
    name   = "name"
    values = ["Rocky-9-EC2-Base-9.*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.rocky9[0].id

  # cloud-init bakes the host so Bootstrap can SSH in cleanly:
  #   1. Authorise the pgclerk Bootstrap public key on each of the
  #      AMI's standard accounts (rocky / root / ec2-user / ubuntu /
  #      admin / centos). Ansible picks whichever one the distro
  #      uses; idempotent grep means re-running is safe.
  #   2. Create a dedicated `pgmadmin` user with NOPASSWD sudo and
  #      the operator's extra_ssh_keys authorised — that's how human
  #      admins log in. The Bootstrap key is NOT trusted here, and
  #      the admin keys are NOT trusted on root, so neither side can
  #      escalate into the other without explicit sudo.
  cloud_init = <<-EOT
    #cloud-config
    users:
      - name: pgmadmin
        gecos: pgclerk admin
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        groups: wheel,sudo
        ssh_authorized_keys:
        %{for k in var.extra_ssh_keys~}
          - ${jsonencode(k)}
        %{endfor~}
    runcmd:
    %{for u in var.extra_ssh_users~}
      - |
        if id -u ${u} >/dev/null 2>&1; then
          home=$(getent passwd ${u} | cut -d: -f6)
          mkdir -p $home/.ssh
          chmod 700 $home/.ssh
          touch $home/.ssh/authorized_keys
          chmod 600 $home/.ssh/authorized_keys
          grep -qxF ${jsonencode(var.base_ssh_public_key)} $home/.ssh/authorized_keys || echo ${jsonencode(var.base_ssh_public_key)} >> $home/.ssh/authorized_keys
          chown -R ${u}:${u} $home/.ssh 2>/dev/null || true
        fi
    %{endfor~}
  EOT
}

resource "aws_instance" "this" {
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  key_name                    = var.key_name
  associate_public_ip_address = true
  user_data                   = local.cloud_init
  user_data_replace_on_change = false

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_size           = var.data_volume_gib
    volume_type           = var.disk_type
    # iops + throughput are only meaningful on gp3/io1/io2. Passing 0
    # on a volume type that rejects them would fail validation; we
    # null out the field so AWS uses the type's default.
    iops       = var.disk_iops > 0 ? var.disk_iops : null
    throughput = var.disk_throughput_mbps > 0 && var.disk_type == "gp3" ? var.disk_throughput_mbps : null
    delete_on_termination = true
  }

  dynamic "instance_market_options" {
    for_each = var.use_spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        spot_instance_type = "one-time"
      }
    }
  }

  tags = merge(var.tags, {
    Name               = var.name
    "pgclerk:role"     = var.role
    "pgclerk:hostname" = var.name
  })
}

output "id" { value = aws_instance.this.id }
output "private_ip" { value = aws_instance.this.private_ip }
output "public_ip" { value = aws_instance.this.public_ip }
output "hostname" { value = var.name }
output "role" { value = var.role }
