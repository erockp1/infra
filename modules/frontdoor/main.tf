# ===========================================================================
# Chunk 7 — Front Door (POC 1, Phase C). The single public front door:
#   /*                       -> SPA static-website origin (Blob $web)
#   /login|/quicksignal|...  -> ACA (the Django API), same-origin to the SPA
# Standard tier + one CUSTOM WAF rule (managed rulesets + Private Link are
# corporate-deferred). Secures the FD->ACA hop with the X-Azure-FDID header
# (the profile's resource_guid), enforced by app middleware. terraform destroy
# this between sessions — Front Door has a base fee and no scale-to-zero.
# ===========================================================================

resource "azurerm_cdn_frontdoor_profile" "this" {
  name                = "afd-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  sku_name            = "Standard_AzureFrontDoor"
  tags                = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = "ep-${var.name_prefix}-qs"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  tags                     = var.tags
}

# --- Origin groups + origins ------------------------------------------------
resource "azurerm_cdn_frontdoor_origin_group" "spa" {
  name                     = "og-spa"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 50
  }
  health_probe {
    path                = "/"
    request_type        = "HEAD"
    protocol            = "Https"
    interval_in_seconds = 120
  }
}

resource "azurerm_cdn_frontdoor_origin" "spa" {
  name                           = "origin-spa"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.spa.id
  enabled                        = true
  host_name                      = var.spa_web_host
  origin_host_header             = var.spa_web_host
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_origin_group" "aca" {
  name                     = "og-aca"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 50
  }
  # The unauthenticated, FDID-exempt health route.
  health_probe {
    path                = "/healthz"
    request_type        = "GET"
    protocol            = "Https"
    interval_in_seconds = 120
  }
}

resource "azurerm_cdn_frontdoor_origin" "aca" {
  name                           = "origin-aca"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.aca.id
  enabled                        = true
  host_name                      = var.aca_fqdn
  origin_host_header             = var.aca_fqdn
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}

# --- Routes -----------------------------------------------------------------
# API route first (more specific patterns); the SPA route catches everything else.
resource "azurerm_cdn_frontdoor_route" "aca" {
  name                          = "route-aca"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.aca.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.aca.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = var.api_route_patterns
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  link_to_default_domain = true
}

resource "azurerm_cdn_frontdoor_route" "spa" {
  name                          = "route-spa"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.spa.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.spa.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  link_to_default_domain = true
}

# --- WAF: one custom rule, to prove 'WAF in the path' -----------------------
resource "azurerm_cdn_frontdoor_firewall_policy" "this" {
  name                = "waf${var.name_prefix}qs"
  resource_group_name = var.resource_group_name
  sku_name            = "Standard_AzureFrontDoor"
  enabled             = true
  mode                = "Prevention"
  tags                = var.tags

  custom_rule {
    name     = "BlockSentinel"
    enabled  = true
    priority = 1
    type     = "MatchRule"
    action   = "Block"

    match_condition {
      match_variable = "RequestUri"
      operator       = "Contains"
      match_values   = [var.waf_block_sentinel]
    }
  }
}

resource "azurerm_cdn_frontdoor_security_policy" "this" {
  name                     = "secpol-${var.name_prefix}-qs"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.this.id
      association {
        patterns_to_match = ["/*"]
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.this.id
        }
      }
    }
  }
}
