output "identity_id" {
  description = "This app's own user-assigned identity ID (for a future Key Vault grant)."
  value       = azurerm_user_assigned_identity.app.id
}

output "identity_principal_id" {
  description = "Principal ID — scope Key Vault Secrets User to this when secrets move to Key Vault."
  value       = azurerm_user_assigned_identity.app.principal_id
}

output "fqdn" {
  description = "Public ingress FQDN (null until image_pushed)."
  value       = var.image_pushed ? azurerm_container_app.app[0].ingress[0].fqdn : null
}

output "url" {
  value = var.image_pushed ? "https://${azurerm_container_app.app[0].ingress[0].fqdn}" : null
}

output "app_fqdn" {
  description = "The ACA ingress FQDN as a string (knowable without the resource) — Front Door's API origin host."
  value       = local.app_fqdn
}

output "spa_web_host" {
  description = "Static-website host of the SPA storage ($web) — Front Door's default (/*) origin host."
  value       = azurerm_storage_account.spa.primary_web_host
}

output "spa_storage_account_name" {
  description = "SPA storage account name (for `az storage blob upload-batch` to $web)."
  value       = azurerm_storage_account.spa.name
}
