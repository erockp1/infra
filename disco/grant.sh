#!/usr/bin/env bash
# =============================================================================
# Permission-discovery harness — denial parser + granter. Reads the last apply
# log, extracts every distinct "does not have authorization to perform action
# 'X' over scope 'Y'", and for each:
#   - prints the exact action + scope (this is what becomes the custom role),
#   - suggests the least-broad built-in role to UNBLOCK the loop,
#   - (with --apply) creates that role assignment for the harness SP,
#   - appends a row to discovered-roles.md.
#
#   ./disco/grant.sh            # dry-run: show denials + suggested az commands
#   ./disco/grant.sh --apply    # actually grant the suggested roles
#
# Granularity is per-provider-area (a built-in role per provider) to keep cycles
# low; the LEDGER keeps the exact actions, which are the real deliverable.
# =============================================================================
set -euo pipefail

AZ="${AZ:-az}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$HERE/last-apply.log"
LEDGER="$HERE/discovered-roles.md"
APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

[[ -f "$LOG" ]] || { echo "No $LOG — run ./disco/run-apply.sh first."; exit 1; }
[[ -f "$HERE/sp.env" ]] && source "$HERE/sp.env"
APP_ID="${ARM_CLIENT_ID:-<harness-sp-appId>}"

# Map a denied action to the least-broad built-in role that unblocks it. The
# ledger keeps the precise action; this is only to proceed to the next denial.
suggest_role() {
  case "$1" in
    Microsoft.Network/*)                       echo "Network Contributor" ;;
    Microsoft.Storage/*)                       echo "Storage Account Contributor" ;;
    Microsoft.OperationalInsights/*)           echo "Log Analytics Contributor" ;;
    Microsoft.ManagedIdentity/*)               echo "Managed Identity Contributor" ;;
    Microsoft.Authorization/roleAssignments/*) echo "Role Based Access Control Administrator" ;;
    Microsoft.App/*|Microsoft.ContainerRegistry/*) echo "Contributor" ;;  # no dedicated built-in; refine in ledger
    Microsoft.Resources/*)                     echo "Reader" ;;
    *)                                         echo "Contributor" ;;       # fallback — REFINE
  esac
}

# Extract distinct (action, scope) pairs from the Azure error text.
mapfile -t PAIRS < <(grep -oE "perform action '[^']+' over scope '[^']+'" "$LOG" \
  | sed -E "s/perform action '([^']+)' over scope '([^']+)'/\1\t\2/" | sort -u)

if [[ "${#PAIRS[@]}" -eq 0 ]]; then
  if grep -qiE 'No changes|Apply complete|Plan: 0 to add' "$LOG"; then
    echo "No AuthorizationFailed in $LOG — clean. The accumulated grants are the answer; see $LEDGER."
  else
    echo "No AuthorizationFailed found, but the run wasn't clean either. Inspect $LOG (could be a non-RBAC error)."
  fi
  exit 0
fi

echo "Found ${#PAIRS[@]} distinct denial(s):"
echo
for pair in "${PAIRS[@]}"; do
  ACTION="${pair%%$'\t'*}"
  SCOPE="${pair#*$'\t'}"
  ROLE="$(suggest_role "$ACTION")"
  SHORT_SCOPE="$(echo "$SCOPE" | sed -E 's#.*/resourceGroups/#rg:/#')"
  echo "  action: $ACTION"
  echo "  scope : $SHORT_SCOPE"
  echo "  unblock: az role assignment create --assignee $APP_ID --role \"$ROLE\" --scope \"$SCOPE\""

  # Append to the ledger (running record -> custom role JSON).
  printf '| %s | %s | %s | %s |\n' "$ACTION" "$ROLE" "$SHORT_SCOPE" "$([[ $APPLY -eq 1 ]] && echo granted || echo suggested)" >> "$LEDGER"

  if [[ $APPLY -eq 1 ]]; then
    echo "  -> granting..."
    "$AZ" role assignment create --assignee "$APP_ID" --role "$ROLE" --scope "$SCOPE" >/dev/null \
      && echo "     OK" || echo "     FAILED (check your own rights to assign at that scope)"
  fi
  echo
done

echo "Ledger updated: $LEDGER"
[[ $APPLY -eq 0 ]] && echo "Dry run — re-run with --apply to grant, then ./disco/run-apply.sh plan again."
