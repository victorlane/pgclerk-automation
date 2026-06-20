variable "region" {
  type    = string
  default = "eu-west-1"
}
variable "owner" {
  type    = string
  default = "pgclerk"
}
variable "cluster_name" {
  type    = string
  default = "sandbox"
}
variable "key_name" {
  type    = string
  default = "pgclerk-dev"
}
variable "ssh_public_key" {
  type    = string
  default = ""
}
variable "extra_ssh_keys" {
  type    = list(string)
  default = []
}
variable "allow_ssh_cidr" {
  type    = string
  default = "0.0.0.0/0"
}
variable "use_spot" {
  type    = bool
  default = false
}
variable "pg_count" {
  type    = number
  default = 3
}
variable "pg_instance_type" {
  type    = string
  default = "t3.medium"
}
variable "pg_data_volume_size" {
  type    = number
  default = 20
}
variable "etcd_count" {
  type    = number
  default = 3
}
variable "etcd_instance_type" {
  type    = string
  default = "t3.small"
}
variable "backup_count" {
  type    = number
  default = 1
}
variable "backup_instance_type" {
  type    = string
  default = "t3.medium"
}
variable "backup_data_volume_size" {
  type    = number
  default = 100
}

# ----- Disk knobs per role (pgclerk dispatcher injects via TF_VAR_*) -----
variable "pg_disk_type" {
  type    = string
  default = "gp3"
}
variable "pg_disk_size_gib" {
  type    = number
  default = 0
}
variable "pg_disk_iops" {
  type    = number
  default = 0
}
variable "pg_disk_throughput_mbps" {
  type    = number
  default = 0
}

variable "etcd_disk_type" {
  type    = string
  default = "gp3"
}
variable "etcd_disk_size_gib" {
  type    = number
  default = 0
}
variable "etcd_disk_iops" {
  type    = number
  default = 0
}
variable "etcd_disk_throughput_mbps" {
  type    = number
  default = 0
}

variable "backup_disk_type" {
  type    = string
  default = "gp3"
}
variable "backup_disk_size_gib" {
  type    = number
  default = 0
}
variable "backup_disk_iops" {
  type    = number
  default = 0
}
variable "backup_disk_throughput_mbps" {
  type    = number
  default = 0
}
