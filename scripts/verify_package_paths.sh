#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

resolve_path() (
    unset DIST_DIR
    if [[ -n "$1" ]]; then export DIST_DIR="$1"; fi
    shift
    source "$ROOT_DIR/scripts/package_paths.sh"
    printf '%s\n' "$DIST_DIR"
)

[[ "$(resolve_path '')" == "$ROOT_DIR/dist.noindex" ]]
[[ "$(resolve_path '/tmp/custom output')" == '/tmp/custom output' ]]
[[ "$(resolve_path '/tmp/env output' '/tmp/argument output')" == '/tmp/argument output' ]]
for SCRIPT in build_app.sh verify.sh release.sh; do
    grep -Fq 'source "$ROOT_DIR/scripts/package_paths.sh"' "$ROOT_DIR/scripts/$SCRIPT"
done
echo 'Packaging paths passed: default excluded from Spotlight; explicit paths preserved'
