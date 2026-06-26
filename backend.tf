# Remote state in Azure Storage (stood up by ../bootstrap). The storage account
# name is globally unique (random suffix), so it cannot be hardcoded here — supply
# the concrete values at init time:
#
#   terraform init -backend-config=backend.hcl
#
# where backend.hcl is produced from `terraform -chdir=bootstrap output backend_hcl`.
# backend.hcl is git-ignored (environment-specific, not secret with AAD auth).
terraform {
  backend "azurerm" {}
}
