variable "name_prefix" {
  type        = string
  description = "Short name prefix (shared with the rest of the rig)."
}

variable "location" {
  type        = string
  description = "Azure region (for this app's user-assigned identity)."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource."
}

variable "resource_group_name" {
  type        = string
  description = "Cloud-app RG (shared with the Chunk-5 substrate)."
}

variable "container_app_environment_id" {
  type        = string
  description = "Shared Container Apps environment ID (from module.app)."
}

variable "environment_default_domain" {
  type        = string
  description = "Shared environment default domain; used to derive the app FQDN for ALLOWED_HOSTS."
}

variable "acr_login_server" {
  type        = string
  description = "Shared ACR login server (from module.app)."
}

variable "acr_id" {
  type        = string
  description = "Shared ACR resource ID — the scope for this app's OWN AcrPull grant."
}

variable "image_tag" {
  type        = string
  description = "Image tag for the first apply only; the CI pipeline owns it afterward (see ignore_changes)."
  default     = "1"
}

variable "image_pushed" {
  type        = bool
  description = "Two-phase gate: create the container app only after its image is in ACR."
  default     = false
}

variable "django_secret_key" {
  type        = string
  description = "DJANGO_SECRET_KEY (TEST-ONLY inline secret until a Key Vault chunk exists)."
  sensitive   = true
}

variable "extra_env" {
  type        = map(string)
  description = "Additional plain (non-secret) env vars for the container — e.g. the LDAP_* duality config, FRONT_DOOR_ID, and the rig-only AUTH_STUB_PERMISSIONS."
  default     = {}
}

variable "unique_suffix" {
  type        = string
  description = "Random suffix (shared with the rig) for the globally-unique SPA storage account name."
}

variable "ldap_bind_password" {
  type        = string
  description = "LDAP service/bind account password, injected as the secret env LDAP_BIND_PASSWORD. Null = omit (on-prem images bind by other means)."
  sensitive   = true
  default     = null
}

variable "cpu" {
  type        = number
  description = "vCPU (Consumption ratio-locks ~2GiB/vCPU on a 0.25 grid)."
  default     = 1.0
}

variable "memory" {
  type        = string
  description = "Memory — the sizing knob; QuickSignals is pandas-heavy."
  default     = "2Gi"
}

variable "min_replicas" {
  type        = number
  description = "1 = warm (interactive). Set 0 for scale-to-zero to stay inside the rig budget."
  default     = 1
}

variable "max_replicas" {
  type        = number
  description = "Upper bound for HTTP-driven scale-out."
  default     = 3
}
