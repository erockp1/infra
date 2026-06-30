variable "name_prefix" {
  type        = string
  description = "Short name prefix (shared with the rest of the rig)."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource."
}

variable "resource_group_name" {
  type        = string
  description = "RG for the Front Door profile + WAF (the shared app RG)."
}

variable "apps" {
  type = map(object({
    spa_web_host       = string       # static-website host ($web) -> the /* (SPA) origin
    aca_fqdn           = string       # ACA ingress FQDN -> the API origin
    api_route_patterns = list(string) # paths routed to the API origin (everything else -> SPA)
  }))
  description = "Per-app edge config, keyed by app name. Each app gets its OWN Front Door endpoint (hostname) under the shared profile + WAF."
}

variable "waf_block_sentinel" {
  type        = string
  description = "A request-URI substring the one custom WAF rule blocks — proves 'WAF in the path' (curl ?<sentinel> -> 403)."
  default     = "wafblocktest"
}
