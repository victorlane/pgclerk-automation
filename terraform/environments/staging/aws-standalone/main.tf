# AWS · 1 PG VM topology. VPC + 1 EC2 + EBS + SG + KP.
# Driven by -var flags pgclerk's Bootstrap action composes from the
# cluster's jitPlan. Outputs a pg_hosts list shaped for jit-seed.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    # State key is overridden per-cluster via -backend-config=key=...
    # in the dispatch wrapper. Bucket + region are static.
    bucket = "pgclerk-tf-state-eu-west-3"
    key    = "default.tfstate"
    region = "eu-west-3"
    encrypt        = true
    dynamodb_table = "pgclerk-tf-locks"
  }
}

provider "aws" {
  region = var.region
}

# pgclerk tags every resource so /pgclerk:role queries during jit-seed
# can pluck out PG / etcd / backup hosts even when the operator
# named them weirdly. Owner is the customer slug.
locals {
  base_tags = {
    "pgclerk:owner"    = var.owner
    "pgclerk:cluster"  = var.cluster_name
    "pgclerk:topology" = "aws-standalone"
  }
}

# Single AZ — standalone doesn't need multi-AZ.
module "network" {
  source         = "../../../modules/network/aws"
  name           = "${var.owner}-${var.cluster_name}"
  vpc_cidr       = "10.42.0.0/16"
  azs            = ["a"]
  allow_ssh_cidr = var.allow_ssh_cidr
  tags           = local.base_tags
}

# Upload the operator's public SSH key into AWS so EC2 has something
# to put in /root/.ssh/authorized_keys at first boot. The matching
# private key is on the Semaphore runner via the pgm-deploy ssh key.
resource "aws_key_pair" "operator" {
  key_name   = var.key_name
  public_key = var.ssh_public_key
  tags       = local.base_tags
}

module "pg" {
  source            = "../../../modules/compute/aws-pg-node"
  name              = "${var.owner}-${var.cluster_name}-pg-1"
  subnet_id         = module.network.subnet_ids[0]
  security_group_id = module.network.pg_sg_id
  instance_type     = var.pg_instance_type
  key_name          = aws_key_pair.operator.key_name
  role              = "pg"
  data_volume_gib   = var.pg_data_volume_size
  use_spot          = var.use_spot
  tags              = local.base_tags
}

# Shape consumed by the jit-seed POST body. Always a list, even with
# one host, so the consumer is uniform across topologies.
output "pg_hosts" {
  description = "List of { hostname, ip, role } for /api/clusters/:id/jit-seed."
  value = [
    {
      hostname = module.pg.hostname
      ip       = module.pg.public_ip
      role     = module.pg.role
    }
  ]
}
