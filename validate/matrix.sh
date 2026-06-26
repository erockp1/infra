#!/usr/bin/env bash
# POC 0 validation matrix — hits the deployed bind app and checks responses.
#
# Usage:
#   ALICE_PW='...' [BOB_PW='...'] [APP_URL=https://...] ./validate/matrix.sh
#
# If APP_URL is unset it is read from `terraform output`. Passwords are passed in
# the environment (test-only; never committed).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_URL="${APP_URL:-$(cd "$ROOT" && terraform output -json app 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["app_url"])')}"
: "${ALICE_PW:?set ALICE_PW to the alice test password}"
BOB_PW="${BOB_PW:-}"

pass=0
fail=0

post() { curl -s --max-time 30 -X POST "$APP_URL/$1" -H 'content-type: application/json' -d "$2"; }
# JSON built via printf (single-quoted format) so the {} literal never hits the
# command line — avoids bash brace-expansion splitting it on the comma.
jbind() { printf '{"username":"%s","password":"%s"}' "$1" "$2"; }
jcheck() { printf '{"username":"%s"}' "$1"; }

check() { # name  expected_grep  json
  if printf '%s' "$3" | grep -q "$2"; then
    echo "PASS  $1"
    pass=$((pass + 1))
  else
    echo "FAIL  $1 -> $3"
    fail=$((fail + 1))
  fi
}

echo "App: $APP_URL"
for _ in $(seq 1 8); do curl -s --max-time 20 "$APP_URL/healthz" | grep -q ok && break; sleep 5; done

check "valid+correct (alice) -> success" '"result":"success"' "$(post bind "$(jbind alice "$ALICE_PW")")"
check "valid+wrong   (alice) -> failure" '"result":"failure"' "$(post bind "$(jbind alice 'definitely-wrong-pw')")"
check "by-name + cert: /check reads UAC" 'userAccountControl' "$(post check "$(jcheck alice)")"
if [ -n "$BOB_PW" ]; then
  check "valid+correct (bob)  -> success" '"result":"success"' "$(post bind "$(jbind bob "$BOB_PW")")"
fi

echo "---"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
