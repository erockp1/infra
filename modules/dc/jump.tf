# ===========================================================================
# Chunk 2 — the jump VM: the only public-facing host, NSG-locked to the home IP.
# SSH to the jump, then hop to the DC over the VNet (no public IP on the DC).
# Cheap B1s; deallocate between sessions.
# ===========================================================================

resource "azurerm_public_ip" "jump" {
  name                = "pip-${var.name_prefix}-jump"
  location            = local.rg_location
  resource_group_name = local.rg_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "jump" {
  name                = "nic-${var.name_prefix}-jump"
  location            = local.rg_location
  resource_group_name = local.rg_name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.mgmt_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.jump.id
  }
}

resource "azurerm_linux_virtual_machine" "jump" {
  name                            = "vm-${var.name_prefix}-jump"
  location                        = local.rg_location
  resource_group_name             = local.rg_name
  size                            = var.jump_vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.jump.id]
  tags                            = var.tags

  custom_data = base64encode(templatefile("${path.root}/scripts/cloud-init-jump.yaml.tftpl", {
    hostname = "jump"
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

  boot_diagnostics {}
}
