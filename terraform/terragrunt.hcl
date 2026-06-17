# Root Terragrunt config. Per-environment dirs (terraform/environments/
# <env>/<customer>/<topology>/terragrunt.hcl) include this so backend
# config + provider config + common inputs live in one place.
#
# State key shape: customers/<customer>/<env>/<topology>/terraform.tfstate
# (matches CONVENTIONS.md in pgmanager/terraform-state-bootstrap)

locals {
  # Parse the path so per-customer dirs don't repeat themselves.
  path_relative = path_relative_to_include()
  parsed        = regex("environments/(?P<env>[^/]+)/(?P<customer>[^/]+)/(?P<topology>.+)", local.path_relative)
  env           = local.parsed.env
  customer      = local.parsed.customer
  topology      = local.parsed.topology

  state_bucket = get_env("PGCLERK_TF_STATE_BUCKET", "")
  state_lock   = get_env("PGCLERK_TF_LOCK_TABLE",   "")
  state_region = get_env("PGCLERK_TF_STATE_REGION", "us-east-1")
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = local.state_bucket
    key            = "customers/${local.customer}/${local.env}/${local.topology}/terraform.tfstate"
    region         = local.state_region
    encrypt        = true
    dynamodb_table = local.state_lock
  }
}

inputs = {
  environment = local.env
  customer    = local.customer
  topology    = local.topology
}
