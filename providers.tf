provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

  # We register resource providers EXPLICITLY below, so disable azurerm's
  # automatic registration. (azurerm 4.x otherwise auto-registers a default set,
  # which collides with the azurerm_resource_provider_registration resources for
  # providers already in that set — e.g. Microsoft.Network / Microsoft.Compute.)
  resource_provider_registrations = "none"
}

# ---------------------------------------------------------------------------
# Explicit resource-provider registration. A fresh subscription leaves many
# unregistered; the first resource of a given provider fails until it is.
# Registration is async (minutes) — let Chunk 0 settle before Chunk 1.
#
# The five required by the spec, plus two the rig's resources also need:
#   Microsoft.ManagedIdentity  -> user-assigned identity for the Container App (Chunk 5)
#   Microsoft.Consumption      -> the subscription budget (Chunk 0, below)
# ---------------------------------------------------------------------------
# count = var.manage_subscription_singletons ? 1 : 0 gates these subscription-scoped
# singletons off for the discovery harness (same sub: already registered, so they
# no-op and never surface their perms). The `moved` blocks below keep the rig's
# existing state zero-churn through the count addition.
resource "azurerm_resource_provider_registration" "network" {
  count = var.manage_subscription_singletons ? 1 : 0
  name  = "Microsoft.Network"
}

resource "azurerm_resource_provider_registration" "compute" {
  count = var.manage_subscription_singletons ? 1 : 0
  name  = "Microsoft.Compute"
}

resource "azurerm_resource_provider_registration" "app" {
  count = var.manage_subscription_singletons ? 1 : 0
  name  = "Microsoft.App"
}

resource "azurerm_resource_provider_registration" "containerregistry" {
  count = var.manage_subscription_singletons ? 1 : 0
  name  = "Microsoft.ContainerRegistry"
}

resource "azurerm_resource_provider_registration" "operationalinsights" {
  count = var.manage_subscription_singletons ? 1 : 0
  name  = "Microsoft.OperationalInsights"
}

resource "azurerm_resource_provider_registration" "managedidentity" {
  count = var.manage_subscription_singletons ? 1 : 0
  name  = "Microsoft.ManagedIdentity"
}

resource "azurerm_resource_provider_registration" "consumption" {
  count = var.manage_subscription_singletons ? 1 : 0
  name  = "Microsoft.Consumption"
}

# Zero-churn migration of the rig state from the un-counted addresses to [0].
moved {
  from = azurerm_resource_provider_registration.network
  to   = azurerm_resource_provider_registration.network[0]
}
moved {
  from = azurerm_resource_provider_registration.compute
  to   = azurerm_resource_provider_registration.compute[0]
}
moved {
  from = azurerm_resource_provider_registration.app
  to   = azurerm_resource_provider_registration.app[0]
}
moved {
  from = azurerm_resource_provider_registration.containerregistry
  to   = azurerm_resource_provider_registration.containerregistry[0]
}
moved {
  from = azurerm_resource_provider_registration.operationalinsights
  to   = azurerm_resource_provider_registration.operationalinsights[0]
}
moved {
  from = azurerm_resource_provider_registration.managedidentity
  to   = azurerm_resource_provider_registration.managedidentity[0]
}
moved {
  from = azurerm_resource_provider_registration.consumption
  to   = azurerm_resource_provider_registration.consumption[0]
}
