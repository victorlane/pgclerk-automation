# A single Azure Linux VM configured as a pgclerk-managed PG host.
# Same contract as the AWS/GCP compute modules.

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}

variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "vm_size" {
  type = string
}

variable "role" {
  type = string
}

variable "data_volume_gib" {
  type    = number
  default = 20
}

# Per-role disk knobs pgclerk's dispatcher injects via TF_VAR_*.
# Operators can override defaults from the wizard's disk card.
# Azure accepts disk_iops_read_write and disk_mbps_read_write only
# on PremiumV2_LRS and UltraSSD_LRS — leave them at 0 to use the
# SKU's default IOPS/throughput.
variable "disk_type" {
  type        = string
  default     = "Premium_LRS"
  description = "Managed disk SKU. Premium_LRS / PremiumV2_LRS / StandardSSD_LRS / Standard_LRS / UltraSSD_LRS."
}

variable "disk_iops" {
  type        = number
  default     = 0
  description = "Provisioned IOPS. Honoured for PremiumV2_LRS + UltraSSD_LRS. 0 = SKU default."
}

variable "disk_throughput_mbps" {
  type        = number
  default     = 0
  description = "Throughput MB/s. Honoured for PremiumV2_LRS + UltraSSD_LRS. 0 = SKU default."
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
  default = ["rocky", "azureuser", "ubuntu", "admin", "centos", "root"]
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

resource "azurerm_public_ip" "this" {
  name                = "${var.name}-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "this" {
  name                = "${var.name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this.id
  }
}

resource "azurerm_linux_virtual_machine" "this" {
  name                            = var.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  size                            = var.vm_size
  admin_username                  = "azureuser"
  network_interface_ids           = [azurerm_network_interface.this.id]
  disable_password_authentication = true
  priority                        = var.use_spot ? "Spot" : "Regular"
  eviction_policy                 = var.use_spot ? "Deallocate" : null
  custom_data                     = base64encode(local.cloud_init)

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.base_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Rocky Linux 9 from the Marketplace.
  source_image_reference {
    publisher = "resf"
    offer     = "rockylinux-x86_64"
    sku       = "9-base"
    version   = "latest"
  }

  tags = merge(var.tags, {
    "pgclerk-role"     = var.role
    "pgclerk-hostname" = var.name
  })
}

resource "azurerm_managed_disk" "data" {
  name                 = "${var.name}-data"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = var.disk_type
  create_option        = "Empty"
  disk_size_gb         = var.data_volume_gib

  # Azure rejects disk_iops_read_write / disk_mbps_read_write on
  # SKUs that don't expose them. Only PremiumV2_LRS + UltraSSD_LRS
  # allow tuning — null them out otherwise so the SKU's default
  # IOPS / throughput stand.
  disk_iops_read_write = (
    var.disk_iops > 0 && contains(["PremiumV2_LRS", "UltraSSD_LRS"], var.disk_type)
    ? var.disk_iops
    : null
  )
  disk_mbps_read_write = (
    var.disk_throughput_mbps > 0 && contains(["PremiumV2_LRS", "UltraSSD_LRS"], var.disk_type)
    ? var.disk_throughput_mbps
    : null
  )
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  managed_disk_id    = azurerm_managed_disk.data.id
  virtual_machine_id = azurerm_linux_virtual_machine.this.id
  lun                = 0
  caching            = "ReadWrite"
}

output "id" { value = azurerm_linux_virtual_machine.this.id }
output "hostname" { value = azurerm_linux_virtual_machine.this.name }
output "public_ip" { value = azurerm_public_ip.this.ip_address }
output "private_ip" { value = azurerm_linux_virtual_machine.this.private_ip_address }
output "role" { value = var.role }
