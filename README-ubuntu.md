# Ubuntu / Debian install

Tested on Ubuntu 24.04 LTS and Kali (Debian-based), kernel 6.8 → 7.2.

DKMS-based, so the module is rebuilt automatically on every `apt upgrade` that pulls a new
kernel. Secure Boot signing is handled with a local MOK.

## Install

```bash
git clone https://github.com/<you>/Linuwu-Sense.git
cd Linuwu-Sense
sudo ./scripts/install-ubuntu.sh
```

If the installer prints the `ACTION REQUIRED` block (Secure Boot machines), enroll the key once:

```bash
sudo mokutil --import /var/lib/dkms/mok.der
sudo reboot     # in the blue MOK screen: Enroll MOK -> Continue -> Reboot
```

After reboot:

```bash
lsmod | grep linuwu_sense
ls /sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/
```

## What the installer does

1. `apt install build-essential dkms linux-headers-$(uname -r)`
2. Stages the tree to `/usr/src/linuwu_sense-1.0.0` and registers it with DKMS
3. Signs via MOK when Secure Boot is on (`/var/lib/dkms/mok.{key,der}`, `dkms/framework.conf`)
4. Blacklists `acer_wmi` (`/etc/modprobe.d/blacklist-acer_wmi.conf`)
5. `/etc/modules-load.d/linuwu_sense.conf` → loads at boot
6. Creates the `linuwu_sense` group, adds your user, writes `systemd-tmpfiles` rules so
   `fan_speed`, `battery_limiter`, `battery_calibration`, `backlight_timeout`, `usb_charging`
   (and `four_zone_mode` / `per_zone_mode` where present) are `0660 root:linuwu_sense`
7. Installs `linuwu_sense.service` (unloads the module at shutdown)
8. `modprobe linuwu_sense`

After step 6 you must log out and back in (or `newgrp linuwu_sense`) before your user can
write to the sysfs attributes.

## Uninstall

```bash
sudo ./scripts/uninstall-ubuntu.sh
sudo reboot
```

## Manual build (no DKMS)

```bash
sudo apt install build-essential linux-headers-$(uname -r)
make
sudo make install
```

`make install` modifies the live `acer_wmi` module state, so it is system-changing — the DKMS
path is the recommended one on Ubuntu because it survives kernel upgrades.

## Kernel compatibility notes

- **Linux 7.2+**: `strncpy()` was removed. This tree uses `strscpy()` at all three sysfs write
  handlers (`input`, `input_buf`, `str_buf`). `strscpy()` exists since 4.3, so the same source
  builds on 5.15 / 6.8 / 6.14 / 7.x without `#if` guards.
- **Kernel 6.17+**: `platform_profile` moved to the `platform_profile_ops` API (see
  `ffd5dcb feat: PTX17-71 support + platform_profile_ops API`). If `make` fails on
  `platform_profile_register`, your kernel needs that upstream commit, not a local patch.
- **Keyboard scancode 0x87** is deliberately unmapped (it was bound to `KEY_POWER`, which shut
  the machine down on that key).

## Troubleshooting

| symptom | cause |
|---|---|
| `modprobe: ERROR: could not insert 'linuwu_sense': Key was rejected by service` | MOK not enrolled, or key enrolled for a different kernel — re-run `sudo mokutil --import /var/lib/dkms/mok.der`, reboot |
| `insmod: ERROR: could not insert module: Operation not permitted` | Secure Boot on and module unsigned — check `mokutil --sb-state` |
| sysfs nodes exist but writes give `Permission denied` | group not refreshed: `newgrp linuwu_sense` or re-login |
| module loads but no RGB/fan control | model not detected; check `dmesg \| grep -i linuwu` and the `predator_sense`/`nitro_sense` node |
| DKMS build fails after `apt upgrade` | `sudo dkms autoinstall`; if still failing, kernel API moved — check the commit log |
