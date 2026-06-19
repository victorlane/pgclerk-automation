# All variables get sane defaults so `terraform plan` runs without
# arguments during CI / local validation. pgclerk overrides them at
# dispatch time via -var flags from the cluster's jitPlan.

variable "region" {
  type        = string
  description = "AWS region (e.g. eu-west-1)."
  default     = "eu-west-1"
}

variable "owner" {
  type        = string
  description = "Customer slug — drives Name tags."
  default     = "pgclerk"
}

variable "cluster_name" {
  type        = string
  description = "Cluster name from pgclerk."
  default     = "sandbox"
}

variable "key_name" {
  type        = string
  description = "EC2 KeyPair name to create."
  default     = "pgclerk-dev"
}

variable "ssh_public_key" {
  type        = string
  description = "OpenSSH public key blob. Injected by pgclerk at dispatch."
  default     = ""
}

variable "allow_ssh_cidr" {
  type        = string
  description = "CIDR allowed SSH access to PG host. Use the operator's IP, or Semaphore's egress."
  default     = "0.0.0.0/0"
}

variable "use_spot" {
  type        = bool
  default     = false
  description = "Use a spot instance for the PG node."
}

variable "pg_count" {
  type        = number
  default     = 1
  description = "Reserved for symmetry with HA topologies — ignored here (always 1)."
}

variable "pg_instance_type" {
  type        = string
  default     = "t3.medium"
}

variable "pg_data_volume_size" {
  type        = number
  default     = 20
}

# Reserved-for-symmetry vars so callers can pass the full jitPlan
# argument set to any topology without per-topology branching.
variable "etcd_count"             { type = number, default = 0 }
variable "etcd_instance_type"     { type = string, default = "t3.small" }
variable "backup_count"           { type = number, default = 0 }
variable "backup_instance_type"   { type = string, default = "t3.medium" }
variable "backup_data_volume_size" { type = number, default = 50 }
