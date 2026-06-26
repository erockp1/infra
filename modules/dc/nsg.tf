# ===========================================================================
# Chunk 2 — admin-path NSG rules attached to the Chunk-1 NSG shells (which live
# in the networking RG). Default-deny is already in effect via the NSGs' default
# rules; these open exactly the SSH paths. The bind port (636) is opened in
# Chunk 6.
# ===========================================================================

# Jump VM: SSH only from the home IP /32.
resource "azurerm_network_security_rule" "mgmt_ssh_from_home" {
  name                        = "Allow-SSH-from-home"
  resource_group_name         = var.rg_net_name
  network_security_group_name = var.mgmt_nsg_name
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = var.home_ip_cidr
  destination_address_prefix  = "*"
}

# DC: SSH only from the mgmt subnet (i.e. via the jump), never the internet.
resource "azurerm_network_security_rule" "dc_ssh_from_mgmt" {
  name                        = "Allow-SSH-from-mgmt"
  resource_group_name         = var.rg_net_name
  network_security_group_name = var.dc_nsg_name
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = var.mgmt_subnet_cidr
  destination_address_prefix  = "*"
}

# ===========================================================================
# Chunk 6 — least-privilege hardening of the DC subnet. The cloud reaches IN
# over a narrow path (LDAPS 636 + DNS 53 — DNS is required for the by-name
# resolution the POC proves); on-prem initiates NOTHING toward the cloud.
# Everything else from the VNet is denied (overriding the default AllowVnetInBound).
# ===========================================================================

# --- The cloud bind path: app subnet -> DC on 636 (the POC invariant) ------
resource "azurerm_network_security_rule" "dc_ldaps_from_app" {
  name                        = "Allow-LDAPS-from-app"
  resource_group_name         = var.rg_net_name
  network_security_group_name = var.dc_nsg_name
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "636"
  source_address_prefix       = var.app_subnet_cidr
  destination_address_prefix  = "*"
}

# --- DNS (53) so the cloud resolves the DC by name across the boundary -----
resource "azurerm_network_security_rule" "dc_dns_from_app" {
  name                        = "Allow-DNS-from-app"
  resource_group_name         = var.rg_net_name
  network_security_group_name = var.dc_nsg_name
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*" # UDP + TCP 53
  source_port_range           = "*"
  destination_port_ranges     = ["53"]
  source_address_prefix       = var.app_subnet_cidr
  destination_address_prefix  = "*"
}

# --- Jump-path validation: mgmt subnet -> DC on 636 + 53 -------------------
resource "azurerm_network_security_rule" "dc_ldaps_dns_from_mgmt" {
  name                        = "Allow-LDAPS-DNS-from-mgmt"
  resource_group_name         = var.rg_net_name
  network_security_group_name = var.dc_nsg_name
  priority                    = 130
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_ranges     = ["53", "636"]
  source_address_prefix       = var.mgmt_subnet_cidr
  destination_address_prefix  = "*"
}

# --- Default-deny the rest of intra-VNet inbound ---------------------------
resource "azurerm_network_security_rule" "dc_deny_vnet_inbound" {
  name                        = "Deny-all-other-VNet-inbound"
  resource_group_name         = var.rg_net_name
  network_security_group_name = var.dc_nsg_name
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
}

# --- On-prem initiates nothing toward the cloud ----------------------------
# Stateful NSG still lets LDAPS/DNS *responses* flow; this only blocks the DC
# from *initiating* connections into the cloud subnet — making the invariant explicit.
resource "azurerm_network_security_rule" "dc_deny_outbound_to_cloud" {
  name                        = "Deny-DC-initiated-to-cloud"
  resource_group_name         = var.rg_net_name
  network_security_group_name = var.dc_nsg_name
  priority                    = 4000
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = var.app_subnet_cidr
}
