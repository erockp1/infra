output "name_prefix" {
  description = "Name prefix in effect."
  value       = var.name_prefix
}

output "unique_suffix" {
  description = "Random suffix seeding globally-unique names."
  value       = random_string.suffix.result
}

output "resource_group_names" {
  description = "Lifecycle-split RG names (created in Chunk 1+, or referenced when create_resource_groups=false)."
  value = {
    net    = local.rg_net_name
    onprem = local.rg_onprem_name
    app    = local.rg_app_name
  }
}

output "dc_fqdn" {
  description = "DC FQDN the LDAPS cert SAN must match and the app connects by."
  value       = local.dc_fqdn
}

output "bind_account_dn" {
  description = "Derived bind service-account DN."
  value       = local.bind_account_dn
}

output "budget_name" {
  description = "Subscription budget guardrail."
  value       = azurerm_consumption_budget_subscription.poc0.name
}

# --- Chunk 1: network ------------------------------------------------------
output "network" {
  description = "Network module summary (VNets, subnets, DNS zone, peering)."
  value = {
    rg               = module.network.rg_net_name
    cloud_vnet       = module.network.cloud_vnet_name
    onprem_vnet      = module.network.onprem_vnet_name
    app_subnet_id    = module.network.app_subnet_id
    dc_subnet_id     = module.network.dc_subnet_id
    mgmt_subnet_id   = module.network.mgmt_subnet_id
    private_dns_zone = module.network.private_dns_zone_name
    peering_ids      = module.network.peering_ids
  }
}

# --- Chunk 2: DC + jump (only when deploy_dc=true) -------------------------
output "dc" {
  description = "DC/jump access details."
  value = var.deploy_dc ? {
    rg             = module.dc[0].rg_onprem_name
    dc_private_ip  = module.dc[0].dc_private_ip
    dc_fqdn        = module.dc[0].dc_fqdn
    jump_public_ip = module.dc[0].jump_public_ip
    ssh            = module.dc[0].ssh_proxyjump_hint
    ldaps_fqdn     = module.dc[0].ldaps_fqdn
  } : null
}

# Chunk 4 — CA cert (public PEM) for the Chunk-5 container trust store.
output "ca_cert_pem" {
  description = "Rig Root CA (PEM). `terraform output -raw ca_cert_pem > validate/ca.pem`."
  value       = var.deploy_dc ? module.dc[0].ca_cert_pem : null
}

# --- Chunk 5: the bind app -------------------------------------------------
output "app" {
  description = "Container Apps env + bind app details."
  value = var.deploy_app ? {
    rg               = module.app[0].rg_app_name
    acr_login_server = module.app[0].acr_login_server
    image_ref        = module.app[0].image_ref
    app_url          = module.app[0].app_url
  } : null
}

# --- Chunk 6: QuickSignals -------------------------------------------------
output "quicksignals" {
  description = "QuickSignals app details (null until deploy_quicksignals; fqdn null until image_pushed)."
  value = var.deploy_quicksignals ? {
    identity_principal_id = module.quicksignals[0].identity_principal_id
    fqdn                  = module.quicksignals[0].fqdn
    url                   = module.quicksignals[0].url
    spa_web_host          = module.quicksignals[0].spa_web_host
    spa_storage_account   = module.quicksignals[0].spa_storage_account_name
  } : null
}

# --- Chunk 8: BalDayDashboard ----------------------------------------------
output "baldaydashboard" {
  description = "BalDayDashboard app details (null until deploy_baldaydashboard; fqdn null until image_pushed)."
  value = var.deploy_baldaydashboard ? {
    identity_principal_id = module.baldaydashboard[0].identity_principal_id
    fqdn                  = module.baldaydashboard[0].fqdn
    url                   = module.baldaydashboard[0].url
    spa_web_host          = module.baldaydashboard[0].spa_web_host
    spa_storage_account   = module.baldaydashboard[0].spa_storage_account_name
  } : null
}

# --- Chunk 7: Front Door ---------------------------------------------------
output "frontdoor" {
  description = "Front Door per-app endpoints + FDID (null until deploy_frontdoor). Feed front_door_id into <app>_front_door_id and re-apply to arm the origin lock."
  value = var.deploy_frontdoor ? {
    front_door_id = module.frontdoor[0].front_door_id
    endpoints     = module.frontdoor[0].endpoint_urls
  } : null
}
