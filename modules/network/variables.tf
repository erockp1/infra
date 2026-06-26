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
  description = "true = create the networking RG; false = reference an existing one (corporate port)."
}

variable "rg_net_name" {
  type        = string
  description = "Networking/shared RG name (holds both VNets, peering, private DNS, NSGs)."
}

variable "cloud_vnet_cidr" {
  type        = string
  description = "Cloud VNet address space."
}

variable "onprem_vnet_cidr" {
  type        = string
  description = "On-prem-sim VNet address space."
}

variable "app_subnet_cidr" {
  type        = string
  description = "Container Apps infra subnet (delegated to Microsoft.App/environments)."
}

variable "dc_subnet_cidr" {
  type        = string
  description = "DC subnet."
}

variable "mgmt_subnet_cidr" {
  type        = string
  description = "Management / jump subnet."
}

variable "vnet_dns_servers" {
  type        = list(string)
  description = "Custom DNS servers on both VNets (point at the DC's reserved static IP). Empty = Azure default DNS."
  default     = []
}

variable "domain_realm" {
  type        = string
  description = "AD realm — also the private DNS zone name."
}
