#!/usr/bin/env bash
# Shared by build, verification and release entry points. Keep development apps
# outside Spotlight without changing the installed bundle's identity or contents.
DIST_DIR="${1:-${DIST_DIR:-$ROOT_DIR/dist.noindex}}"
