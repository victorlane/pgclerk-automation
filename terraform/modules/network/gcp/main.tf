# Reusable GCP networking module. One VPC, one subnet per zone the
# caller hands in. SSH allowed from the operator's CIDR; PG, etcd
# and Patroni REST allowed intra-VPC.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "zones" {
  type        = list(string)
  description = "Zone suffixes (a, b, c) — fully qualified inside."
}

variable "subnet_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "allow_ssh_cidr" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "google_compute_network" "this" {
  name                    = "${var.name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "primary" {
  name          = "${var.name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.this.id
}

resource "google_compute_firewall" "ssh" {
  name      = "${var.name}-ssh"
  network   = google_compute_network.this.id
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.allow_ssh_cidr]
  target_tags   = ["pgclerk-vm"]
}

resource "google_compute_firewall" "intra" {
  name      = "${var.name}-intra"
  network   = google_compute_network.this.id
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["5432", "2379-2380", "8008"]
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["pgclerk-vm"]
}

output "subnet_id" {
  value = google_compute_subnetwork.primary.id
}

output "network_name" {
  value = google_compute_network.this.name
}

output "zones" {
  value = [for z in var.zones : "${var.region}-${z}"]
}
