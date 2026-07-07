#!/usr/bin/env bash
#
# get-bluetooth-mac-addr.sh
#
# Get the physical MAC address of the Bluetooth device.
#

EFI_VAR_PATH=$(compgen -G "/sys/firmware/efi/efivars/MacAddressEmulationAddress-*" | head -n1)
if [ -z "$EFI_VAR_PATH" ]; then
    echo "[+] MacAddressEmulationAddress EFI variable not found"
    exit 1
fi

# Skip the 4-byte attribute header, read the remaining 6 bytes as raw MAC
MAC_HEX=$(xxd -p -s 4 "$EFI_VAR_PATH" | tr -d '\n')
MAC=$(echo "$MAC_HEX" | sed -E 's/(..)/\1:/g; s/:$//' | tr 'a-f' 'A-F')

echo $MAC