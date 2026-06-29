# ===========================================================================
# Variable surface for the whole rig. The corporate port is a different
# terraform.tfvars over these — never an edit inside a module.
# Grouped by the chunk that first consumes each variable.
# ===========================================================================

# --- Identity / subscription (Chunk 0) -------------------------------------
variable "subscription_id" {
  type        = string
  description = "Azure subscription ID (GUID). From `az account show` .id."
}

variable "tenant_id" {
  type        = string
  description = "Azure tenant ID (GUID). From `az account show` .tenantId."
}

# --- Naming & tags (cross-cutting) -----------------------------------------
variable "name_prefix" {
  type        = string
  description = "Short prefix seeding all names. 2-9 lowercase alphanumerics starting with a letter."
  default     = "altop"
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,8}$", var.name_prefix))
    error_message = "name_prefix must be 2-9 lowercase alphanumeric chars starting with a letter."
  }
}

variable "location" {
  type        = string
  description = "Azure region for all resources."
  default     = "eastus"
}

variable "tags" {
  type        = map(string)
  description = "Extra tags merged onto the base tag set."
  default     = {}
}

variable "owner" {
  type        = string
  description = "owner tag value."
  default     = "erockp1"
}

variable "env" {
  type        = string
  description = "env tag value."
  default     = "rig"
}

variable "delete_after" {
  type        = string
  description = "delete_after tag (YYYY-MM-DD) — a teardown nudge against a forgotten VM."
  default     = ""
}

# --- Resource groups (cross-cutting; the key porting affordance) -----------
variable "create_resource_groups" {
  type        = bool
  description = "true = create the RGs (this rig). false = reference existing RGs by name (corporate, where you get RGs with Contributor and no create rights)."
  default     = true
}

variable "rg_net_name" {
  type        = string
  description = "Networking/shared RG name. Null -> rg-<prefix>-net."
  default     = null
}

variable "rg_onprem_name" {
  type        = string
  description = "On-prem-sim RG name (DC VM, disks, jump). Null -> rg-<prefix>-onprem."
  default     = null
}

variable "rg_app_name" {
  type        = string
  description = "Cloud-app RG name (Container Apps env, ACR, Log Analytics). Null -> rg-<prefix>-app."
  default     = null
}

# --- Budget / cost guardrail (Chunk 0) -------------------------------------
variable "budget_alert_email" {
  type        = string
  description = "Email for the cost-alert notifications."
  default     = "erockp1@gmail.com"
}

variable "budget_amount" {
  type        = number
  description = "Monthly budget amount (USD) for the subscription alert."
  default     = 5
}

variable "budget_start_date" {
  type        = string
  description = "Budget start (RFC3339, first of a month). Must not be in the past beyond the allowed window."
  default     = "2026-06-01T00:00:00Z"
}

# --- Networking / address space (Chunk 1) ----------------------------------
variable "cloud_vnet_cidr" {
  type        = string
  description = "Cloud VNet address space."
  default     = "10.50.0.0/16"
}

variable "onprem_vnet_cidr" {
  type        = string
  description = "On-prem-sim VNet address space (disjoint from cloud, and off common corporate ranges)."
  default     = "10.60.0.0/16"
}

variable "app_subnet_cidr" {
  type        = string
  description = "Container Apps infra subnet. /27 min for a workload-profiles env, /23 for consumption-only."
  default     = "10.50.0.0/27"
}

variable "dc_subnet_cidr" {
  type        = string
  description = "DC subnet (on-prem VNet)."
  default     = "10.60.1.0/24"
}

variable "mgmt_subnet_cidr" {
  type        = string
  description = "Management / jump subnet (on-prem VNet)."
  default     = "10.60.2.0/24"
}

variable "dc_static_ip" {
  type        = string
  description = "Reserved static private IP for the DC (>= .4 in dc_subnet). VNet DNS points here."
  default     = "10.60.1.10"
}

variable "aca_env_type" {
  type        = string
  description = "Container Apps environment type."
  default     = "workload_profiles"
  validation {
    condition     = contains(["workload_profiles", "consumption_only"], var.aca_env_type)
    error_message = "aca_env_type must be 'workload_profiles' or 'consumption_only'."
  }
}

# --- Domain / realm (Chunks 1,3,4,5) ---------------------------------------
variable "domain_realm" {
  type        = string
  description = "AD realm / DNS domain (clearly-test; avoid bare .local). Drives DC FQDN, cert SAN, base DN."
  default     = "poc0.lab"
}

variable "domain_netbios" {
  type        = string
  description = "NetBIOS / short domain name."
  default     = "POC0"
}

variable "base_dn" {
  type        = string
  description = "LDAP base DN matching the realm."
  default     = "DC=poc0,DC=lab"
}

variable "dc_hostname" {
  type        = string
  description = "DC short hostname. dc_fqdn = <hostname>.<realm>."
  default     = "dc01"
}

variable "ou_name" {
  type        = string
  description = "OU created to hold the test identities."
  default     = "POC0"
}

variable "bind_account_cn" {
  type        = string
  description = "CN of the bind service account."
  default     = "svc-bind"
}

# --- Sensitive identities (Chunks 3,5) — keep in git-ignored tfvars only ----
variable "domain_admin_password" {
  type        = string
  description = "Domain Administrator password set at provision (TEST-ONLY; never a real credential)."
  sensitive   = true
  default     = null
}

variable "dns_forwarder" {
  type        = string
  description = "Upstream DNS forwarder for Samba's internal DNS (Azure-provided DNS by default)."
  default     = "168.63.129.16"
}

variable "bind_account_password" {
  type        = string
  description = "Bind service-account password (TEST-ONLY; never a real credential)."
  sensitive   = true
  default     = null
}

variable "test_users" {
  type        = map(object({ password = string }))
  description = "Test users keyed by sAMAccountName (TEST-ONLY passwords). e.g. { alice = { password = \"...\" } }"
  sensitive   = true
  default     = {}
}

# --- DC / jump VMs (Chunk 2) -----------------------------------------------
variable "dc_vm_size" {
  type        = string
  description = "DC VM size (small B-series)."
  default     = "Standard_B2s"
}

variable "jump_vm_size" {
  type        = string
  description = "Jump VM size."
  default     = "Standard_B1s"
}

variable "dc_data_disk_gb" {
  type        = number
  description = "Data disk size for /var/lib/samba (caching None)."
  default     = 16
}

variable "dc_image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  description = "DC/jump OS image. Default Ubuntu 22.04 LTS gen2 (best-trodden for Samba-AD-DC)."
  default = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for the DC + jump VMs (key auth only)."
  default     = ""
}

variable "home_ip_cidr" {
  type        = string
  description = "Your home public IP as /32 — the only source allowed to SSH the jump VM."
  default     = ""
}

variable "admin_username" {
  type        = string
  description = "Admin username on the Linux VMs."
  default     = "azadmin"
}

variable "enable_jit" {
  type        = bool
  description = "Seam for the corporate port: JIT VM access instead of the jump VM. Not free-tier (Defender for Servers); leave false for the rig."
  default     = false
}

# --- App / registry (Chunk 5) ----------------------------------------------
variable "acr_sku" {
  type        = string
  description = "Azure Container Registry SKU."
  default     = "Basic"
}

variable "app_image_tag" {
  type        = string
  description = "Tag of the ldap-binder image in ACR."
  default     = "1"
}

variable "app_image_pushed" {
  type        = bool
  description = "Two-phase apply gate: create the container app only after the image is pushed to ACR."
  default     = false
}

# --- Chunk gates (additive apply per chunk) --------------------------------
variable "deploy_dc" {
  type        = bool
  description = "Gate Chunks 2-4 (DC VM, Samba-AD, LDAPS)."
  default     = false
}

variable "deploy_app" {
  type        = bool
  description = "Gate Chunk 5 (Container Apps env + bind app)."
  default     = false
}

# --- QuickSignals app (Chunk 6) — requires deploy_app=true -------------------
variable "deploy_quicksignals" {
  type        = bool
  description = "Gate Chunk 6 (QuickSignals container app + its own identity). Needs deploy_app=true."
  default     = false
}

variable "quicksignals_image_pushed" {
  type        = bool
  description = "Two-phase gate: create the QuickSignals app only after its image is pushed to ACR."
  default     = false
}

variable "quicksignals_image_tag" {
  type        = string
  description = "Tag of the quicksignals image in ACR (first apply only; CI owns it after via ignore_changes)."
  default     = "1"
}

variable "quicksignals_django_secret_key" {
  type        = string
  description = "DJANGO_SECRET_KEY for QuickSignals (TEST-ONLY inline secret; keep in git-ignored tfvars only)."
  sensitive   = true
  default     = null
}
