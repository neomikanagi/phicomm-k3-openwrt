#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG=${1:?Usage: validate-config.sh .config}
# make defconfig silently drops what it cannot resolve: everything requested must survive.
while IFS= read -r line; do
    grep -qxF "$line" "$CONFIG" || { echo "Missing required symbol: $line" >&2; exit 1; }
done < <(grep -E '^CONFIG_.*=y$' "$ROOT/config/k3.config")
for symbol in PACKAGE_dnsmasq PACKAGE_sing-box PACKAGE_luci-app-passwall2_Iptables_Transparent_Proxy; do
    if grep -qxF "CONFIG_${symbol}=y" "$CONFIG"; then
        echo "Conflicting/unwanted symbol: $symbol" >&2; exit 1
    fi
done
# Selecting a second board accidentally can produce a valid but wrong TRX.
[[ $(grep -cE '^CONFIG_TARGET_bcm53xx_generic_DEVICE_.*=y$' "$CONFIG") = 1 ]]
echo 'K3 configuration validated'
