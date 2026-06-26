# ===========================================================================
# Chunk 5 — the stateless, non-domain-joined, scale-to-zero Container App that
# performs the LDAPS bind across the peering. Log Analytics + ACR + a
# VNet-integrated Container Apps environment (Consumption workload profile).
# ===========================================================================

# --- Cloud-app RG: create (rig) or reference (corporate) -------------------
resource "azurerm_resource_group" "app" {
  count    = var.create_resource_groups ? 1 : 0
  name     = var.rg_app_name
  location = var.location
  tags     = var.tags
}

data "azurerm_resource_group" "app" {
  count = var.create_resource_groups ? 0 : 1
  name  = var.rg_app_name
}

locals {
  rg_name     = var.create_resource_groups ? azurerm_resource_group.app[0].name : data.azurerm_resource_group.app[0].name
  rg_location = var.create_resource_groups ? azurerm_resource_group.app[0].location : data.azurerm_resource_group.app[0].location
  image_ref   = "${azurerm_container_registry.acr.login_server}/ldap-binder:${var.app_image_tag}"
}

# --- Observability ---------------------------------------------------------
resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.name_prefix}"
  location            = local.rg_location
  resource_group_name = local.rg_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# --- Registry + managed-identity pull (the corporate RBAC pattern) ---------
resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = local.rg_name
  location            = local.rg_location
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${var.name_prefix}-binder"
  resource_group_name = local.rg_name
  location            = local.rg_location
  tags                = var.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# --- VNet-integrated Container Apps environment (Consumption profile) -------
resource "azurerm_container_app_environment" "this" {
  name                       = "cae-${var.name_prefix}"
  resource_group_name        = local.rg_name
  location                   = local.rg_location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  # VNet integration: egress routes over the peering to the DC. The subnet is
  # delegated to Microsoft.App/environments (Chunk 1).
  infrastructure_subnet_id       = var.app_subnet_id
  internal_load_balancer_enabled = false

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  tags = var.tags
}

# --- The bind app (created only once the image is in ACR) ------------------
resource "azurerm_container_app" "binder" {
  count = var.app_image_pushed ? 1 : 0

  name                         = "ca-${var.name_prefix}-binder"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = local.rg_name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.app.id
  }

  secret {
    name  = "bind-pw"
    value = var.bind_account_password
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "auto"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 0 # scale to zero — sits in the free grant
    max_replicas = 1

    container {
      name   = "binder"
      image  = local.image_ref
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "DC_FQDN"
        value = var.dc_fqdn
      }
      env {
        name  = "BASE_DN"
        value = var.base_dn
      }
      env {
        name  = "REALM"
        value = var.domain_realm
      }
      env {
        name  = "BIND_DN"
        value = var.bind_account_dn
      }
      env {
        name        = "BIND_PW"
        secret_name = "bind-pw"
      }

      liveness_probe {
        transport = "HTTP"
        path      = "/healthz"
        port      = 8080
      }
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}
