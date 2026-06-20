# AWS · Patroni HA with dedicated etcd quorum.
# pg_count PG nodes + etcd_count etcd nodes across up to 3 AZs.
# Shared VPC / SG / key-pair. Outputs pg_hosts AND etcd_hosts shaped
# for /api/clusters/:id/jit-seed (uses the `role` field to distinguish).

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    # Partial backend configuration. Bucket, region, dynamodb_table,
    # and key are injected by pgclerk's dispatcher at `terraform init`
    # time via TF_CLI_ARGS_init=-backend-config=... so each customer's
    # state lives in their own AWS account.
  }
}

provider "aws" {
  region = var.region
}

locals {
  base_tags = {
    "pgclerk:owner"    = var.owner
    "pgclerk:cluster"  = var.cluster_name
    "pgclerk:topology" = "aws-replication-external-etcd"
  }
  az_keys = slice(["a", "b", "c"], 0, min(3, max(1, max(var.pg_count, var.etcd_count))))
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
  count                = var.pg_count
  source               = "../../../modules/compute/aws-pg-node"
  name                 = "${var.owner}-${var.cluster_name}-pg-${count.index + 1}"
  subnet_id            = module.network.subnet_ids[count.index % length(module.network.subnet_ids)]
  security_group_id    = module.network.pg_sg_id
  instance_type        = var.pg_instance_type
  key_name             = aws_key_pair.operator.key_name
  role                 = "pg"
  data_volume_gib      = var.pg_disk_size_gib > 0 ? var.pg_disk_size_gib : var.pg_data_volume_size
  disk_type            = var.pg_disk_type
  disk_iops            = var.pg_disk_iops
  disk_throughput_mbps = var.pg_disk_throughput_mbps
  use_spot             = var.use_spot
  base_ssh_public_key  = var.ssh_public_key
  extra_ssh_keys       = var.extra_ssh_keys
  tags                 = local.base_tags
}

module "etcd" {
  count                = var.etcd_count
  source               = "../../../modules/compute/aws-pg-node"
  name                 = "${var.owner}-${var.cluster_name}-etcd-${count.index + 1}"
  subnet_id            = module.network.subnet_ids[count.index % length(module.network.subnet_ids)]
  security_group_id    = module.network.pg_sg_id
  instance_type        = var.etcd_instance_type
  key_name             = aws_key_pair.operator.key_name
  role                 = "etcd"
  data_volume_gib      = var.etcd_disk_size_gib > 0 ? var.etcd_disk_size_gib : 10
  disk_type            = var.etcd_disk_type
  disk_iops            = var.etcd_disk_iops
  disk_throughput_mbps = var.etcd_disk_throughput_mbps
  use_spot             = var.use_spot
  base_ssh_public_key  = var.ssh_public_key
  extra_ssh_keys       = var.extra_ssh_keys
  tags                 = local.base_tags
}

output "pg_hosts" {
  description = "PG + etcd nodes flattened into one list for jit-seed; the `role` field tells them apart."
  value = concat(
    [for n in module.pg : { hostname = n.hostname, ip = n.public_ip, role = n.role }],
    [for n in module.etcd : { hostname = n.hostname, ip = n.public_ip, role = n.role }]
  )
}
