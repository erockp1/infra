# ===========================================================================
# Chunk 6 — QuickSignals (POC1), the first cloud-native app.
#
# Reuses the SHARED substrate created by module "app" (Chunk 5): the Container
# Apps environment and the ACR. But it brings its OWN managed identity so its
# permissions (ACR pull now, Key Vault later) are scoped per-app and never
# entangled with the binder's identity.
# ===========================================================================

locals {
  app_name  = "ca-${var.name_prefix}-quicksignals"
  image_ref = "${var.acr_login_server}/quicksignals:${var.image_tag}"
  # ACA-assigned hostname, knowable without a cycle (name + env domain). Feeds ALLOWED_HOSTS.
  app_fqdn = "${local.app_name}.${var.environment_default_domain}"
}

# --- This app's OWN identity + pull rights on the SHARED registry ----------
resource "azurerm_user_assigned_identity" "qs" {
  name                = "id-${var.name_prefix}-quicksignals"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "qs_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.qs.principal_id
}

# --- The app (created only once its image is in ACR) -----------------------
resource "azurerm_container_app" "quicksignals" {
  count = var.image_pushed ? 1 : 0

  name                         = local.app_name
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.qs.id]
  }

  registry {
    server   = var.acr_login_server
    identity = azurerm_user_assigned_identity.qs.id
  }

  # POC0 has no Key Vault yet, so match the binder's inline-secret pattern (TEST-ONLY).
  # Swap to a key_vault_secret_id + identity reference once a Key Vault chunk exists.
  secret {
    name  = "django-secret-key"
    value = var.django_secret_key
  }

  ingress {
    external_enabled = true
    target_port      = 8000 # Django/gunicorn (the binder was 8080)
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
      name   = "quicksignals"
      image  = local.image_ref
      cpu    = var.cpu
      memory = var.memory

      # Pin settings explicitly — bypasses the WEBSITE_HOSTNAME detection ACA can't satisfy.
      env {
        name  = "DJANGO_SETTINGS_MODULE"
        value = "backend.deployment"
      }
      env {
        name  = "RUNNING_IN_CLOUD"
        value = "true"
      }
      # Feeds deployment.py ALLOWED_HOSTS/CSRF with no app code change.
      env {
        name  = "WEBSITE_HOSTNAME"
        value = local.app_fqdn
      }
      env {
        name        = "DJANGO_SECRET_KEY"
        secret_name = "django-secret-key"
      }

      # Platform health on the unauthenticated /healthz route (FDID-exempt, no DB
      # touch). The probe hits the replica directly with Host: <pod-ip>; that is
      # why deployment.py adds the replica's own resolved IP(s) to ALLOWED_HOSTS,
      # so the probe doesn't 400 as DisallowedHost and strand the revision.
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
    # The app CI pipeline owns the image tag (az containerapp update); TF owns the shape.
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [azurerm_role_assignment.qs_acr_pull]
}
