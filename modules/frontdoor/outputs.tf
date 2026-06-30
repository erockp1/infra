output "endpoint_host" {
  description = "Public Front Door hostname (the single front door users hit)."
  value       = azurerm_cdn_frontdoor_endpoint.this.host_name
}

output "endpoint_url" {
  value = "https://${azurerm_cdn_frontdoor_endpoint.this.host_name}"
}

output "front_door_id" {
  description = "The profile resource_guid — the value Front Door sends as X-Azure-FDID. Feed this to the app's FRONT_DOOR_ID so the origin-lock middleware accepts FD traffic and 403s direct hits."
  value       = azurerm_cdn_frontdoor_profile.this.resource_guid
}
