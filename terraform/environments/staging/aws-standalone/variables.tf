variable "region" {
  type = string
  description = "Cloud region (e.g. eu-west-1 for AWS, europe-west4 for GCP, westeurope for Azure)."
}

variable "owner" {
  type = string
  description = "Resource owner tag — usually the customer slug."
  default     = "pgclerk"
}

variable "key_name" {
  type = string
  description = "SSH key pair name uploaded to the cloud provider; pgclerk's Semaphore deploy key."
  default     = "pgclerk-dev"
}

variable "allow_ssh_cidr" {
  type = string
  description = "CIDR allowed to SSH into PG hosts. Set this to the operator's public IP (or Semaphore's egress IP)."
  default     = "0.0.0.0/0"
}

variable "use_spot" {
  type = bool
  description = "Use spot/preemptible instances where the provider allows."
  default     = true
}

variable "pg_count" {
  type = number
  description = "PostgreSQL node count."
}

variable "pg_instance_type" {
  type = string
  description = "Provider-specific instance type for PG nodes."
}

variable "pg_data_volume_size" {
  type = number
  description = "Data volume size in GiB."
  default     = 20
}

variable "etcd_count" {
  type = number
  default = 0
}
variable "etcd_instance_type" {
  type = string
  default = "t3.small"
}
variable "backup_count" {
  type = number
  default = 0
}
variable "backup_instance_type" {
  type = string
  default = "t3.medium"
}
variable "backup_data_volume_size" {
  type = number
  default = 50
}
