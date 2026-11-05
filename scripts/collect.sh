#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BUILD=${1:?Usage: collect.sh build-dir official|ac88 output-dir}
VARIANT=${2:?}
OUT=${3:?}
case "$VARIANT" in official|ac88) ;; *) exit 2 ;; esac
VERSION=$(jq -r .openwrt.version "$ROOT/sources.lock.json")
TARGET="$BUILD/bin/targets/bcm53xx/generic"
IMAGE="$TARGET/openwrt-$VERSION-bcm53xx-generic-phicomm_k3-squashfs.trx"
[[ -s $IMAGE ]]
# TRX magic is HDR0. Conservative ceiling; actual flash layout must be checked on the router.
[[ $(od -An -tx1 -N4 "$IMAGE" | tr -d ' \n') = 48445230 ]]
[[ $(stat -c %s "$IMAGE") -lt 104857600 ]]
MANIFEST="$TARGET/openwrt-$VERSION-bcm53xx-generic.manifest"
[[ -s $MANIFEST ]]
for package in luci-app-passwall2 luci-i18n-passwall2-zh-cn xray-core dnsmasq-full \
    adguardhome lyaml kmod-brcmfmac brcmfmac-firmware-4366c0-pcie kmod-nft-tproxy kmod-nft-socket; do
    grep -qE "^${package} - " "$MANIFEST" || { echo "Missing from image manifest: $package" >&2; exit 1; }
done
shopt -s nullglob
roots=("$BUILD"/build_dir/target-*/root-bcm53xx)
[[ ${#roots[@]} = 1 ]]
rootfs=${roots[0]}
for path in usr/bin/AdGuardHome usr/bin/xray usr/sbin/k3-adguard usr/sbin/k3-check \
    usr/share/k3/adguard-config.lua etc/uci-defaults/99-k3 etc/k3-sources.json; do
    [[ -s "$rootfs/$path" ]] || { echo "Missing from rootfs: $path" >&2; exit 1; }
done
[[ $(< "$rootfs/etc/k3-wireless-variant") = "$VARIANT" ]]
BLOB="$rootfs/lib/firmware/brcm/brcmfmac4366c-pcie.bin"
if [[ $VARIANT = ac88 ]]; then
    printf '%s  %s\n' "$(jq -r .ac88.sha256 "$ROOT/sources.lock.json")" "$BLOB" | sha256sum -c -
else
    [[ $(sha256sum "$BLOB" | cut -d' ' -f1) != "$(jq -r .ac88.sha256 "$ROOT/sources.lock.json")" ]]
fi
mkdir -p "$OUT"
cp "$IMAGE" "$OUT/k3-openwrt-$VERSION-$VARIANT-squashfs.trx"
cp "$MANIFEST" "$OUT/packages.manifest"
cp "$ROOT/sources.lock.json" "$OUT/"
cp "$BUILD/.config" "$OUT/build.config"
cp "$BUILD/feeds.conf" "$OUT/feeds.conf"
cp "$ROOT/README.md" "$OUT/README.md"
cp "$ROOT/docs/acceptance.md" "$OUT/acceptance.md"
(
    cd "$BUILD"
    git rev-parse HEAD
    for feed in feeds/*/.git; do
        printf '%s ' "${feed%/.git}"
        git -C "${feed%/.git}" rev-parse HEAD
    done
    sha256sum "$BLOB"
    git diff -- package/firmware/linux-firmware/broadcom.mk
    git -C feeds/packages diff -- lang/golang/golang-values.mk
) > "$OUT/provenance.txt"
printf 'BUILD VERIFIED, HARDWARE UNTESTED. Variant: %s. Not K3C.\n' "$VARIANT" > "$OUT/STATUS.txt"
rm -f "$OUT/SHA256SUMS"
(cd "$OUT" && sha256sum -- * > SHA256SUMS)
echo "Validated candidate artifact: $OUT"
