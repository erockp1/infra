# ===========================================================================
# Chunk 7 — Front Door (POC 1, Phase C). The single public front door, now
# MULTI-APP: a shared profile + WAF, and one endpoint (hostname) PER app via
# for_each over var.apps. Per app:
#   /*                       -> that app's SPA static-website origin (Blob $web)
#   /login|/<app-prefix>|... -> that app's ACA (the Django API), same-origin
# Standard tier + one CUSTOM WAF rule (managed rulesets + Private Link are
# corporate-deferred). The FD->ACA hop is secured by the X-Azure-FDID header
# (the profile resource_guid), enforced by app middleware. terraform destroy
# between sessions — Front Door has a base fee and no scale-to-zero.
# ===========================================================================

resource "azurerm_cdn_frontdoor_profile" "this" {
  name                = "afd-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  sku_name            = "Standard_AzureFrontDoor"
  tags                = var.tags
}

# --- One endpoint per app ----------------------------------------------------
resource "azurerm_cdn_frontdoor_endpoint" "this" {
  for_each                 = var.apps
  name                     = "ep-${var.name_prefix}-${each.key}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  tags                     = var.tags
}

# --- SPA origin group + origin (per app) ------------------------------------
resource "azurerm_cdn_frontdoor_origin_group" "spa" {
  for_each                 = var.apps
  name                     = "og-spa-${each.key}"
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
  for_each                       = var.apps
  name                           = "origin-spa-${each.key}"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.spa[each.key].id
  enabled                        = true
  host_name                      = each.value.spa_web_host
  origin_host_header             = each.value.spa_web_host
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}

# --- ACA (API) origin group + origin (per app) ------------------------------
resource "azurerm_cdn_frontdoor_origin_group" "aca" {
  for_each                 = var.apps
  name                     = "og-aca-${each.key}"
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
  for_each                       = var.apps
  name                           = "origin-aca-${each.key}"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.aca[each.key].id
  enabled                        = true
  host_name                      = each.value.aca_fqdn
  origin_host_header             = each.value.aca_fqdn
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}

# --- Routes (per app): API patterns to ACA, everything else to the SPA ------
resource "azurerm_cdn_frontdoor_route" "aca" {
  for_each                      = var.apps
  name                          = "route-aca-${each.key}"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this[each.key].id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.aca[each.key].id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.aca[each.key].id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = each.value.api_route_patterns
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  link_to_default_domain = true
}

resource "azurerm_cdn_frontdoor_route" "spa" {
  for_each                      = var.apps
  name                          = "route-spa-${each.key}"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this[each.key].id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.spa[each.key].id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.spa[each.key].id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  link_to_default_domain = true
}

# --- WAF: one shared custom rule, to prove 'WAF in the path' -----------------
resource "azurerm_cdn_frontdoor_firewall_policy" "this" {
  name                = "waf${var.name_prefix}poc"
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

# Associate the WAF with EVERY app endpoint via ONE security policy (a WAF policy
# can be attached to a profile only once; a single association carries all the
# endpoint domains).
resource "azurerm_cdn_frontdoor_security_policy" "this" {
  name                     = "secpol-${var.name_prefix}-poc"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.this.id
      association {
        patterns_to_match = ["/*"]
        dynamic "domain" {
          for_each = azurerm_cdn_frontdoor_endpoint.this
          content {
            cdn_frontdoor_domain_id = domain.value.id
          }
        }
      }
    }
  }
}
