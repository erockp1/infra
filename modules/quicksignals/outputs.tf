output "identity_id" {
  description = "QuickSignals' own user-assigned identity ID (for a future Key Vault access grant)."
  value       = azurerm_user_assigned_identity.qs.id
}

output "identity_principal_id" {
  description = "Principal ID — scope Key Vault Secrets User to this when secrets move to Key Vault."
  value       = azurerm_user_assigned_identity.qs.principal_id
}

output "fqdn" {
  description = "Public ingress FQDN (null until image_pushed)."
  value       = var.image_pushed ? azurerm_container_app.quicksignals[0].ingress[0].fqdn : null
}

output "url" {
  value = var.image_pushed ? "https://${azurerm_container_app.quicksignals[0].ingress[0].fqdn}" : null
}
