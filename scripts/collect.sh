#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BUILD=${1:?Usage: collect.sh build-dir output-dir}
OUT=${2:?}
VERSION=$(jq -r .openwrt.version "$ROOT/sources.lock.json")
TARGET="$BUILD/bin/targets/bcm53xx/generic"
# Local source builds need not include a version in filenames. Use the generated
# profile metadata, not the download server's naming convention.
jq -e --arg version "$VERSION" \
    '(.version_number == $version) and (.profiles.phicomm_k3.supported_devices | index("phicomm,k3") != null)' \
    "$TARGET/profiles.json" >/dev/null
IMAGE_NAME=$(jq -er '.profiles.phicomm_k3.images | map(select(.filesystem == "squashfs" and .type == "trx")) | if length == 1 then .[0].name else error("Expected one K3 squashfs TRX") end' "$TARGET/profiles.json")
[[ $IMAGE_NAME = "$(basename "$IMAGE_NAME")" && $IMAGE_NAME = *.trx ]]
IMAGE="$TARGET/$IMAGE_NAME"
[[ -s $IMAGE ]]
# TRX magic is HDR0. Conservative ceiling; actual flash layout must be checked on the router.
[[ $(od -An -tx1 -N4 "$IMAGE" | tr -d ' \n') = 48445230 ]]
[[ $(stat -c %s "$IMAGE") -lt 104857600 ]]
shopt -s nullglob
manifests=("$TARGET"/*.manifest)
[[ ${#manifests[@]} = 1 ]]
MANIFEST=${manifests[0]}
[[ -s $MANIFEST ]]
# Symbols with an underscore are package options, not packages.
while IFS= read -r package; do
    grep -qE "^${package} - " "$MANIFEST" || { echo "Missing from image manifest: $package" >&2; exit 1; }
done < <(sed -nE 's/^CONFIG_PACKAGE_([^_=]+)=y$/\1/p' "$ROOT/config/k3.config")
roots=("$BUILD"/build_dir/target-*/root-bcm53xx)
[[ ${#roots[@]} = 1 ]]
rootfs=${roots[0]}
for path in usr/bin/AdGuardHome usr/bin/xray usr/sbin/k3-adguard usr/sbin/k3-check usr/sbin/usbmuxd \
    usr/share/k3/adguard-config.lua etc/uci-defaults/99-k3 etc/k3-sources.json; do
    [[ -s "$rootfs/$path" ]] || { echo "Missing from rootfs: $path" >&2; exit 1; }
done
BLOB="$rootfs/lib/firmware/brcm/brcmfmac4366c-pcie.bin"
printf '%s  %s\n' "$(jq -r .wifi_firmware.sha256 "$ROOT/sources.lock.json")" "$BLOB" | sha256sum -c -
mkdir -p "$OUT"
cp "$IMAGE" "$OUT/k3-openwrt-$VERSION-squashfs.trx"
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
printf 'BUILD VERIFIED, HARDWARE UNTESTED. Not K3C.\n' > "$OUT/STATUS.txt"
rm -f "$OUT/SHA256SUMS"
(cd "$OUT" && sha256sum -- * > SHA256SUMS)
echo "Validated artifact: $OUT"
