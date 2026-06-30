# Discovered roles — the running ledger

> The deliverable. Each loop iteration adds a row. When `run-apply.sh` finally
> shows a clean plan/apply, the **union of the `Action` column** (plus the
> baseline and the documented-not-surfaced sections) is the minimal RBAC the
> corporate deploy principal needs — assemble it into the custom role JSON at the
> bottom.

## Baseline grants (set by `00-prep.sh`, not loop-discovered)

These are required just to run Terraform as a non-Owner; they don't surface as
denials because they're prerequisites to getting that far.

| Grant | Scope | Why |
|---|---|---|
| `Reader` | `rg-disco-net` | Read the RG via `data.azurerm_resource_group.net` (else 404 looks like not-found) |
| `Reader` | `rg-disco-app` | Read the RG via `data.azurerm_resource_group.app` |
| `Storage Blob Data Contributor` | tfstate container | Read/write `disco.tfstate` (AAD-auth backend; mgmt-plane Owner does NOT grant blob data plane) |

## Loop-discovered (appended by `grant.sh`)

Each row is one denied control-plane write the harness hit. `Action` is the
precise thing for the custom role; `Unblock role` is just the built-in granted to
proceed.

| Action | Unblock role | Scope | Status |
|---|---|---|---|
<!-- grant.sh appends rows below this line -->

### Anticipated headline finding (expected on the first non-baseline iteration)

- **`Microsoft.Authorization/roleAssignments/write`** at the **ACR** scope (in
  `rg-disco-app`). Both `modules/app` and `modules/django_app` self-create an
  `AcrPull` assignment for their managed identity — and neither is gated by
  `image_pushed`, so this surfaces even with no image. Corporate security commonly
  **withholds** this action. **Flag for the security team**; the likely design
  change is to pre-create the identities + AcrPull assignments out-of-band and have
  Terraform reference them. Unblock role for the loop: `Role Based Access Control
  Administrator` (or `User Access Administrator`).

## Documented-not-surfaced (gated off via `manage_subscription_singletons=false`)

These are **subscription-scoped** and already done in this sub, so the harness
can't make them fail. Documented from provider docs; they belong in the corporate
ask as **subscription-scoped** grants (or are handled by corporate pre-registering
the RPs / owning the budget):

| Action | Scope | Source |
|---|---|---|
| `Microsoft.Network/register/action` | subscription | `providers.tf` |
| `Microsoft.Compute/register/action` | subscription | `providers.tf` |
| `Microsoft.App/register/action` | subscription | `providers.tf` |
| `Microsoft.ContainerRegistry/register/action` | subscription | `providers.tf` |
| `Microsoft.OperationalInsights/register/action` | subscription | `providers.tf` |
| `Microsoft.ManagedIdentity/register/action` | subscription | `providers.tf` |
| `Microsoft.Consumption/register/action` | subscription | `providers.tf` |
| `Microsoft.Consumption/budgets/write` | subscription | `budget.tf` |

> Corporate almost always pre-registers RPs and **denies** the register action — in
> which case the corporate apply runs with `manage_subscription_singletons=false`
> too, and these drop out of scope entirely (see `CORPORATE_PORT.md`).

## Custom role JSON (assemble when the loop is clean)

```jsonc
{
  "Name": "Cloud Port Deploy (minimal)",
  "IsCustom": true,
  "Description": "Minimal control-plane actions to deploy the Cloud Port app surface into pre-provisioned RGs.",
  "Actions": [
    // <- paste the union of the Action column here, e.g.:
    // "Microsoft.Network/virtualNetworks/*",
    // "Microsoft.OperationalInsights/workspaces/*",
    // "Microsoft.ContainerRegistry/registries/*",
    // "Microsoft.App/managedEnvironments/*",
    // "Microsoft.App/containerApps/*",
    // "Microsoft.ManagedIdentity/userAssignedIdentities/*",
    // "Microsoft.Storage/storageAccounts/*",
    // "Microsoft.Authorization/roleAssignments/write"   // <- the one to negotiate
  ],
  "AssignableScopes": [ "/subscriptions/<sub-id>/resourceGroups/<app-rg>" ]
}
```
