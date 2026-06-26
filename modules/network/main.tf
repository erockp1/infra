# ===========================================================================
# Chunk 1 — the simulated hybrid boundary: two VNets joined by peering, plus a
# private DNS zone for the realm and NSG shells. All networking lives in the
# long-lived networking/shared RG.
# ===========================================================================

# --- Networking RG: create (rig) or reference (corporate) ------------------
resource "azurerm_resource_group" "net" {
  count    = var.create_resource_groups ? 1 : 0
  name     = var.rg_net_name
  location = var.location
  tags     = var.tags
}

data "azurerm_resource_group" "net" {
  count = var.create_resource_groups ? 0 : 1
  name  = var.rg_net_name
}

locals {
  rg_name     = var.create_resource_groups ? azurerm_resource_group.net[0].name : data.azurerm_resource_group.net[0].name
  rg_location = var.create_resource_groups ? azurerm_resource_group.net[0].location : data.azurerm_resource_group.net[0].location
}

# --- Cloud VNet + delegated app subnet -------------------------------------
resource "azurerm_virtual_network" "cloud" {
  name                = "vnet-${var.name_prefix}-cloud"
  location            = local.rg_location
  resource_group_name = local.rg_name
  address_space       = [var.cloud_vnet_cidr]
  dns_servers         = var.vnet_dns_servers
  tags                = var.tags
}

# Dedicated, delegated subnet for the Container Apps environment. Left EMPTY of
# other resources — delegation blocks them.
resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.cloud.name
  address_prefixes     = [var.app_subnet_cidr]

  delegation {
    name = "aca-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# --- On-prem-sim VNet + dc + mgmt subnets ----------------------------------
resource "azurerm_virtual_network" "onprem" {
  name                = "vnet-${var.name_prefix}-onprem"
  location            = local.rg_location
  resource_group_name = local.rg_name
  address_space       = [var.onprem_vnet_cidr]
  dns_servers         = var.vnet_dns_servers
  tags                = var.tags
}

resource "azurerm_subnet" "dc" {
  name                 = "snet-dc"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.onprem.name
  address_prefixes     = [var.dc_subnet_cidr]
}

resource "azurerm_subnet" "mgmt" {
  name                 = "snet-mgmt"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.onprem.name
  address_prefixes     = [var.mgmt_subnet_cidr]
}

# --- Bidirectional peering (stands in for the hybrid VPN/ExpressRoute) ------
resource "azurerm_virtual_network_peering" "cloud_to_onprem" {
  name                         = "peer-cloud-to-onprem"
  resource_group_name          = local.rg_name
  virtual_network_name         = azurerm_virtual_network.cloud.name
  remote_virtual_network_id    = azurerm_virtual_network.onprem.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "onprem_to_cloud" {
  name                         = "peer-onprem-to-cloud"
  resource_group_name          = local.rg_name
  virtual_network_name         = azurerm_virtual_network.onprem.name
  remote_virtual_network_id    = azurerm_virtual_network.cloud.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# --- Private DNS zone for the realm, linked to both VNets -------------------
# Belt-and-suspenders: actual realm resolution comes from Samba's internal DNS
# (VNet dns_servers point at the DC). This zone is the Azure-side stand-in and a
# place to pin an A record for the DC if name resolution needs decoupling.
resource "azurerm_private_dns_zone" "realm" {
  name                = var.domain_realm
  resource_group_name = local.rg_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "cloud" {
  name                  = "link-cloud"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.realm.name
  virtual_network_id    = azurerm_virtual_network.cloud.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "onprem" {
  name                  = "link-onprem"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.realm.name
  virtual_network_id    = azurerm_virtual_network.onprem.id
  registration_enabled  = false
  tags                  = var.tags
}

# --- NSG shells + subnet associations --------------------------------------
# Rules are added in later chunks (SSH in Chunk 2, 636 in Chunk 5/6). Default
# NSG rules already deny inbound internet while allowing intra-VNet + outbound.
resource "azurerm_network_security_group" "dc" {
  name                = "nsg-${var.name_prefix}-dc"
  location            = local.rg_location
  resource_group_name = local.rg_name
  tags                = var.tags
}

resource "azurerm_network_security_group" "mgmt" {
  name                = "nsg-${var.name_prefix}-mgmt"
  location            = local.rg_location
  resource_group_name = local.rg_name
  tags                = var.tags
}

resource "azurerm_network_security_group" "app" {
  name                = "nsg-${var.name_prefix}-app"
  location            = local.rg_location
  resource_group_name = local.rg_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "dc" {
  subnet_id                 = azurerm_subnet.dc.id
  network_security_group_id = azurerm_network_security_group.dc.id
}

resource "azurerm_subnet_network_security_group_association" "mgmt" {
  subnet_id                 = azurerm_subnet.mgmt.id
  network_security_group_id = azurerm_network_security_group.mgmt.id
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}
