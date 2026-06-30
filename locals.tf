locals {
  # --- Tags applied everywhere -------------------------------------------
  base_tags = {
    owner        = var.owner
    purpose      = "poc0"
    env          = var.env
    managed_by   = "terraform"
    delete_after = var.delete_after
  }
  tags = merge(local.base_tags, var.tags)

  # --- Resource group names (create-or-reference is wired in Chunk 1) -----
  rg_net_name    = coalesce(var.rg_net_name, "rg-${var.name_prefix}-net")
  rg_onprem_name = coalesce(var.rg_onprem_name, "rg-${var.name_prefix}-onprem")
  rg_app_name    = coalesce(var.rg_app_name, "rg-${var.name_prefix}-app")

  # --- Derived domain values ---------------------------------------------
  dc_fqdn         = "${var.dc_hostname}.${var.domain_realm}"
  bind_account_dn = "CN=${var.bind_account_cn},OU=${var.ou_name},${var.base_dn}"

  # --- Globally-unique names (prefix + random suffix; charset-clean) ------
  acr_name = substr("${var.name_prefix}acr${random_string.suffix.result}", 0, 50)

  # --- Shared LDAP duality config (Phase B) ------------------------------
  # Identical for every cloud-served app: point the LDAPS branch at the Samba DC.
  # The corporate port swaps these via tfvars (real ALTOP-DC01) without touching
  # any module. Each app merges this with its own (rig-only) AUTH_STUB_PERMISSIONS
  # and (two-phase) FRONT_DOOR_ID.
  ldap_extra_env = {
    LDAP_HOST              = local.dc_fqdn
    LDAP_PORT              = "636"
    LDAP_USE_SSL           = "true"
    LDAP_AUTH_METHOD       = "SIMPLE"
    LDAP_BASE_DN           = var.base_dn
    LDAP_REALM             = var.domain_realm
    LDAP_BIND_USER         = local.bind_account_dn
    LDAP_USER_SEARCH_BASES = "OU=${var.ou_name},${var.base_dn}"
    LDAP_ALLOWED_DOMAINS   = var.domain_realm
  }
}
