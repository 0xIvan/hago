#!/usr/bin/env bash
# Opens the installed Hago on a separate, freshly seeded demo database. Your real history is untouched.
set -euo pipefail
APP="${1:-/Applications/Hago.app}"
osascript -e 'tell application id "com.ivan.hago" to quit' >/dev/null 2>&1 || true
sleep 1
open -n "$APP" --args --demo
echo "Hago is showing demo data. Quit it and open Hago normally to return to your own history."
