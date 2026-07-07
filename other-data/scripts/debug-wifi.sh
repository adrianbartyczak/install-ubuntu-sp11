#!/usr/bin/env bash
#
# debug-wifi.sh — Surface Pro 11 ath12k WiFi diagnostic
#
# Run on the booted SP11 to diagnose WiFi issues.
# Usage: sudo ./debug-wifi.sh
#
set -euo pipefail

B="\033[1m"
R="\033[0m"
G="\033[1;32m"
Y="\033[1;33m"
RED="\033[1;31m"

section() { printf "\n${B}=== %s ===${R}\n" "$*"; }
ok()      { printf "  ${G}[OK]${R} %s\n" "$*"; }
warn()    { printf "  ${Y}[!]${R}  %s\n" "$*"; }
fail()    { printf "  ${RED}[X]${R} %s\n" "$*"; }

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0"
    exit 1
fi

section "Firmware files"
FW_DIR="/lib/firmware/ath12k/WCN7850/hw2.0"
if [ -d "$FW_DIR" ]; then
    for f in amss.bin m3.bin board.bin board-2.bin regdb.bin; do
        if [ -f "$FW_DIR/$f" ]; then
            sz=$(stat -c%s "$FW_DIR/$f" 2>/dev/null || stat -f%z "$FW_DIR/$f" 2>/dev/null || echo "?")
            ok "$f ($sz bytes)"
        else
            warn "$f — missing"
        fi
    done
else
    fail "Firmware directory not found: $FW_DIR"
fi

section "ath12k module"
if lsmod | grep -q ath12k; then
    ok "ath12k loaded"
    modinfo ath12k 2>/dev/null | grep -E "^(filename|version|vermagic|firmware):" | while read -r line; do
        printf "  %s\n" "$line"
    done
else
    fail "ath12k not loaded — trying modprobe"
    modprobe ath12k 2>&1 || true
fi

# Check for wifi7 submodule
if lsmod | grep -q ath12k_wifi7; then
    ok "ath12k_wifi7 loaded"
else
    warn "ath12k_wifi7 not loaded"
fi

section "Network interfaces"
ip link show 2>/dev/null | grep -E "wlan|wlp|ath" || warn "No wireless interfaces found"

section "rfkill"
if command -v rfkill &>/dev/null; then
    rfkill list 2>/dev/null || warn "rfkill: no devices"
else
    warn "rfkill not installed (apt install rfkill)"
fi

section "dmesg: ath12k (last 50 lines)"
dmesg | grep -i "ath12k\|qmi\|wcn7850\|wifi" | tail -50 || warn "No ath12k messages in dmesg"

section "dmesg: firmware errors"
dmesg | grep -iE "firmware|qmi.*fail|board.*data|timeout|-110|-2 " | tail -20 || warn "No firmware errors found"

section "QMI board data status"
if dmesg | grep -q "qmi failed to load board data"; then
    fail "QMI board data transfer FAILED"
    echo ""
    echo "  Likely cause: firmware version mismatch"
    echo "  Ensure amss.bin, m3.bin, and bdwlan.elf all come from the"
    echo "  same Windows driver store directory."
    echo ""
    echo "  To enable QMI debug logging:"
    echo "    sudo modprobe -r ath12k"
    echo "    sudo modprobe ath12k debug_mask=0x40000"
    echo "    dmesg | grep ath12k"
elif dmesg | grep -q "board data"; then
    ok "Board data appears to have loaded"
else
    warn "No board data messages found — module may not have initialized"
fi

section "PCI device"
if command -v lspci &>/dev/null; then
    lspci -nn | grep -i "network\|wireless\|qualcomm\|ath" || warn "No WiFi PCI device found"
else
    warn "lspci not installed (apt install pciutils)"
fi

echo ""
printf "${B}Diagnostic complete.${R}\n"
