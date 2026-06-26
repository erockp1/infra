output "resource_group_name" {
  description = "RG holding the Terraform state storage account."
  value       = azurerm_resource_group.tfstate.name
}

output "storage_account_name" {
  description = "Globally-unique state storage account name (feed into root backend.hcl)."
  value       = azurerm_storage_account.tfstate.name
}

output "container_name" {
  description = "Blob container for state."
  value       = azurerm_storage_container.tfstate.name
}

# Convenience: the exact backend.hcl body to write for the root config.
output "backend_hcl" {
  description = "Paste/redirect into ../backend.hcl, then: terraform init -backend-config=backend.hcl"
  value       = <<-EOT
    resource_group_name  = "${azurerm_resource_group.tfstate.name}"
    storage_account_name = "${azurerm_storage_account.tfstate.name}"
    container_name       = "${azurerm_storage_container.tfstate.name}"
    key                  = "poc0.tfstate"
    use_azuread_auth     = true
  EOT
}
