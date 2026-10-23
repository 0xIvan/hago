#!/usr/bin/env bash
set -euo pipefail

for attempt in 1 2 3 4 5; do
  if xcrun stapler "$@"; then
    exit 0
  else
    status=$?
  fi
  [[ "$status" == 68 && "$attempt" != 5 ]] || exit "$status"
  echo "Apple ticket service unavailable; retrying stapler (attempt $((attempt + 1))/5)." >&2
  sleep "$((attempt * 5))"
done
