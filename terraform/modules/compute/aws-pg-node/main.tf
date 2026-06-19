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

variable "name"             { type = string }
variable "subnet_id"         { type = string }
variable "security_group_id" { type = string }
variable "instance_type"     { type = string }
variable "key_name"          { type = string }
variable "role"              { type = string }
variable "data_volume_gib"   { type = number, default = 20 }
variable "use_spot"          { type = bool, default = false }
variable "tags"              { type = map(string), default = {} }

variable "ami_id" {
  type        = string
  default     = ""
  description = "Override AMI id. Empty = look up Rocky 9 via the AMI data source."
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
}

resource "aws_instance" "this" {
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_size           = var.data_volume_gib
    volume_type           = "gp3"
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
    Name             = var.name
    "pgclerk:role"   = var.role
    "pgclerk:hostname" = var.name
  })
}

output "id"           { value = aws_instance.this.id }
output "private_ip"   { value = aws_instance.this.private_ip }
output "public_ip"    { value = aws_instance.this.public_ip }
output "hostname"     { value = var.name }
output "role"         { value = var.role }
