# Permission-discovery harness (`disco/`)

Discovers the **minimal RBAC** the corporate deploy principal needs, by running the
*same* root Terraform as a **zero-privilege service principal** in a contained
sandbox and letting each `AuthorizationFailed` name the action+scope it needs.

Design rationale: `../PERMISSION_DISCOVERY_HARNESS.md`. Corporate framing:
`../CORPORATE_PORT.md`.

## How it stays out of the rig's way

- **Separate state key** `disco.tfstate` (not the rig's `poc0.tfstate`).
- **Separate data dir** `TF_DATA_DIR=.terraform-disco` (run-apply.sh sets it).
- **Separate sandbox RGs** `rg-disco-net` / `rg-disco-app` via `name_prefix=disco`.
- **SP auth** (`ARM_*`) replaces your Owner/CLI login — that login is exactly what
  masks the missing perms today.
- **Subscription singletons gated off** (`manage_subscription_singletons=false`):
  the RP registrations + budget no-op in this sub, so they can't surface perms.

The shared root config change that makes this possible is zero-churn on the rig:
the `count` + `moved` blocks on the RP registrations (`../providers.tf`) and budget
(`../budget.tf`) — verified by a `No changes` rig plan.

## First-pass scope → exactly two RGs

`deploy_app=true` + `deploy_quicksignals=true`, both `*_image_pushed=false`,
everything else off. Resources land in only:

- **rg-disco-net** — VNets, subnets, peerings, private DNS zone+links, NSGs.
- **rg-disco-app** — Log Analytics, ACR, identities, **both AcrPull assignments**,
  ACA env. (Container apps stay `count=0` — no image needed.)

`rg-disco-onprem` is **not** used (DC is gated off). `00-prep.sh` pre-creates the
two RGs and grants the SP `Reader` on each, so the only loop failures are
`AuthorizationFailed`, never `ResourceGroupNotFound`.

## The loop

```sh
# 0. ONE TIME, AS OWNER: zero-priv SP + the two RGs + baseline grants.
TFSTATE_ACCOUNT=altoptfn95qtf ./disco/00-prep.sh

# Copy the two templates and fill in sub/tenant + state account:
cp disco/backend.disco.hcl.example disco/backend.disco.hcl   # set storage_account_name
cp disco/disco.tfvars.example      disco/disco.tfvars        # set subscription_id / tenant_id

# 1..N. The apply -> deny -> grant cycle:
./disco/run-apply.sh plan        # plan as the SP -> AuthorizationFailed(s) in disco/last-apply.log
./disco/grant.sh                 # dry-run: show the denials + suggested az commands
./disco/grant.sh --apply         # grant the suggested built-in roles; appends to discovered-roles.md
# repeat run-apply.sh plan -> grant.sh --apply until:
./disco/run-apply.sh plan        # -> "No changes" / clean. Done.

# Optional: prove it really applies, not just plans.
./disco/run-apply.sh apply
```

Then, to widen coverage, flip gates in `disco.tfvars` and repeat:
`deploy_dc=true` (adds the DC/VM/network surface, needs `rg-disco-onprem` —
pre-create it + Reader first), then `deploy_frontdoor=true`, then
`deploy_baldaydashboard=true` (should add ~nothing new — same module as quicksignals).

To exercise the container-app *write* surface too, push an image to the disco ACR
and set `*_image_pushed=true` for a final pass.

## Deliverable

`discovered-roles.md` — the running ledger. When the plan is clean, the union of its
`Action` column (+ the baseline + the documented subscription singletons) is the
minimal role; assemble the custom-role JSON at the bottom of that file. Flag
`Microsoft.Authorization/roleAssignments/write` separately — it's the grant
corporate security is most likely to withhold.

## Teardown

```sh
TF_DATA_DIR=.terraform-disco /c/Terraform/terraform.exe destroy -var-file=disco/disco.tfvars
az group delete -n rg-disco-app -y; az group delete -n rg-disco-net -y
az ad sp delete --id "$(az ad app list --display-name disco-harness-sp --query '[0].appId' -o tsv)"
```

## Files

| File | Committed? | What |
|---|---|---|
| `backend.disco.hcl.example` | yes | template → `backend.disco.hcl` (git-ignored) |
| `disco.tfvars.example` | yes | template → `disco.tfvars` (git-ignored) |
| `00-prep.sh` | yes | Owner-run: SP + RGs + baseline grants |
| `run-apply.sh` | yes | plan/apply as the SP (isolated state + data dir) |
| `grant.sh` | yes | parse denials → suggest/grant roles → update ledger |
| `discovered-roles.md` | yes | the running deliverable |
| `backend.disco.hcl`, `disco.tfvars`, `sp.env`, `last-apply.log` | **no** | real/secret, git-ignored |
