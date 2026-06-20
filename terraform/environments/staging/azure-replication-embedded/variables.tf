variable "region" {
  type    = string
  default = "westeurope"
}
variable "owner" {
  type    = string
  default = "pgclerk"
}
variable "cluster_name" {
  type    = string
  default = "sandbox"
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
  default = "Standard_B2s"
}
variable "pg_data_volume_size" {
  type    = number
  default = 20
}
variable "etcd_count" {
  type    = number
  default = 0
}
variable "etcd_instance_type" {
  type    = string
  default = "Standard_B1ms"
}
variable "backup_count" {
  type    = number
  default = 0
}
variable "backup_instance_type" {
  type    = string
  default = "Standard_B2s"
}
variable "backup_data_volume_size" {
  type    = number
  default = 50
}
variable "key_name" {
  type    = string
  default = "pgclerk-dev"
}
