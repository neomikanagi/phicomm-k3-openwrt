#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
for file in scripts/*.sh; do bash -n "$file"; done
for file in files/etc/uci-defaults/99-k3 files/usr/sbin/*; do sh -n "$file"; done
if command -v shellcheck >/dev/null; then
    shellcheck scripts/*.sh
    # OpenWrt ash supports local. Runtime /lib/functions.sh is not present on the runner.
    shellcheck -s ash -e SC1091,SC3043 files/etc/uci-defaults/99-k3 files/usr/sbin/*
fi
python3 -m unittest discover -s tests -p 'test_*.py' -v
