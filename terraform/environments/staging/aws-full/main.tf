# AWS · Full topology. pg_count PG nodes + etcd_count etcd nodes +
# backup_count backup nodes, all sharing one VPC / SG / key-pair across
# up to 3 AZs. Outputs pg_hosts flattened into one list for
# /api/clusters/:id/jit-seed; the `role` field distinguishes pg / etcd / backup.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "pgclerk-tf-state-eu-west-3"
    key            = "default.tfstate"
    region         = "eu-west-3"
    encrypt        = true
    dynamodb_table = "pgclerk-tf-locks"
  }
}

provider "aws" {
  region = var.region
}

locals {
  base_tags = {
    "pgclerk:owner"    = var.owner
    "pgclerk:cluster"  = var.cluster_name
    "pgclerk:topology" = "aws-full"
  }
  az_keys = slice(["a", "b", "c"], 0, min(3, max(1, max(var.pg_count, var.etcd_count, var.backup_count))))
}

module "network" {
  source         = "../../../modules/network/aws"
  name           = "${var.owner}-${var.cluster_name}"
  vpc_cidr       = "10.42.0.0/16"
  azs            = local.az_keys
  allow_ssh_cidr = var.allow_ssh_cidr
  tags           = local.base_tags
}

resource "aws_key_pair" "operator" {
  key_name   = var.key_name
  public_key = var.ssh_public_key
  tags       = local.base_tags
}

module "pg" {
  count               = var.pg_count
  source              = "../../../modules/compute/aws-pg-node"
  name                = "${var.owner}-${var.cluster_name}-pg-${count.index + 1}"
  subnet_id           = module.network.subnet_ids[count.index % length(module.network.subnet_ids)]
  security_group_id   = module.network.pg_sg_id
  instance_type       = var.pg_instance_type
  key_name            = aws_key_pair.operator.key_name
  role                = "pg"
  data_volume_gib      = var.pg_disk_size_gib > 0 ? var.pg_disk_size_gib : var.pg_data_volume_size
  disk_type            = var.pg_disk_type
  disk_iops            = var.pg_disk_iops
  disk_throughput_mbps = var.pg_disk_throughput_mbps
  use_spot            = var.use_spot
  base_ssh_public_key = var.ssh_public_key
  extra_ssh_keys      = var.extra_ssh_keys
  tags                = local.base_tags
}

module "etcd" {
  count               = var.etcd_count
  source              = "../../../modules/compute/aws-pg-node"
  name                = "${var.owner}-${var.cluster_name}-etcd-${count.index + 1}"
  subnet_id           = module.network.subnet_ids[count.index % length(module.network.subnet_ids)]
  security_group_id   = module.network.pg_sg_id
  instance_type       = var.etcd_instance_type
  key_name            = aws_key_pair.operator.key_name
  role                = "etcd"
  data_volume_gib      = var.etcd_disk_size_gib > 0 ? var.etcd_disk_size_gib : 10
  disk_type            = var.etcd_disk_type
  disk_iops            = var.etcd_disk_iops
  disk_throughput_mbps = var.etcd_disk_throughput_mbps
  use_spot            = var.use_spot
  base_ssh_public_key = var.ssh_public_key
  extra_ssh_keys      = var.extra_ssh_keys
  tags                = local.base_tags
}

module "backup" {
  count               = var.backup_count
  source              = "../../../modules/compute/aws-pg-node"
  name                = "${var.owner}-${var.cluster_name}-backup-${count.index + 1}"
  subnet_id           = module.network.subnet_ids[count.index % length(module.network.subnet_ids)]
  security_group_id   = module.network.pg_sg_id
  instance_type       = var.backup_instance_type
  key_name            = aws_key_pair.operator.key_name
  role                = "backup"
  data_volume_gib      = var.backup_disk_size_gib > 0 ? var.backup_disk_size_gib : var.backup_data_volume_size
  disk_type            = var.backup_disk_type
  disk_iops            = var.backup_disk_iops
  disk_throughput_mbps = var.backup_disk_throughput_mbps
  use_spot            = var.use_spot
  base_ssh_public_key = var.ssh_public_key
  extra_ssh_keys      = var.extra_ssh_keys
  tags                = local.base_tags
}

output "pg_hosts" {
  description = "PG + etcd + backup nodes flattened into one list for jit-seed; the `role` field tells them apart."
  value = concat(
    [for n in module.pg : { hostname = n.hostname, ip = n.public_ip, role = n.role }],
    [for n in module.etcd : { hostname = n.hostname, ip = n.public_ip, role = n.role }],
    [for n in module.backup : { hostname = n.hostname, ip = n.public_ip, role = n.role }]
  )
}
