output "front_door_id" {
  description = "The profile resource_guid — the value Front Door sends as X-Azure-FDID (shared across all app endpoints). Feed it to each app's FRONT_DOOR_ID so the origin-lock middleware accepts FD traffic and 403s direct hits."
  value       = azurerm_cdn_frontdoor_profile.this.resource_guid
}

output "endpoints" {
  description = "Per-app public Front Door hostname."
  value       = { for k, ep in azurerm_cdn_frontdoor_endpoint.this : k => ep.host_name }
}

output "endpoint_urls" {
  description = "Per-app public Front Door URL."
  value       = { for k, ep in azurerm_cdn_frontdoor_endpoint.this : k => "https://${ep.host_name}" }
}
