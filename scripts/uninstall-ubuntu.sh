#!/usr/bin/env bash
# Remove Linuwu-Sense installed by scripts/install-ubuntu.sh.
# Usage: sudo ./scripts/uninstall-ubuntu.sh
set -euo pipefail

PKG=linuwu_sense
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$(dirname "$0")/../dkms.conf")
REAL_USER="${SUDO_USER:-$USER}"

[[ $EUID -eq 0 ]] || { echo "error: run with sudo" >&2; exit 1; }

echo "==> removing DKMS registration"
dkms remove "$PKG/$VER" --all >/dev/null 2>&1 || true
rm -rf "/usr/src/$PKG-$VER"

echo "==> restoring acer_wmi"
rm -f /etc/modules-load.d/$PKG.conf /etc/modprobe.d/blacklist-acer_wmi.conf
rm -f /etc/tmpfiles.d/$PKG.conf
rm -f /etc/systemd/system/linuwu_sense.service
systemctl daemon-reload
modprobe -r "$PKG" 2>/dev/null || true
depmod -a
modprobe acer_wmi 2>/dev/null || true

echo "==> removing group membership"
if getent group $PKG >/dev/null; then
    gpasswd -d "$REAL_USER" $PKG 2>/dev/null || true
    groupdel $PKG 2>/dev/null || true
fi

echo "Done. Reboot to fully restore the stock driver."
