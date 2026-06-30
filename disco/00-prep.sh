#!/usr/bin/env bash
# =============================================================================
# Permission-discovery harness — one-time prep. RUN AS OWNER (or User Access
# Administrator + RG creator). Idempotent-ish: safe to re-run; it will reuse an
# existing SP app registration by display name.
#
# Creates the ZERO-PRIVILEGE service principal the harness runs as, the two
# sandbox RGs, and the BASELINE grants only:
#   - Reader on rg-disco-net and rg-disco-app  (so data-source RG reads resolve;
#     without read access Azure 404s and it looks like ResourceGroupNotFound)
#   - Storage Blob Data Contributor on the tfstate container (AAD-auth backend)
# Everything else is discovered by the apply -> deny -> grant loop (grant.sh).
#
# Writes disco/sp.env (git-ignored) with ARM_* creds for run-apply.sh.
# =============================================================================
set -euo pipefail

AZ="${AZ:-az}"
SP_NAME="${SP_NAME:-disco-harness-sp}"
LOCATION="${LOCATION:-eastus}"
RG_NET="${RG_NET:-rg-disco-net}"
RG_APP="${RG_APP:-rg-disco-app}"

# tfstate backend (same account as the rig; different key). Override if needed.
TFSTATE_RG="${TFSTATE_RG:-rg-altop-tfstate}"
TFSTATE_ACCOUNT="${TFSTATE_ACCOUNT:?set TFSTATE_ACCOUNT to the state storage account name (e.g. altoptfn95qtf)}"
TFSTATE_CONTAINER="${TFSTATE_CONTAINER:-tfstate}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SP_ENV="${HERE}/sp.env"

SUB_ID="$("$AZ" account show --query id -o tsv)"
TENANT_ID="$("$AZ" account show --query tenantId -o tsv)"
echo "Subscription: $SUB_ID   Tenant: $TENANT_ID"

# --- 1. Zero-privilege SP (app + sp + secret; NO role assignment) -----------
# Built explicitly rather than `create-for-rbac` so NO role is ever attached,
# across all az CLI versions.
APP_ID="$("$AZ" ad app list --display-name "$SP_NAME" --query '[0].appId' -o tsv)"
if [[ -z "$APP_ID" || "$APP_ID" == "null" ]]; then
  echo "Creating app registration '$SP_NAME'..."
  APP_ID="$("$AZ" ad app create --display-name "$SP_NAME" --query appId -o tsv)"
fi
if [[ -z "$("$AZ" ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || true)" ]]; then
  echo "Creating service principal for $APP_ID..."
  "$AZ" ad sp create --id "$APP_ID" >/dev/null
fi
echo "Resetting client secret..."
SECRET="$("$AZ" ad app credential reset --id "$APP_ID" --query password -o tsv)"
SP_OID="$("$AZ" ad sp show --id "$APP_ID" --query id -o tsv)"

# Guard: prove the SP truly has zero role assignments before we start.
EXISTING="$("$AZ" role assignment list --assignee "$APP_ID" --all --query 'length(@)' -o tsv || echo 0)"
echo "SP existing role assignments (expect 0 before baseline): $EXISTING"

# --- 2. Pre-create exactly the two sandbox RGs the first pass touches --------
# rg-disco-onprem is NOT created: module.network puts the on-prem-sim VNet in
# rg-net, and the only rg-onprem consumer (module.dc) is gated off.
for RG in "$RG_NET" "$RG_APP"; do
  echo "Ensuring resource group $RG..."
  "$AZ" group create -n "$RG" -l "$LOCATION" \
    --tags owner=erockp1 purpose=poc0 env=disco managed_by=harness >/dev/null
done

# --- 3. Baseline grants (the only ones not discovered by the loop) ----------
RG_NET_SCOPE="/subscriptions/${SUB_ID}/resourceGroups/${RG_NET}"
RG_APP_SCOPE="/subscriptions/${SUB_ID}/resourceGroups/${RG_APP}"
TFSTATE_SCOPE="/subscriptions/${SUB_ID}/resourceGroups/${TFSTATE_RG}/providers/Microsoft.Storage/storageAccounts/${TFSTATE_ACCOUNT}/blobServices/default/containers/${TFSTATE_CONTAINER}"

grant() { # role  scope
  echo "  grant '$1' @ $2"
  "$AZ" role assignment create --assignee "$APP_ID" --role "$1" --scope "$2" >/dev/null 2>&1 \
    || echo "    (already present or pending)"
}
echo "Baseline grants:"
grant "Reader" "$RG_NET_SCOPE"
grant "Reader" "$RG_APP_SCOPE"
grant "Storage Blob Data Contributor" "$TFSTATE_SCOPE"

# --- 4. Emit ARM_* creds for run-apply.sh -----------------------------------
cat > "$SP_ENV" <<EOF
# Git-ignored. Sourced by run-apply.sh. Zero-priv harness SP — TEST sandbox only.
export ARM_CLIENT_ID="${APP_ID}"
export ARM_CLIENT_SECRET="${SECRET}"
export ARM_TENANT_ID="${TENANT_ID}"
export ARM_SUBSCRIPTION_ID="${SUB_ID}"
export DISCO_SP_OBJECT_ID="${SP_OID}"
EOF
echo "Wrote $SP_ENV"
echo
echo "Done. Baseline set. Now run:  ./disco/run-apply.sh plan"
echo "Then feed denials to:        ./disco/grant.sh"
