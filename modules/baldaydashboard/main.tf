# ===========================================================================
# Chunk 8 — BalDayDashboard (POC 1, Phase D), the second cloud-native app.
#
# Identical shape to the QuickSignals module (Chunk 6): reuses the SHARED
# substrate (Container Apps env + ACR) but brings its OWN identity. This is the
# "repeat the pattern" app; the natural next refactor is to fold both into one
# parameterized module for the migrate-rest multiplier.
# ===========================================================================

locals {
  app_name  = "ca-${var.name_prefix}-baldaydashboard"
  image_ref = "${var.acr_login_server}/baldaydashboard:${var.image_tag}"
  app_fqdn  = "${local.app_name}.${var.environment_default_domain}"
}

# --- SPA static website (Phase C) -------------------------------------------
resource "azurerm_storage_account" "spa" {
  name                       = "st${var.name_prefix}bd${var.unique_suffix}"
  resource_group_name        = var.resource_group_name
  location                   = var.location
  account_tier               = "Standard"
  account_replication_type   = "LRS"
  account_kind               = "StorageV2"
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"
  tags                       = var.tags

  static_website {
    index_document     = "index.html"
    error_404_document = "index.html"
  }
}

# --- This app's OWN identity + pull rights on the SHARED registry ----------
resource "azurerm_user_assigned_identity" "bd" {
  name                = "id-${var.name_prefix}-baldaydashboard"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "bd_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.bd.principal_id
}

# --- The app (created only once its image is in ACR) -----------------------
resource "azurerm_container_app" "baldaydashboard" {
  count = var.image_pushed ? 1 : 0

  name                         = local.app_name
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.bd.id]
  }

  registry {
    server   = var.acr_login_server
    identity = azurerm_user_assigned_identity.bd.id
  }

  secret {
    name  = "django-secret-key"
    value = var.django_secret_key
  }

  dynamic "secret" {
    for_each = var.ldap_bind_password == null ? [] : [1]
    content {
      name  = "ldap-bind-password"
      value = var.ldap_bind_password
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8000
    transport        = "auto"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "baldaydashboard"
      image  = local.image_ref
      cpu    = var.cpu
      memory = var.memory

      env {
        name  = "DJANGO_SETTINGS_MODULE"
        value = "backend.deployment"
      }
      env {
        name  = "RUNNING_IN_CLOUD"
        value = "true"
      }
      env {
        name  = "WEBSITE_HOSTNAME"
        value = local.app_fqdn
      }
      env {
        name        = "DJANGO_SECRET_KEY"
        secret_name = "django-secret-key"
      }

      dynamic "env" {
        for_each = var.extra_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.ldap_bind_password == null ? [] : [1]
        content {
          name        = "LDAP_BIND_PASSWORD"
          secret_name = "ldap-bind-password"
        }
      }

      liveness_probe {
        transport               = "HTTP"
        port                    = 8000
        path                    = "/healthz"
        initial_delay           = 10
        interval_seconds        = 30
        timeout                 = 5
        failure_count_threshold = 3
      }
      readiness_probe {
        transport               = "HTTP"
        port                    = 8000
        path                    = "/healthz"
        interval_seconds        = 10
        timeout                 = 5
        failure_count_threshold = 3
        success_count_threshold = 1
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [azurerm_role_assignment.bd_acr_pull]
}
