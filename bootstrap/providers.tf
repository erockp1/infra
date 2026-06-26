terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Bootstrap uses azurerm's default provider registration so Microsoft.Storage /
# Microsoft.Resources self-register on a fresh subscription. The ROOT config (one
# level up) manages provider registration explicitly.
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}
