#!/bin/bash
#
# fix-bluetooth-firmware.sh
#
# Fix the Bluetooth firmware on a live Ubuntu system running on the Surface Pro 11.
#
# This is based on: https://wiki.debian.org/InstallingDebianOn/Thinkpad/X13s#Wi-Fi_and_Bluetooth
#
# On the Surface Pro 11, the Bluetooth MAC falls back to a random
# address on every boot, and Bluetooth won't work at all without its real address
# being set. This script restores the addresses noted down from Windows
# (Settings > Network & Internet > Properties, or `ipconfig /all`) by:
#
#   1. Creating /etc/udev/rules.d/99-fix_mac_addresses.rules, which:
#        - sets the Wi-Fi interface's MAC directly via a udev RUN rule
#        - triggers a systemd template service to fix the Bluetooth MAC
#   2. Creating /lib/systemd/system/hci-btaddress@.service, which uses
#      `btmgmt` to set the Bluetooth controller's public address.
#   3. Reloading the systemd daemon so the new unit is picked up.
#
# A reboot is required afterwards for the changes to take effect.
#
# Usage:
#   sudo ./fix-bluetooth-firmware.sh <WIFI_MAC> <BT_MAC>
#   sudo ./fix-bluetooth-firmware.sh            (interactive prompts)
#
# MACs may be given with ':' or '-' separators (Windows style is fine).

set -euo pipefail

UDEV_RULES_FILE="/etc/udev/rules.d/99-fix_mac_addresses.rules"
SERVICE_FILE="/etc/systemd/system/hci-btaddress@.service"
WIFI_KERNELS="0006:01:00.0"   # PCI address Wi-Fi card on Surface Pro 11
WIFI_IFACE="wlP6p1s0"         # predictable interface name on Surface Pro 11

# err()  { printf 'Error: %s\n' "$*" >&2; exit 1; }
# info() { printf '==> %s\n' "$*"; }
info() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
err() { printf "\033[1;33m[ERROR]\033[0m %s\n" "$*"; }

# --- sanity checks -----------------------------------------------------------

# [[ $EUID -eq 0 ]] || (err "this script must be run as root (try: sudo $0 ...)" && exit 1)

command -v btmgmt >/dev/null 2>&1 || {
    info "btmgmt not found; it is required by the Bluetooth fix."
    if command -v apt-get >/dev/null 2>&1; then
        info "Installing bluez..."
        apt-get install -y bluez
    else
        err "please install the 'bluez' package (provides btmgmt) and re-run"
    fi
}

# --- collect and validate MAC addresses --------------------------------------

normalize_mac() {
    # Accept AA-BB-CC-DD-EE-FF or aa:bb:cc:dd:ee:ff, output AA:BB:CC:DD:EE:FF
    local mac="${1//-/:}"
    mac="${mac^^}"
    [[ "$mac" =~ ^([0-9A-F]{2}:){5}[0-9A-F]{2}$ ]] || return 1
    printf '%s' "$mac"
}

WIFI_MAC_RAW=""
BT_MAC_RAW=""
if [ "$#" -ge 2 ]; then
    WIFI_MAC_RAW="${1:-}"
    BT_MAC_RAW="${2:-}"
else
    # Compgen causes the script to fail if it can't find the variable, so we have to use
    # this method first.
    shopt -s nullglob # Enable nullglob so the array stays empty if nothing matches
    files=( "/sys/firmware/efi/efivars/MacAddressEmulationAddress-"* )
    if (( ${#files[@]} )); then
        EFI_VAR_PATH=$(compgen -G "/sys/firmware/efi/efivars/MacAddressEmulationAddress-*" | head -n1)
        echo $EFI_VAR_PATH
        if [ -z "$EFI_VAR_PATH" ]; then
            echo "[+] MacAddressEmulationAddress EFI variable not found"
            exit 1
        fi
        # Skip the 4-byte attribute header, read the remaining 6 bytes as raw MAC
        MAC_HEX=$(xxd -p -s 4 "$EFI_VAR_PATH" | tr -d '\n')
        MAC=$(echo "$MAC_HEX" | sed -E 's/(..)/\1:/g; s/:$//' | tr 'a-f' 'A-F')
        WIFI_MAC_RAW="${MAC}"
        BT_MAC_RAW="${MAC}"
    fi
fi

if [[ -z "$WIFI_MAC_RAW" || -z "$BT_MAC_RAW" ]]; then
    read -rp "Wi-Fi MAC address (from Windows 'getmac /v' or 'ipconfig /all', Wireless LAN adapter Wi-Fi): " WIFI_MAC_RAW
    read -rp "Bluetooth MAC address (Ethernet adapter Bluetooth Network Connection): " BT_MAC_RAW
fi

WIFI_MAC="$(normalize_mac "$WIFI_MAC_RAW")" || (err "invalid Wi-Fi MAC address: $WIFI_MAC_RAW" && exit 1)
BT_MAC="$(normalize_mac "$BT_MAC_RAW")"     || (err "invalid Bluetooth MAC address: $BT_MAC_RAW" && exit 1)

[[ "$WIFI_MAC" != "$BT_MAC" ]] || info "warning: Wi-Fi and Bluetooth MACs are identical - double-check your notes."

info "Wi-Fi MAC:     $WIFI_MAC"
info "Bluetooth MAC: $BT_MAC"

# --- back up any existing files ----------------------------------------------

for f in "$UDEV_RULES_FILE" "$SERVICE_FILE"; do
    if [[ -e "$f" ]]; then
        cp -a "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
        info "Backed up existing $f"
    fi
done

# --- 1) udev rules -------------------------------------------------------------

info "Writing $UDEV_RULES_FILE"
cat > "$UDEV_RULES_FILE" <<EOF
ACTION=="add", SUBSYSTEM=="net", KERNELS=="$WIFI_KERNELS", \\
  RUN+="/usr/sbin/ip link set dev $WIFI_IFACE address $WIFI_MAC"
ACTION=="add", SUBSYSTEM=="bluetooth", ENV{DEVTYPE}=="host" \\
  ENV{DEVPATH}=="*/serial[0-9]*/serial[0-9]*/bluetooth/hci[0-9]*", \\
  TAG+="systemd", ENV{SYSTEMD_WANTS}="hci-btaddress@%k.service"
EOF
# cat > "$UDEV_RULES_FILE" <<EOF
# ACTION=="add", SUBSYSTEM=="net", KERNELS=="$WIFI_KERNELS", \\
#   RUN+="/usr/sbin/ip link set dev $WIFI_IFACE address $WIFI_MAC"
# ACTION=="add", SUBSYSTEM=="bluetooth", ENV{DEVTYPE}=="host" \\
#   ENV{DEVPATH}=="*/serial[0-9]*/serial[0-9]*/bluetooth/hci[0-9]*", \\
#   TAG+="systemd", ENV{SYSTEMD_WANTS}="hci-btaddress@%k.service"
# EOF

# --- 2) systemd service for the Bluetooth address ------------------------------

info "Writing $SERVICE_FILE"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=HCI bluetooth address fix

[Service]
Type=simple
ExecStart=/bin/sh -c 'sleep 5 && yes | btmgmt -i %I public-addr $BT_MAC'
EOF

# --- 3) reload configuration ---------------------------------------------------

info "Reloading systemd units"
systemctl daemon-reload

info "Reloading udev rules"
udevadm control --reload

info "Done. The addresses will be applied automatically on the next boot."
info "Reboot now to apply the changes (sudo reboot)."
