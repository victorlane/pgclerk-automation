# A single GCE VM configured as a pgclerk-managed PG host. Same
# contract as the AWS compute module — same inputs, same outputs.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

variable "name" {
  type = string
}

variable "zone" {
  type = string
}

variable "machine_type" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "role" {
  type = string
}

variable "data_volume_gib" {
  type    = number
  default = 20
}

variable "use_spot" {
  type    = bool
  default = false
}

variable "base_ssh_public_key" {
  type = string
}

variable "extra_ssh_keys" {
  type    = list(string)
  default = []
}

variable "extra_ssh_users" {
  type    = list(string)
  default = ["rocky", "ec2-user", "ubuntu", "admin", "centos", "root"]
}

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  cloud_init = <<-EOT
    #cloud-config
    users:
      - name: pgmadmin
        gecos: pgclerk admin
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        groups: wheel,sudo
        ssh_authorized_keys:
        %{for k in var.extra_ssh_keys~}
          - ${jsonencode(k)}
        %{endfor~}
    runcmd:
    %{for u in var.extra_ssh_users~}
      - |
        if id -u ${u} >/dev/null 2>&1; then
          home=$(getent passwd ${u} | cut -d: -f6)
          mkdir -p $home/.ssh
          chmod 700 $home/.ssh
          touch $home/.ssh/authorized_keys
          chmod 600 $home/.ssh/authorized_keys
          grep -qxF ${jsonencode(var.base_ssh_public_key)} $home/.ssh/authorized_keys || echo ${jsonencode(var.base_ssh_public_key)} >> $home/.ssh/authorized_keys
          chown -R ${u}:${u} $home/.ssh 2>/dev/null || true
        fi
    %{endfor~}
  EOT
}

# Rocky Linux 9 image family — operators can override AMI-equivalent
# by patching this resource if they need a different distro.
data "google_compute_image" "rocky9" {
  family  = "rocky-linux-9-optimized-gcp"
  project = "rocky-linux-cloud"
}

resource "google_compute_instance" "this" {
  name         = var.name
  zone         = var.zone
  machine_type = var.machine_type
  tags         = ["pgclerk-vm"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.rocky9.self_link
      size  = 20
      type  = "pd-ssd"
    }
  }

  attached_disk {
    source      = google_compute_disk.data.id
    device_name = "pgdata"
  }

  network_interface {
    subnetwork = var.subnet_id
    access_config {
      # ephemeral external IP
    }
  }

  scheduling {
    provisioning_model = var.use_spot ? "SPOT" : "STANDARD"
    preemptible        = var.use_spot
    automatic_restart  = !var.use_spot
  }

  metadata = {
    user-data = local.cloud_init
    # GCP's metadata SSH key format also accepts these
    ssh-keys = "pgmadmin:${var.base_ssh_public_key}"
  }

  labels = {
    "pgclerk-role"     = var.role
    "pgclerk-hostname" = var.name
  }
}

resource "google_compute_disk" "data" {
  name = "${var.name}-data"
  zone = var.zone
  type = "pd-ssd"
  size = var.data_volume_gib
}

output "id" { value = google_compute_instance.this.id }
output "hostname" { value = google_compute_instance.this.name }
output "private_ip" { value = google_compute_instance.this.network_interface[0].network_ip }
output "public_ip" { value = google_compute_instance.this.network_interface[0].access_config[0].nat_ip }
output "role" { value = var.role }
