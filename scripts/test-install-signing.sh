#!/usr/bin/env zsh
set -euo pipefail

INSTALL_SCRIPT="$(cd "$(dirname "$0")" && pwd)/install-app.sh"
OLD_HASH="1111111111111111111111111111111111111111"
NEW_HASH="2222222222222222222222222222222222222222"
OLD_IDENTITY="  1) $OLD_HASH \"Worklog Local Code Signing\""
NEW_IDENTITY="  2) $NEW_HASH \"Hago Local Code Signing\""
CHECKS=0

check() {
  local label="$1" expected_code="$2" expected_output="$3"
  local identity_fixture="$4" installed_fixture="$5" requested_identity="$6"
  local result result_code

  if result="$(
    export HAGO_CODE_SIGN_IDENTITY="$requested_identity"
    security() { printf '%s\n' "$identity_fixture"; }
    codesign() { printf '%s\n' "$installed_fixture" >&2; }
    # A preflight regression must not stop, replace, or open the user's app during tests.
    pkill() { return 98; }
    rm() { return 98; }
    ditto() { return 98; }
    open() { return 98; }
    source "$INSTALL_SCRIPT" --check-signing 2>&1
  )"; then
    result_code=0
  else
    result_code=$?
  fi

  if [[ "$result_code" != "$expected_code" || "$result" != *"$expected_output"* ]]; then
    printf 'FAIL: %s (exit %s)\n%s\n' "$label" "$result_code" "$result" >&2
    exit 1
  fi
  printf 'PASS: %s\n' "$label"
  CHECKS=$((CHECKS + 1))
}

check "Legacy certificate survives rename" 0 "$OLD_HASH" "$OLD_IDENTITY" "Signature=adhoc" ""
check "New certificate on first install" 0 "$NEW_HASH" "$NEW_IDENTITY" "" ""
check "Installed certificate takes precedence" 0 "$OLD_HASH" "$OLD_IDENTITY"$'\n'"$NEW_IDENTITY" "Authority=Worklog Local Code Signing" ""
check "Explicit certificate name" 0 "$NEW_HASH" "$NEW_IDENTITY" "" "Hago Local Code Signing"
check "Explicit certificate fingerprint" 0 "$OLD_HASH" "$OLD_IDENTITY" "" "$OLD_HASH"
check "No certificate stops installation" 1 "No unique valid signing identity" "0 valid identities found" "" ""
check "Missing installed certificate does not silently switch" 1 "No unique valid signing identity" "$NEW_IDENTITY" "Authority=Worklog Local Code Signing" ""
check "Invalid explicit identity stops installation" 1 "No unique valid signing identity" "$OLD_IDENTITY" "" "Missing certificate"
check "Ad hoc override is rejected" 1 "Ad hoc signing is not allowed" "$OLD_IDENTITY" "" "-"
check "Ambiguous certificate name is rejected" 1 "No unique valid signing identity" "$OLD_IDENTITY"$'\n'"  2) $NEW_HASH \"Worklog Local Code Signing\"" "" "Worklog Local Code Signing"
printf '%s signing checks passed\n' "$CHECKS"
