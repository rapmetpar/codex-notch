#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/package_paths.sh"

cd "$ROOT_DIR"

"$ROOT_DIR/scripts/check_contracts.sh"
bash "$ROOT_DIR/scripts/verify_package_paths.sh"
swift test
RUN_TESTS=0 "$ROOT_DIR/scripts/build_app.sh" "$DIST_DIR"
"$ROOT_DIR/scripts/verify_app.sh" "$DIST_DIR/CodexNotch.app"
python3 "$ROOT_DIR/scripts/verify_preferences.py"

echo "Full verification passed: $DIST_DIR/CodexNotch.app"
