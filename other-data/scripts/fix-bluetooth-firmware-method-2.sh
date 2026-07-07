#!/usr/bin/env bash
# 
# fix-bluetooth-firmware-method-2.sh
# 
# This is the second method for fixing the Bluetooth firmware. It attempts to assign
# a MAC address to your Bluetooth interface at boot using the "btmgmt" command.
# 

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0"; exit 1; }

info() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="/root/install-ubuntu-sp11-sp11-workspace"
REPO_DIR="/root/install-ubuntu-sp11"
REPO_URL="https://github.com/adrianbartyczak/install-ubuntu-sp11.git"

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            grep -E '^# ' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

mkdir -p "$WORK_DIR"

# -- Step 0: Sanity checks --------------------------------------------------

if ! command -v git &>/dev/null; then
    apt-get update -qq
    apt-get install -y -qq git
fi

# -- Step 1: Fetch system file assets from the repo -----------

if [ ! -d "$REPO_DIR" ]; then
    info "Cloning patch repo ..."
    git clone --depth 1 "$REPO_URL" "$REPO_DIR"
#else
#    info "Updating patch repo ..."
#    git -C "$REPO_DIR" pull --ff-only
fi

SYSTEM_FILES_DIR="$REPO_DIR/other-data/system-files"

# -- Step 2: Install system files -------------

if [ -d "$SYSTEM_FILES_DIR" ]; then
    info "Installing system files files ..."
    cp -r "$SYSTEM_FILES_DIR"/. /
    [ -f /usr/local/sbin/sp11-bt-addr.sh ] && chmod +x /usr/local/sbin/sp11-bt-addr.sh
    if [ -f /usr/lib/systemd/system/sp11-bt-addr.service ]; then
        systemctl daemon-reload
        systemctl enable sp11-bt-addr.service
        info "Enabled sp11-bt-addr.service"
    fi
else
    warn "system-files/ directory not found in repo checkout, skipping system files install"
fi

echo ""
info "Checking if sp11-bt-addr.service is enabled:"
systemctl status sp11-bt-addr.service
echo ""

# -- Step 9: Unblock rfkill all wireless devices ---------------------------

rfkill unblock all 2>/dev/null || true

echo ""
info "Done. Check Bluetooth"
info "A reboot is recommended:"
echo "  sudo reboot"
echo ""
