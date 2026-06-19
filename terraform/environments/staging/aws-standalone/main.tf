# Stub Terraform module — replace with real resources.
# Generated from meta/catalogue.yml. Provider: aws
# Topology: pg=1 etcd=0 backup=0

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.region
}


locals {
  topology = {
    provider     = "aws"
    pg_count     = var.pg_count
    etcd_count   = try(var.etcd_count, 0)
    backup_count = 0
  }
}
