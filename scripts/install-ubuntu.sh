#!/usr/bin/env bash
# Ubuntu/Debian installer for Linuwu-Sense.
#
# Builds the module through DKMS so it is rebuilt automatically on every kernel
# upgrade, then performs the same post-install steps the Makefile's `install`
# target does (blacklist acer_wmi, group, tmpfiles, systemd unit).
#
# Usage:  sudo ./scripts/install-ubuntu.sh
set -euo pipefail

PKG=linuwu_sense
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$(dirname "$0")/../dkms.conf")
SRC=$(cd "$(dirname "$0")/.." && pwd)
DST=/usr/src/$PKG-$VER

die() { echo "error: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run with sudo"
[[ -n "${VER}" ]] || die "could not read PACKAGE_VERSION from dkms.conf"

REAL_USER="${SUDO_USER:-$USER}"
KVER=$(uname -r)

echo "==> installing build dependencies"
apt-get update -qq
apt-get install -y build-essential dkms "linux-headers-$KVER"

echo "==> staging sources to $DST"
rm -rf "$DST"
mkdir -p "$DST"
cp -a "$SRC"/. "$DST"/
# DKMS rebuilds from this copy; drop build artifacts so it always compiles clean.
make -C "$DST" clean >/dev/null 2>&1 || true
rm -rf "$DST/.git" "$DST"/src/.*.cmd "$DST"/.*.cmd 2>/dev/null || true

# --- Secure Boot: sign the module with a local MOK, otherwise Ubuntu refuses to load it ---
if [[ -d /sys/firmware/efi ]] && mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
    echo "==> Secure Boot detected: configuring DKMS module signing"
    KEYDIR=/var/lib/dkms
    if [[ ! -f $KEYDIR/mok.key ]]; then
        openssl req -new -x509 -newkey rsa:2048 -nodes -days 36500 \
            -keyout "$KEYDIR/mok.key" -outform DER -out "$KEYDIR/mok.der" \
            -subj "/CN=Linuwu-Sense Module Signing/"
        chmod 600 "$KEYDIR/mok.key"
    fi
    if ! grep -q '^mok_signing_key' /etc/dkms/framework.conf 2>/dev/null; then
        printf '\nmok_signing_key="%s"\nmok_certificate="%s"\n' \
            "$KEYDIR/mok.key" "$KEYDIR/mok.der" >> /etc/dkms/framework.conf
    fi
    if ! mokutil --test-key "$KEYDIR/mok.der" 2>/dev/null | grep -q "already enrolled"; then
        echo
        echo "  ACTION REQUIRED: the signing key must be enrolled before the module can load."
        echo "  Run:  sudo mokutil --import $KEYDIR/mok.der"
        echo "  then reboot and complete the blue MOK manager screen (Enroll MOK -> Continue)."
        echo
    fi
else
    echo "==> Secure Boot not enabled: module will load unsigned"
fi

echo "==> registering with DKMS"
dkms remove "$PKG/$VER" --all >/dev/null 2>&1 || true
dkms add "$PKG/$VER"
dkms build "$PKG/$VER"
dkms install "$PKG/$VER" --force

echo "==> blacklisting the stock acer_wmi"
echo "blacklist acer_wmi" > /etc/modprobe.d/blacklist-acer_wmi.conf
modprobe -r acer_wmi 2>/dev/null || true

echo "==> loading $PKG"
depmod -a
echo "$PKG" > /etc/modules-load.d/$PKG.conf
modprobe "$PKG"

echo "==> systemd shutdown unit"
install -m 644 "$SRC/linuwu_sense.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable linuwu_sense.service

echo "==> group + sysfs permissions"
getent group $PKG >/dev/null || groupadd $PKG
usermod -aG $PKG "$REAL_USER"

AWMIDIR=/sys/module/$PKG/drivers/platform:acer-wmi/acer-wmi
MODEL_PATH=""
for d in "$AWMIDIR/predator_sense" "$AWMIDIR/nitro_sense"; do
    [[ -d "$d" ]] && MODEL_PATH=${d##*/} && break
done
if [[ -n "$MODEL_PATH" ]]; then
    echo "    detected: $MODEL_PATH"
    if [[ "$MODEL_PATH" == *nitro_sense* ]]; then
        FIELDS="fan_speed battery_limiter battery_calibration usb_charging"
    else
        FIELDS="backlight_timeout battery_calibration battery_limiter boot_animation_sound fan_speed lcd_override usb_charging"
    fi
    CONF=/etc/tmpfiles.d/$PKG.conf
    : > "$CONF"
    for f in $FIELDS; do
        echo "f /sys/module/$PKG/drivers/platform:acer-wmi/acer-wmi/$MODEL_PATH/$f 0660 root $PKG" >> "$CONF"
    done
    KB=/sys/module/$PKG/drivers/platform:acer-wmi/acer-wmi/four_zoned_kb
    if [[ -d $KB ]]; then
        for z in four_zone_mode per_zone_mode; do
            echo "f $KB/$z 0660 root $PKG" >> "$CONF"
        done
    fi
    systemd-tmpfiles --create "$CONF"
else
    echo "    warning: no predator_sense/nitro_sense node in sysfs; permissions not set"
fi

echo
echo "Done. Reboot (or log out and back in for the group), then check:"
echo "  lsmod | grep $PKG"
echo "  ls /sys/module/$PKG/drivers/platform:acer-wmi/acer-wmi/"
