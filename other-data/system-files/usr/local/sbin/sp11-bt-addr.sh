#!/usr/bin/env bash
# 
# sp11-bt-addr.sh
# 
# Set Bluetooth MAC from UEFI variable before bluetoothd starts.
# 

# ===============================================
EFI_VAR_PATH=$(compgen -G "/sys/firmware/efi/efivars/MacAddressEmulationAddress-*" | head -n1)
if [ -z "$EFI_VAR_PATH" ]; then
    echo "[+] MacAddressEmulationAddress EFI variable not found"
    exit 1
fi

# Skip the 4-byte attribute header, read the remaining 6 bytes as raw MAC
MAC_HEX=$(xxd -p -s 4 "$EFI_VAR_PATH" | tr -d '\n')
MAC=$(echo "$MAC_HEX" | sed -E 's/(..)/\1:/g; s/:$//' | tr 'a-f' 'A-F')
# --------------------------------------------------
#   This might work better for you on the SP11 X1P. Uncomment this section and comment
#   the section above to see.
# EFI_VAR="MacAddressEmulationAddress-b7f95555-4ea5-4786-b088-78ba350a1b56"
# EFI_PATH="/sys/firmware/efi/efivars/$EFI_VAR"

# MAC=$(hexdump -s 4 -n 6 -e '5/1 "%02X:" 1/1 "%02X"' "$EFI_PATH" 2>/dev/null)
# if [ -z "$MAC" ]; then
#     echo "sp11-bt-addr: UEFI variable not found, using default MAC" >&2
#     exit 0
# fi
# ===============================================

# Wait for hci0 to appear (up to 10 seconds)
for i in $(seq 1 50); do
    [ -e /sys/class/bluetooth/hci0 ] && break
    sleep 0.2
done
if [ ! -e /sys/class/bluetooth/hci0 ]; then
    echo "sp11-bt-addr: hci0 not found after 10s, giving up" >&2
    exit 0
fi

echo "sp11-bt-addr: setting MAC to $MAC" >&2
btmgmt --index 0 power off >/dev/null 2>&1 || true
echo "y" | btmgmt --index 0 public-addr "$MAC" >/dev/null 2>&1 || {
    echo "sp11-bt-addr: btmgmt failed, continuing with default MAC" >&2
    exit 0
}
echo "sp11-bt-addr: MAC set successfully" >&2
