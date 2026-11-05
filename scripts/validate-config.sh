#!/usr/bin/env bash
set -euo pipefail
CONFIG=${1:?Usage: validate-config.sh .config}
for symbol in \
    TARGET_bcm53xx TARGET_bcm53xx_generic TARGET_bcm53xx_generic_DEVICE_phicomm_k3 \
    PACKAGE_luci PACKAGE_luci-ssl PACKAGE_luci-app-passwall2 PACKAGE_luci-i18n-passwall2-zh-cn \
    PACKAGE_luci-app-passwall2_Basic_Core_Xray PACKAGE_luci-app-passwall2_Nftables_Transparent_Proxy \
    PACKAGE_xray-core PACKAGE_chinadns-ng PACKAGE_geoview PACKAGE_v2ray-geoip PACKAGE_v2ray-geosite \
    PACKAGE_dnsmasq-full PACKAGE_dnsmasq_full_nftset PACKAGE_firewall4 \
    PACKAGE_kmod-nft-tproxy PACKAGE_kmod-nft-socket PACKAGE_kmod-nft-nat \
    PACKAGE_adguardhome PACKAGE_lyaml PACKAGE_bind-dig PACKAGE_kmod-brcmfmac \
    PACKAGE_brcmfmac-firmware-4366c0-pcie PACKAGE_wpad-basic-mbedtls; do
    grep -qxF "CONFIG_${symbol}=y" "$CONFIG" || { echo "Missing required symbol: $symbol" >&2; exit 1; }
done
for symbol in PACKAGE_dnsmasq PACKAGE_sing-box PACKAGE_luci-app-passwall2_Iptables_Transparent_Proxy; do
    if grep -qxF "CONFIG_${symbol}=y" "$CONFIG"; then
        echo "Conflicting/unwanted symbol: $symbol" >&2; exit 1
    fi
done
# Selecting a second board accidentally can produce a valid but wrong TRX.
[[ $(grep -cE '^CONFIG_TARGET_bcm53xx_generic_DEVICE_.*=y$' "$CONFIG") = 1 ]]
echo 'K3 configuration validated'
