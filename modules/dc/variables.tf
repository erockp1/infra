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
  description = "true = create the on-prem-sim RG; false = reference existing (corporate)."
}

variable "rg_onprem_name" {
  type        = string
  description = "On-prem-sim RG (DC VM, disks, jump)."
}

variable "rg_net_name" {
  type        = string
  description = "Networking RG where the NSGs live (rules are attached there)."
}

variable "dc_subnet_id" {
  type        = string
  description = "DC subnet ID."
}

variable "mgmt_subnet_id" {
  type        = string
  description = "Management/jump subnet ID."
}

variable "dc_nsg_name" {
  type        = string
  description = "Name of the DC NSG (shell from Chunk 1) to attach rules to."
}

variable "mgmt_nsg_name" {
  type        = string
  description = "Name of the mgmt NSG (shell from Chunk 1) to attach rules to."
}

variable "mgmt_subnet_cidr" {
  type        = string
  description = "Mgmt subnet CIDR — source allowed to SSH the DC."
}

variable "app_subnet_cidr" {
  type        = string
  description = "Cloud app subnet CIDR — the only cloud source allowed to reach the DC (636 + 53)."
}

variable "dc_static_ip" {
  type        = string
  description = "Static private IP for the DC NIC (the reserved one)."
}

variable "dc_vm_size" {
  type        = string
  description = "DC VM size."
}

variable "jump_vm_size" {
  type        = string
  description = "Jump VM size."
}

variable "dc_data_disk_gb" {
  type        = number
  description = "Data disk size (GB)."
}

variable "dc_image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  description = "OS image for DC + jump."
}

variable "admin_username" {
  type        = string
  description = "Admin username on the VMs."
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for VM access."
  validation {
    condition     = length(trimspace(var.ssh_public_key)) > 0
    error_message = "ssh_public_key must be set before deploying the DC (Chunk 2)."
  }
}

variable "home_ip_cidr" {
  type        = string
  description = "Home public IP /32 — the only source allowed to SSH the jump VM."
  validation {
    condition     = can(cidrhost(var.home_ip_cidr, 0))
    error_message = "home_ip_cidr must be a valid CIDR (e.g. 203.0.113.7/32)."
  }
}

variable "dc_hostname" {
  type        = string
  description = "DC short hostname."
}

variable "domain_realm" {
  type        = string
  description = "Realm — used to build the DC FQDN for cloud-init."
}

# --- Chunk 3: Samba-AD provisioning inputs ---------------------------------
variable "domain_netbios" {
  type        = string
  description = "NetBIOS/short domain name."
}

variable "base_dn" {
  type        = string
  description = "LDAP base DN matching the realm."
}

variable "ou_name" {
  type        = string
  description = "OU created for the test identities."
}

variable "dns_forwarder" {
  type        = string
  description = "Upstream DNS forwarder for Samba (external resolution)."
}

variable "bind_account_cn" {
  type        = string
  description = "CN/sAMAccountName of the bind service account."
}

variable "domain_admin_password" {
  type        = string
  description = "Domain Administrator password set at provision (TEST-ONLY)."
  sensitive   = true
}

variable "bind_account_password" {
  type        = string
  description = "Bind service-account password (TEST-ONLY)."
  sensitive   = true
}

variable "test_users" {
  type        = map(object({ password = string }))
  description = "Test users keyed by sAMAccountName (TEST-ONLY)."
  sensitive   = true
}
