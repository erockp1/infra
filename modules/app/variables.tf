variable "name_prefix" {
  type        = string
  description = "Short name prefix."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource."
}

variable "create_resource_groups" {
  type        = bool
  description = "true = create the cloud-app RG; false = reference existing (corporate)."
}

variable "rg_app_name" {
  type        = string
  description = "Cloud-app RG (Container Apps env, ACR, Log Analytics)."
}

variable "app_subnet_id" {
  type        = string
  description = "Delegated app subnet ID for the Container Apps environment (VNet integration)."
}

variable "acr_name" {
  type        = string
  description = "Globally-unique ACR name (prefix + random suffix)."
}

variable "acr_sku" {
  type        = string
  description = "ACR SKU."
}

variable "app_image_tag" {
  type        = string
  description = "Tag of the ldap-binder image."
}

variable "app_image_pushed" {
  type        = bool
  description = "Gate the container app: create it only after the image exists in ACR."
  default     = false
}

# --- App runtime config ----------------------------------------------------
variable "dc_fqdn" {
  type        = string
  description = "DC FQDN the app connects by (must match the cert SAN)."
}

variable "base_dn" {
  type        = string
  description = "LDAP base DN."
}

variable "domain_realm" {
  type        = string
  description = "Realm (used to build UPNs)."
}

variable "bind_account_dn" {
  type        = string
  description = "Service-account DN for the /check endpoint."
}

variable "bind_account_password" {
  type        = string
  description = "Service-account password (TEST-ONLY)."
  sensitive   = true
}
