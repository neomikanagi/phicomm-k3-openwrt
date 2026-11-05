#!/usr/bin/env bash
# Point the 4366c0 firmware package at the pinned blob. Replacing the package's contents,
# rather than overlaying files/, keeps the installed manifest and the actual blob consistent.
set -euo pipefail
FILE=${1:?Usage: patch-wifi-firmware.sh broadcom.mk}
# Literal Make variables, not shell expansions.
# shellcheck disable=SC2016
export OLD='$(PKG_BUILD_DIR)/brcm/brcmfmac4366c-pcie.bin'
# shellcheck disable=SC2016
export NEW='$(TOPDIR)/k3-vendor-firmware/brcmfmac4366c-pcie.bin'
# Fail rather than silently keep, or patch the wrong, device firmware.
[[ $(grep -Fc "$OLD" "$FILE") = 1 ]] || { echo "Expected exactly one firmware path in $FILE" >&2; exit 1; }
perl -pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/' "$FILE"
[[ $(grep -Fc "$OLD" "$FILE") = 0 && $(grep -Fc "$NEW" "$FILE") = 1 ]] || { echo "Patching $FILE failed" >&2; exit 1; }
