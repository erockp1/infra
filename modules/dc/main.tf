# ===========================================================================
# Chunk 2 — the DC VM (bare): a Linux VM positioned to become a Samba-AD DC,
# reachable only via the jump path, with a data disk for /var/lib/samba. No DC
# provisioning yet (that's Chunk 3).
# ===========================================================================

# --- On-prem-sim RG: create (rig) or reference (corporate) ------------------
resource "azurerm_resource_group" "onprem" {
  count    = var.create_resource_groups ? 1 : 0
  name     = var.rg_onprem_name
  location = var.location
  tags     = var.tags
}

data "azurerm_resource_group" "onprem" {
  count = var.create_resource_groups ? 0 : 1
  name  = var.rg_onprem_name
}

locals {
  rg_name     = var.create_resource_groups ? azurerm_resource_group.onprem[0].name : data.azurerm_resource_group.onprem[0].name
  rg_location = var.create_resource_groups ? azurerm_resource_group.onprem[0].location : data.azurerm_resource_group.onprem[0].location
  dc_fqdn     = "${var.dc_hostname}.${var.domain_realm}"
}

# --- DC NIC: static private IP, NO public IP -------------------------------
resource "azurerm_network_interface" "dc" {
  name                = "nic-${var.name_prefix}-dc"
  location            = local.rg_location
  resource_group_name = local.rg_name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.dc_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.dc_static_ip
  }
}

# --- DC VM (B-series, Ubuntu LTS, SSH key only) ----------------------------
resource "azurerm_linux_virtual_machine" "dc" {
  name                            = "vm-${var.name_prefix}-dc"
  location                        = local.rg_location
  resource_group_name             = local.rg_name
  size                            = var.dc_vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.dc.id]
  tags                            = var.tags

  custom_data = base64encode(templatefile("${path.root}/scripts/cloud-init-dc.yaml.tftpl", {
    hostname = var.dc_hostname
    fqdn     = local.dc_fqdn
  }))

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = var.dc_image.publisher
    offer     = var.dc_image.offer
    sku       = var.dc_image.sku
    version   = var.dc_image.version
  }

  # Serial console / screenshot for debugging a VM with no public IP.
  boot_diagnostics {}
}

# --- Data disk for /var/lib/samba (host caching None) -----------------------
resource "azurerm_managed_disk" "dc_data" {
  name                 = "disk-${var.name_prefix}-dc-data"
  location             = local.rg_location
  resource_group_name  = local.rg_name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.dc_data_disk_gb
  tags                 = var.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "dc_data" {
  managed_disk_id    = azurerm_managed_disk.dc_data.id
  virtual_machine_id = azurerm_linux_virtual_machine.dc.id
  lun                = 0
  caching            = "None"
}
