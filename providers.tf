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
resource "azurerm_resource_provider_registration" "network" {
  name = "Microsoft.Network"
}

resource "azurerm_resource_provider_registration" "compute" {
  name = "Microsoft.Compute"
}

resource "azurerm_resource_provider_registration" "app" {
  name = "Microsoft.App"
}

resource "azurerm_resource_provider_registration" "containerregistry" {
  name = "Microsoft.ContainerRegistry"
}

resource "azurerm_resource_provider_registration" "operationalinsights" {
  name = "Microsoft.OperationalInsights"
}

resource "azurerm_resource_provider_registration" "managedidentity" {
  name = "Microsoft.ManagedIdentity"
}

resource "azurerm_resource_provider_registration" "consumption" {
  name = "Microsoft.Consumption"
}
