# Stable random suffix for globally-unique names (ACR, etc.). Defined once so
# names never churn across chunks/re-applies.
resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# ---------------------------------------------------------------------------
# Modules are wired in additively, one per chunk (each gated so a chunk is a
# clean `terraform apply -var ...` increment on one repo):
#
#   Chunk 1 -> module "network"  (RG, VNets, peering, private DNS, NSG shells)
#   Chunk 2 -> module "dc"        (DC VM + jump; gated by var.deploy_dc)
#   Chunk 5 -> module "app"       (Container Apps env + bind app; var.deploy_app)
# ---------------------------------------------------------------------------

# Chunk 1 — the simulated hybrid boundary.
module "network" {
  source = "./modules/network"

  name_prefix = var.name_prefix
  location    = var.location
  tags        = local.tags

  create_resource_groups = var.create_resource_groups
  rg_net_name            = local.rg_net_name

  cloud_vnet_cidr  = var.cloud_vnet_cidr
  onprem_vnet_cidr = var.onprem_vnet_cidr
  app_subnet_cidr  = var.app_subnet_cidr
  dc_subnet_cidr   = var.dc_subnet_cidr
  mgmt_subnet_cidr = var.mgmt_subnet_cidr

  # Point both VNets' DNS at the DC's reserved static IP (resolution comes online
  # in Chunk 3 once Samba serves DNS; harmless until then — no VMs yet).
  vnet_dns_servers = [var.dc_static_ip]
  domain_realm     = var.domain_realm

  depends_on = [azurerm_resource_provider_registration.network]
}

# Chunk 2 — the DC VM (bare) + jump admin access. Gated by deploy_dc.
module "dc" {
  source = "./modules/dc"
  count  = var.deploy_dc ? 1 : 0

  name_prefix = var.name_prefix
  location    = var.location
  tags        = local.tags

  create_resource_groups = var.create_resource_groups
  rg_onprem_name         = local.rg_onprem_name
  rg_net_name            = module.network.rg_net_name

  dc_subnet_id   = module.network.dc_subnet_id
  mgmt_subnet_id = module.network.mgmt_subnet_id
  dc_nsg_name    = module.network.dc_nsg_name
  mgmt_nsg_name  = module.network.mgmt_nsg_name

  mgmt_subnet_cidr = var.mgmt_subnet_cidr
  app_subnet_cidr  = var.app_subnet_cidr
  dc_static_ip     = var.dc_static_ip

  dc_vm_size      = var.dc_vm_size
  jump_vm_size    = var.jump_vm_size
  dc_data_disk_gb = var.dc_data_disk_gb
  dc_image        = var.dc_image
  admin_username  = var.admin_username
  ssh_public_key  = var.ssh_public_key
  home_ip_cidr    = var.home_ip_cidr

  dc_hostname  = var.dc_hostname
  domain_realm = var.domain_realm

  # Chunk 3 — Samba-AD provisioning inputs.
  domain_netbios        = var.domain_netbios
  base_dn               = var.base_dn
  ou_name               = var.ou_name
  dns_forwarder         = var.dns_forwarder
  bind_account_cn       = var.bind_account_cn
  domain_admin_password = var.domain_admin_password
  bind_account_password = var.bind_account_password
  test_users            = var.test_users

  depends_on = [azurerm_resource_provider_registration.compute]
}

# Chunk 5 — the Container App that performs the bind. Gated by deploy_app.
module "app" {
  source = "./modules/app"
  count  = var.deploy_app ? 1 : 0

  name_prefix = var.name_prefix
  location    = var.location
  tags        = local.tags

  create_resource_groups = var.create_resource_groups
  rg_app_name            = local.rg_app_name
  app_subnet_id          = module.network.app_subnet_id

  acr_name         = local.acr_name
  acr_sku          = var.acr_sku
  app_image_tag    = var.app_image_tag
  app_image_pushed = var.app_image_pushed

  dc_fqdn               = local.dc_fqdn
  base_dn               = var.base_dn
  domain_realm          = var.domain_realm
  bind_account_dn       = local.bind_account_dn
  bind_account_password = var.bind_account_password

  depends_on = [
    azurerm_resource_provider_registration.app,
    azurerm_resource_provider_registration.containerregistry,
    azurerm_resource_provider_registration.operationalinsights,
  ]
}

# Chunk 6 — QuickSignals (POC 1), the first cloud-native app. Reuses the Chunk-5
# substrate (Container Apps env + ACR) but brings its OWN identity. Gated by
# deploy_quicksignals; requires deploy_app=true (it consumes module.app[0]).
module "quicksignals" {
  source = "./modules/quicksignals"
  count  = var.deploy_quicksignals ? 1 : 0

  name_prefix = var.name_prefix
  location    = var.location
  tags        = local.tags

  resource_group_name          = module.app[0].rg_app_name
  container_app_environment_id = module.app[0].environment_id
  environment_default_domain   = module.app[0].environment_default_domain
  acr_login_server             = module.app[0].acr_login_server
  acr_id                       = module.app[0].acr_id
  unique_suffix                = random_string.suffix.result

  image_tag         = var.quicksignals_image_tag
  image_pushed      = var.quicksignals_image_pushed
  django_secret_key = var.quicksignals_django_secret_key

  # Duality (Phase B): point the cloud LDAPS branch at the Samba DC. These derive
  # from the same realm/DC vars the DC module uses, so the corporate port swaps
  # them via tfvars (real ALTOP-DC01) without touching this block. AUTH_STUB_*
  # is gated on a rig-only flag so it can never leak into a corporate deploy.
  extra_env = merge({
    LDAP_HOST              = local.dc_fqdn
    LDAP_PORT              = "636"
    LDAP_USE_SSL           = "true"
    LDAP_AUTH_METHOD       = "SIMPLE"
    LDAP_BASE_DN           = var.base_dn
    LDAP_REALM             = var.domain_realm
    LDAP_BIND_USER         = local.bind_account_dn
    LDAP_USER_SEARCH_BASES = "OU=${var.ou_name},${var.base_dn}"
    LDAP_ALLOWED_DOMAINS   = var.domain_realm
    },
    var.quicksignals_stub_permissions ? { AUTH_STUB_PERMISSIONS = "true" } : {},
    # Origin lock (Phase C): set once Front Door exists (two-phase). When present,
    # the middleware 403s any request to the ACA FQDN lacking the matching FDID.
    var.quicksignals_front_door_id != "" ? { FRONT_DOOR_ID = var.quicksignals_front_door_id } : {},
  )
  ldap_bind_password = var.bind_account_password

  # Warm replica for an interactive dashboard; set 0 to scale-to-zero for the rig budget.
  min_replicas = 1

  depends_on = [module.app]
}

# Chunk 7 — Front Door (POC 1, Phase C). The shared public edge. Gated by
# deploy_frontdoor; requires deploy_quicksignals=true. Consumes QuickSignals'
# SPA storage host + ACA FQDN (module.quicksignals outputs that don't depend on
# Front Door — no cycle). FRONT_DOOR_ID flows BACK to the app via the two-phase
# var.quicksignals_front_door_id (apply FD, read its front_door_id, re-apply).
module "frontdoor" {
  source = "./modules/frontdoor"
  count  = var.deploy_frontdoor ? 1 : 0

  name_prefix         = var.name_prefix
  tags                = local.tags
  resource_group_name = module.app[0].rg_app_name

  spa_web_host = module.quicksignals[0].spa_web_host
  aca_fqdn     = module.quicksignals[0].app_fqdn

  depends_on = [module.quicksignals]
}
