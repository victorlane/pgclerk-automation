# Stub Terraform module — replace with real resources.
# Generated from meta/catalogue.yml. Provider: azure
# Topology: pg=1 etcd=0 backup=0

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}


locals {
  topology = {
    provider     = "azure"
    pg_count     = var.pg_count
    etcd_count   = try(var.etcd_count, 0)
    backup_count = 0
  }
}
