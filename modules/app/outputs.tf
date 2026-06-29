output "rg_app_name" {
  value = local.rg_name
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "acr_name" {
  value = azurerm_container_registry.acr.name
}

output "acr_id" {
  description = "ACR resource ID — the scope a per-app AcrPull grant (e.g. QuickSignals, Chunk 6) targets."
  value       = azurerm_container_registry.acr.id
}

output "image_ref" {
  value = local.image_ref
}

output "environment_id" {
  value = azurerm_container_app_environment.this.id
}

output "environment_default_domain" {
  value = azurerm_container_app_environment.this.default_domain
}

output "app_fqdn" {
  description = "Public ingress FQDN of the bind app (null until app_image_pushed)."
  value       = var.app_image_pushed ? azurerm_container_app.binder[0].ingress[0].fqdn : null
}

output "app_url" {
  value = var.app_image_pushed ? "https://${azurerm_container_app.binder[0].ingress[0].fqdn}" : null
}
