# Stub Terraform module — replace with real resources.
# Generated from meta/catalogue.yml. Provider: gcp
# Topology: pg=1 etcd=0 backup=0

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}


locals {
  topology = {
    provider     = "gcp"
    pg_count     = var.pg_count
    etcd_count   = try(var.etcd_count, 0)
    backup_count = 0
  }
}
