# Running this Terraform in the corporate account

How to take the proven POC 0 rig from the personal/scratch account to the corporate
subscription. The model is **a different `terraform.tfvars` plus two structural swaps** —
not a rewrite. The bind code, cert-trust handling, DNS path, and NSG rules are unchanged.

See also: `POC0_RESULTS.md` (validation + RBAC manifest), `CLAUDE_POC0_WORK` (original
spec), and `corporate.tfvars.example` (a worked starting tfvars).

---

## TL;DR

1. Get RGs provisioned to you (you won't have create rights) → set `create_resource_groups = false`.
2. Copy `corporate.tfvars.example` → `terraform.tfvars`, fill in corporate values.
3. **Don't build a DC** (`deploy_dc = false`) — point the app at the real `ALTOP-DC01`.
4. Replace the rig peering with corporate's real hybrid link (structural edit, below).
5. Move secrets + CA trust to **Key Vault** (structural edit, below).
6. `terraform init` against a corporate state backend → `plan` → expect it to **fail loudly
   on missing RBAC** (that's the point — the failures are your permission manifest).

---

## What changes — values only (tfvars swaps)

| Variable | Corporate value |
|---|---|
| `subscription_id`, `tenant_id` | corporate IDs |
| `location` | corporate region |
| `name_prefix` | corporate naming convention (drives ACR/storage; expect Policy to enforce a CAF-style name) |
| `create_resource_groups` | **`false`** |
| `rg_net_name`, `rg_onprem_name`, `rg_app_name` | the RGs you're handed (referenced as data sources) |
| `cloud_vnet_cidr`, `app_subnet_cidr`, … | corporate-assigned address space |
| `tags` | corporate Policy-mandated tags |
| `domain_realm`, `base_dn`, `dc_hostname` | the **real** AD realm → derives `dc_fqdn` = real `ALTOP-DC01` FQDN |
| `bind_account_cn`, `ou_name` | the real service-account location (composes `bind_account_dn`) |
| CA trust | corporate internal CA (not the rig CA) — see Key Vault below |

The `create_resource_groups` flag is the single most important porting affordance: each RG
flips between `azurerm_resource_group` (rig) and a `data` source (corporate). Without it,
the first corporate `apply` fails on RG creation.

---

## What changes — structure (the two swaps + secrets)

These touch module wiring, not just values. Each is small and scoped.

### 1. Peering → real hybrid link
The rig joins cloud and on-prem with `azurerm_virtual_network_peering` (in
`modules/network`). In corporate, the link is a real VPN/ExpressRoute owned by corporate
networking. **Edit:** remove the on-prem VNet + peering from `modules/network` and instead
reference corporate's existing connectivity (their hub VNet / link is an input, often just
routing you already have). The cloud VNet + app subnet stay.

### 2. Samba stand-in DC → real `ALTOP-DC01`
Set **`deploy_dc = false`**. This drops the whole `modules/dc` build (VM, data disk, jump,
Samba provisioning, the rig's self-signed CA). You **create no DC** — the app points at the
real one via `dc_fqdn` (`<dc_hostname>.<domain_realm>`). The DC-subnet NSG rules (636/53
inbound) become rules corporate applies on their side of the link; keep them as the
declared intent / manifest of what the cloud needs to reach.

### 3. Secrets + CA trust → Key Vault
The rig keeps the bind password in `terraform.tfvars` and bakes the CA into the image — both
**test-only**. In corporate:
- Add `azurerm_key_vault` + `azurerm_key_vault_secret` (or reference an existing vault).
- Change the `azurerm_container_app` `secret` block in `modules/app/main.tf` from a literal
  `value` to a **Key Vault reference** (`key_vault_secret_id` + the app's managed identity
  granted `get` on the secret).
- Source the **CA trust** from corporate's internal CA — either baked from their CA PEM at
  image build, or mounted from Key Vault — instead of the rig CA output.

---

## RBAC manifest — permissions to request before the corporate apply

The rig surfaced these by hitting them; declare them as explicit resources so the corporate
`apply` fails loudly on whichever is missing:

- **`AcrPull`** for the app's user-assigned identity on the corporate ACR (managed-identity image pull).
- **`Storage Blob Data Contributor`** on the Terraform state storage account for whoever runs
  apply (Owner/Contributor at the management plane does NOT grant blob data-plane access).
- **Resource-provider registration** (`Microsoft.App`, `.ContainerRegistry`,
  `.OperationalInsights`, `.Network`, `.ManagedIdentity`) — corporate often pre-registers and
  **denies** the registration action; if so, drop the `azurerm_resource_provider_registration`
  resources or make them data-only.
- **Key Vault** access for the app identity (`get` on the bind secret) + whoever manages the vault.
- Network: the inbound 636/53 path to the DC and the egress over the link (corporate networking grants/owns).

Treat each `apply` failure as a line item for the corporate security conversation, not a blocker to debug around.

---

## Known revisit items (rig shortcuts that need attention in corporate)

- **`bind_account_dn` is derived** in `locals.tf` as `CN=<cn>,OU=<ou>,<base_dn>`. If the real
  service account doesn't follow that exact RDN shape, add a direct `bind_account_dn` variable
  and override it.
- **ACA env type**: the rig uses a workload-profiles env + Consumption profile on a `/27`.
  Confirm corporate's preferred env type/subnet sizing and Policy constraints at apply time.
- **Image registry/build**: the rig built locally (`docker build --platform linux/amd64`) +
  pushed because ACR Tasks were blocked on the scratch sub. Corporate may allow `az acr build`
  or require a CI pipeline — wire to whatever their CI/CD mandates.
- **VM sizes** (only relevant if you ever build a test DC in corporate): the rig's
  `Standard_D2als_v7` was forced by scratch-account SKU/quota limits; pick a corporate-approved size.

---

## Apply procedure in corporate

```sh
# 1. State backend: a corporate storage account + container you have data-plane access to.
terraform init -backend-config=backend.hcl

# 2. Plan with the corporate tfvars (expect RBAC/Policy failures — capture them as the manifest).
terraform plan -var-file=terraform.tfvars

# 3. Build + push the app image to the corporate ACR (per their CI/CD), then:
terraform apply -var-file=terraform.tfvars
```
