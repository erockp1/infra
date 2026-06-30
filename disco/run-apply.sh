#!/usr/bin/env bash
# =============================================================================
# Permission-discovery harness — apply driver. Runs the SAME root Terraform as
# the rig, but AS THE ZERO-PRIV SP, against an isolated state key (disco.tfstate)
# and an isolated plugin/data dir (.terraform-disco), with the disco tfvars.
#
#   ./disco/run-apply.sh            # plan (default)
#   ./disco/run-apply.sh apply      # apply (-auto-approve)
#
# Each run tees full output to disco/last-apply.log for grant.sh to parse.
# Run from the infra repo root (where backend.tf / variables.tf live).
# =============================================================================
set -euo pipefail

TERRAFORM="${TERRAFORM:-/c/Terraform/terraform.exe}"
command -v "$TERRAFORM" >/dev/null 2>&1 || TERRAFORM="terraform"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT"

ACTION="${1:-plan}"
LOG="$HERE/last-apply.log"

# Auth as the SP (replaces az-CLI/Owner auth that masks missing perms today).
[[ -f "$HERE/sp.env" ]] || { echo "Missing $HERE/sp.env — run ./disco/00-prep.sh first."; exit 1; }
# shellcheck disable=SC1090
source "$HERE/sp.env"

# Isolate from the rig's .terraform/ and state.
export TF_DATA_DIR=".terraform-disco"

BACKEND="$HERE/backend.disco.hcl"
TFVARS="$HERE/disco.tfvars"
[[ -f "$BACKEND" ]] || { echo "Missing $BACKEND — copy from backend.disco.hcl.example."; exit 1; }
[[ -f "$TFVARS" ]]  || { echo "Missing $TFVARS — copy from disco.tfvars.example."; exit 1; }

if [[ ! -d "$TF_DATA_DIR" ]]; then
  echo "Initializing disco backend (key=disco.tfstate)..."
  "$TERRAFORM" init -reconfigure -input=false -backend-config="$BACKEND"
fi

echo "Running terraform $ACTION as SP $ARM_CLIENT_ID ..."
case "$ACTION" in
  plan)  "$TERRAFORM" plan  -input=false -no-color -var-file="$TFVARS" 2>&1 | tee "$LOG" ;;
  apply) "$TERRAFORM" apply -input=false -no-color -auto-approve -var-file="$TFVARS" 2>&1 | tee "$LOG" ;;
  *)     echo "Usage: $0 [plan|apply]"; exit 2 ;;
esac

echo
echo "Output saved to $LOG. If it failed with AuthorizationFailed, run: ./disco/grant.sh"
