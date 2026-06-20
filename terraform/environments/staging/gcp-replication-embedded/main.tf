# GCP · Patroni HA with embedded etcd. 3 GCE VMs across 3 zones.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "pgclerk-tf-state-eu-west-3"
    key            = "default.tfstate"
    region         = "eu-west-3"
    encrypt        = true
    dynamodb_table = "pgclerk-tf-locks"
  }
}

provider "google" {
  region = var.region
}

locals {
  base_tags = {
    "pgclerk_owner"    = var.owner
    "pgclerk_cluster"  = var.cluster_name
    "pgclerk_topology" = "gcp-replication-embedded"
  }
  zone_keys = slice(["a", "b", "c"], 0, min(3, max(1, var.pg_count)))
}

module "network" {
  source         = "../../../modules/network/gcp"
  name           = "${var.owner}-${var.cluster_name}"
  region         = var.region
  zones          = local.zone_keys
  allow_ssh_cidr = var.allow_ssh_cidr
  tags           = local.base_tags
}

module "pg" {
  count               = var.pg_count
  source              = "../../../modules/compute/gcp-pg-node"
  name                = "${var.owner}-${var.cluster_name}-pg-${count.index + 1}"
  zone                = module.network.zones[count.index % length(module.network.zones)]
  machine_type        = var.pg_instance_type
  subnet_id           = module.network.subnet_id
  role                = "pg"
  data_volume_gib     = var.pg_data_volume_size
  use_spot            = var.use_spot
  base_ssh_public_key = var.ssh_public_key
  extra_ssh_keys      = var.extra_ssh_keys
  tags                = local.base_tags
}

output "pg_hosts" {
  value = [
    for n in module.pg : {
      hostname = n.hostname
      ip       = n.public_ip
      role     = n.role
    }
  ]
}
