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

variable "spa_web_host" {
  type        = string
  description = "Static-website host of the SPA storage ($web) — the default (/*) origin."
}

variable "aca_fqdn" {
  type        = string
  description = "ACA ingress FQDN — the API origin (the /login|/quicksignal|... routes)."
}

variable "api_route_patterns" {
  type        = list(string)
  description = "Path patterns routed to the ACA (API) origin; everything else (/*) goes to the SPA."
  default     = ["/login/*", "/quicksignal/*", "/healthz", "/static/*", "/admin/*"]
}

variable "waf_block_sentinel" {
  type        = string
  description = "A request-URI substring the one custom WAF rule blocks — proves 'WAF in the path' (curl ?<sentinel> -> 403)."
  default     = "wafblocktest"
}
