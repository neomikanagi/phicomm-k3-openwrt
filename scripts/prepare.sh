#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BUILD=${1:?Usage: prepare.sh /absolute/build/directory official|ac88}
VARIANT=${2:?Select official or ac88}
[[ $BUILD = /* && $BUILD != / ]] || { echo 'Build directory must be absolute' >&2; exit 1; }
case "$VARIANT" in official|ac88) ;; *) exit 2 ;; esac
[[ ! -e $BUILD ]] || { echo 'Use a fresh build directory' >&2; exit 1; }
lock() { jq -er "$1" "$ROOT/sources.lock.json"; }
git init "$BUILD"
git -C "$BUILD" remote add origin "$(lock .openwrt.url)"
git -C "$BUILD" fetch --depth=1 origin "$(lock .openwrt.commit)"
git -C "$BUILD" checkout --detach FETCH_HEAD
[[ $(git -C "$BUILD" rev-parse HEAD) = "$(lock .openwrt.commit)" ]]
cd "$BUILD"
# Official feeds.conf.default is already pinned by the release tag. Do not use moving branches.
cp feeds.conf.default feeds.conf
for feed in passwall_packages passwall2; do
    printf 'src-git %s %s^%s\n' "$feed" "$(lock ".$feed.url")" "$(lock ".$feed.commit")" >> feeds.conf
done
./scripts/feeds update -a
# Xray 26.10.31 requires Go 1.27. Select the compiler ALREADY included in this
# official release feed, rather than fetching a moving SDK or auto-downloading a toolchain.
export K3_GO_VERSION
K3_GO_VERSION=$(lock .build.go)
[[ $K3_GO_VERSION =~ ^1\.[0-9]+$ ]]
[[ -s "feeds/packages/lang/golang/golang$K3_GO_VERSION/Makefile" ]]
GO_VALUES=feeds/packages/lang/golang/golang-values.mk
[[ $(grep -c '^GO_DEFAULT_VERSION:=' "$GO_VALUES") = 1 ]]
perl -pi -e 's/^GO_DEFAULT_VERSION:=.*$/GO_DEFAULT_VERSION:=$ENV{K3_GO_VERSION}/' "$GO_VALUES"
# Feed scanning caches by Makefile mtime, not all included .mk files.
touch feeds/packages/lang/golang/golang/Makefile
./scripts/feeds update -i packages
./scripts/feeds install -p packages "golang$K3_GO_VERSION"
[[ -L "package/feeds/packages/golang$K3_GO_VERSION" ]]
# Install only this appliance's package closure. Installing every LuCI application
# exposes unrelated upstream Kconfig cycles (e.g. luci-app-weechat / weechat).
./scripts/feeds install -p luci luci luci-ssl luci-compat luci-lib-jsonc
./scripts/feeds install -p packages adguardhome bind-dig lyaml curl htop zram-swap
# Only override packages actually used by PassWall2; leave other official packages alone.
./scripts/feeds install -f -p passwall_packages chinadns-ng geoview tcping v2ray-geoip v2ray-geosite xray-core
./scripts/feeds install -f -p passwall2 luci-app-passwall2
for feed in passwall_packages passwall2; do
    [[ $(git -C "feeds/$feed" rev-parse HEAD) = "$(lock ".$feed.commit")" ]]
done
cp "$ROOT/config/k3.config" .config
cp -a "$ROOT/files" ./files
chmod +x files/etc/uci-defaults/99-k3 files/usr/sbin/k3-adguard files/usr/sbin/k3-check
install -Dm644 "$ROOT/sources.lock.json" files/etc/k3-sources.json
printf '%s\n' "$VARIANT" > files/etc/k3-wireless-variant
if [[ $VARIANT = ac88 ]]; then
    # Replace the contents of the selected firmware package, NOT files/ overlay:
    # this keeps the installed package manifest and the actual blob consistent.
    blob_dir="$BUILD/k3-vendor-firmware"
    mkdir -p "$blob_dir"
    curl --fail --location --retry 4 --proto '=https' --tlsv1.2 \
        "$(lock .ac88.url)" -o "$blob_dir/brcmfmac4366c-pcie.bin"
    printf '%s  %s\n' "$(lock .ac88.sha256)" "$blob_dir/brcmfmac4366c-pcie.bin" | sha256sum -c -
    # Scoped substitution: fail rather than silently patching the wrong device firmware.
    FILE=package/firmware/linux-firmware/broadcom.mk
    # Match a literal Make variable, not a shell expansion.
    # shellcheck disable=SC2016
    [[ $(grep -Fc '$(PKG_BUILD_DIR)/brcm/brcmfmac4366c-pcie.bin' "$FILE") = 1 ]]
    perl -0pi -e 's#\Q\$(PKG_BUILD_DIR)/brcm/brcmfmac4366c-pcie.bin\E#\$(TOPDIR)/k3-vendor-firmware/brcmfmac4366c-pcie.bin#g' "$FILE"
fi
make defconfig
"$ROOT/scripts/validate-config.sh" .config
printf '\nPrepared %s (%s)\n' "$BUILD" "$VARIANT"
