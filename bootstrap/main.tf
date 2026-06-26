# ---------------------------------------------------------------------------
# Chunk 0a — remote-state backend (runs with LOCAL state).
# Breaks the chicken-and-egg: the azurerm backend in ../backend.tf needs a
# storage account that must already exist. Apply this once, then point the root
# config's backend at the outputs below.
# ---------------------------------------------------------------------------

resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  # storage account names: 3-24 chars, lowercase alphanumeric, globally unique.
  state_sa_name = substr("${var.name_prefix}tf${random_string.suffix.result}", 0, 24)

  tags = merge({
    purpose = "poc0"
    env     = "rig"
    role    = "tfstate"
  }, var.tags)
}

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-${var.name_prefix}-tfstate"
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "tfstate" {
  name                            = local.state_sa_name
  resource_group_name             = azurerm_resource_group.tfstate.name
  location                        = azurerm_resource_group.tfstate.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true # backend can use AAD; key kept enabled as fallback

  blob_properties {
    versioning_enabled = true # protects state against accidental overwrite
  }

  tags = local.tags
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}
