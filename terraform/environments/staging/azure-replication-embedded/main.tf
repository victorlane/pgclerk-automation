# Azure · Patroni HA with embedded etcd. 3 VMs in one VNet.

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
  backend "s3" {
    bucket         = "pgclerk-tf-state-eu-west-3"
    key            = "default.tfstate"
    region         = "eu-west-3"
    encrypt        = true
    dynamodb_table = "pgclerk-tf-locks"
  }
}

provider "azurerm" {
  features {}
}

locals {
  base_tags = {
    pgclerk_owner    = var.owner
    pgclerk_cluster  = var.cluster_name
    pgclerk_topology = "azure-replication-embedded"
  }
}

module "network" {
  source         = "../../../modules/network/azure"
  name           = "${var.owner}-${var.cluster_name}"
  location       = var.region
  allow_ssh_cidr = var.allow_ssh_cidr
  tags           = local.base_tags
}

module "pg" {
  count               = var.pg_count
  source              = "../../../modules/compute/azure-pg-node"
  name                = "${var.owner}-${var.cluster_name}-pg-${count.index + 1}"
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
  subnet_id           = module.network.subnet_id
  vm_size             = var.pg_instance_type
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
