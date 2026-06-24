#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/Scripts/build-app.sh"
"$ROOT/Scripts/sign-app.sh"

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
  echo "Skipping notarization because SKIP_NOTARIZE=1."
else
  "$ROOT/Scripts/notarize-app.sh"
fi
