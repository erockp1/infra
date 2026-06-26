variable "subscription_id" {
  type        = string
  description = "Azure subscription ID (GUID)."
}

variable "tenant_id" {
  type        = string
  description = "Azure tenant ID (GUID)."
}

variable "name_prefix" {
  type        = string
  description = "Short prefix that seeds all globally-unique names. 2-9 lowercase alphanumerics, starting with a letter."
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,8}$", var.name_prefix))
    error_message = "name_prefix must be 2-9 lowercase alphanumeric chars starting with a letter (charset constraint of storage-account names)."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the state resource group + storage account."
  default     = "eastus"
}

variable "tags" {
  type        = map(string)
  description = "Extra tags merged onto the bootstrap resources."
  default     = {}
}
