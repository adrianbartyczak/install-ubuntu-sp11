#!/usr/bin/env bash
#
# fix-wifi-firmware.sh
#
# Fixes the Wi-Fi firmware on a live Ubuntu system running on the Surface Pro 11.
#
# WiFi firmware is obtained, by default, straight from the Windows
# installation still sitting on disk (mounts the Windows partition and
# pulls the files out of the driver store). If that's not available, it
# falls back to downloading the files. You can instead force use of a
# local ./firmware-src/ directory with --local-firmware.
#
# Usage:
#   sudo ./fix-wifi-firmware.sh [options]
#
#   The options are actually optional. You don't need them to fix WiFi. Only use them
#   if you want to modify or adjust how the Windows fimrware is installed or if you
#   want to skip the Ath12k firmware build.
#
# Options:
#   --local-firmware        Use ./firmware-src/ instead of mounting Windows
#                            or downloading (you must populate it yourself
#                            with wlanfw20.mbn, phy_ucode20.elf, bdwlan.elf,
#                            and optionally regdb.bin).
#   --win-partition=DEV     Windows partition device (default: /dev/nvme0n1p3)
#   --win-mount=DIR         Mountpoint to use (default: /mnt/windows)
#   --skip-ath12k-build     Don't fetch kernel source / patch / build ath12k.ko
#                            (same as setting BUILD_ATH12K=false below)
#

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0"; exit 1; }

info() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="/root/install-ubuntu-sp11-workspace"
REPO_DIR="$WORK_DIR/install-ubuntu-sp11"
REPO_URL="https://github.com/adrianbartyczak/install-ubuntu-sp11.git"

FW_MODE="auto"                          # auto (mount+download) | local
FW_SRC_DIR="$SCRIPT_DIR/firmware-src"   # used only when FW_MODE=local
WINDOWS_PARTITION="/dev/nvme0n1p3"
WINDOWS_MOUNT_POINT="/mnt/windows"
WINDOWS_DRIVER_PATH="Windows/System32/DriverStore/FileRepository/qcwlanhmt8380.inf_arm64_f6c170edbe88d474"

BUILD_ATH12K="true"   # whether to fetch kernel source, patch, and build ath12k.ko

FW_BASE_URL="https://github.com/adrianbartyczak/install-ubuntu-sp11/raw/refs/heads/main/windows-firmware"
declare -A FW_URLS=(
    [wlanfw20.mbn]="$FW_BASE_URL/wlanfw20.mbn"
    [phy_ucode20.elf]="$FW_BASE_URL/phy_ucode20.elf"
    [bdwlan.elf]="$FW_BASE_URL/bdwlan.elf"
    [regdb.bin]="$FW_BASE_URL/regdb.bin"
)

for arg in "$@"; do
    case "$arg" in
        --local-firmware) FW_MODE="local" ;;
        --win-partition=*) WINDOWS_PARTITION="${arg#*=}" ;;
        --win-mount=*) WINDOWS_MOUNT_POINT="${arg#*=}" ;;
        --skip-ath12k-build) BUILD_ATH12K="false" ;;
        -h|--help)
            grep -E '^# ' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

KVER="$(uname -r)"
MOD_ROOT="/lib/modules/$KVER"
BUILD_TREE="$MOD_ROOT/build"

mkdir -p "$WORK_DIR"

# -- Step 0: Sanity checks --------------------------------------------------

if [ "$BUILD_ATH12K" = "true" ]; then
    if [ ! -d "$BUILD_TREE" ]; then
        warn "No kernel build tree at $BUILD_TREE"
        info "Install matching headers first, e.g.:"
        info "  apt-get install linux-headers-$KVER"
        exit 1
    fi

    apt-get install --yes make gcc flex bison bc libssl-dev libelf-dev dwarves cpio zstd

    for pkg in make gcc flex bison bc libssl-dev libelf-dev dwarves cpio zstd; do
        dpkg -s "$pkg" &>/dev/null || MISSING="$MISSING $pkg"
    done
    if [ -n "${MISSING:-}" ]; then
        info "Installing build dependencies:$MISSING"
        apt-get update -qq
        apt-get install -y -qq $MISSING
    fi
fi

if ! command -v git &>/dev/null; then
    apt-get update -qq
    apt-get install -y -qq git
fi

# -- Step 1: Fetch patches/overlay/firmware assets from the repo -----------

if [ ! -d "$REPO_DIR" ]; then
    info "Cloning patch repo ..."
    git clone --depth 1 "$REPO_URL" "$REPO_DIR"
else
    info "Updating patch repo ..."
    git -C "$REPO_DIR" pull --ff-only
fi

PATCHES_DIR="$REPO_DIR/other-data/patches"

# -- Step 1b: Acquire WiFi firmware -----------------------------------------
#
# Default: pull straight from the Windows install's driver store. Any file
# not found there gets downloaded individually. --local-firmware skips both
# and just uses whatever's already in $FW_SRC_DIR.

FW_STAGING="$WORK_DIR/firmware-staged"
mkdir -p "$FW_STAGING"

if [ "$FW_MODE" = "local" ]; then
    info "Using local firmware directory: $FW_SRC_DIR"
    if [ ! -d "$FW_SRC_DIR" ]; then
        warn "No firmware-src/ directory found next to this script."
        warn "Create $FW_SRC_DIR and drop in wlanfw20.mbn, phy_ucode20.elf,"
        warn "bdwlan.elf and (optionally) regdb.bin before re-running."
    fi
    for f in wlanfw20.mbn phy_ucode20.elf bdwlan.elf regdb.bin; do
        [ -f "$FW_SRC_DIR/$f" ] && cp "$FW_SRC_DIR/$f" "$FW_STAGING/$f"
    done
else
    WINDOWS_MOUNT_POINTED_HERE=0
    if [ ! -b "$WINDOWS_PARTITION" ]; then
        warn "Windows partition $WINDOWS_PARTITION not found, skipping mount step."
    else
        mkdir -p "$WINDOWS_MOUNT_POINT"

        # Make sure we have some way to read NTFS: either the in-kernel
        # ntfs3 driver or the ntfs-3g FUSE driver.
        if ! modprobe ntfs3 2>/dev/null && ! command -v ntfs-3g &>/dev/null; then
            info "No NTFS driver available, installing ntfs-3g ..."
            apt-get update -qq
            apt-get install -y -qq ntfs-3g
        fi

        if mountpoint -q "$WINDOWS_MOUNT_POINT"; then
            info "$WINDOWS_MOUNT_POINT is already mounted, using it as-is."
        else
            info "Mounting $WINDOWS_PARTITION on $WINDOWS_MOUNT_POINT (read-only) ..."
            if mount -t ntfs3 -o ro "$WINDOWS_PARTITION" "$WINDOWS_MOUNT_POINT" 2>/dev/null \
               || mount -t ntfs-3g -o ro "$WINDOWS_PARTITION" "$WINDOWS_MOUNT_POINT" 2>/dev/null \
               || mount -o ro "$WINDOWS_PARTITION" "$WINDOWS_MOUNT_POINT" 2>/dev/null; then
                WINDOWS_MOUNT_POINTED_HERE=1
            else
                warn "Failed to mount $WINDOWS_PARTITION (need ntfs-3g installed?)."
            fi
        fi

        if mountpoint -q "$WINDOWS_MOUNT_POINT"; then
            DRIVER_DIR="$WINDOWS_MOUNT_POINT/$WINDOWS_DRIVER_PATH"
            if [ -d "$DRIVER_DIR" ]; then
                info "Found driver store at $DRIVER_DIR"
                for f in wlanfw20.mbn phy_ucode20.elf bdwlan.elf regdb.bin; do
                    if [ -f "$DRIVER_DIR/$f" ]; then
                        cp "$DRIVER_DIR/$f" "$FW_STAGING/$f"
                        echo "  Copied $f from Windows driver store"
                    fi
                done
            else
                warn "Driver store path not found on Windows partition:"
                warn "  $WINDOWS_DRIVER_PATH"
            fi
        fi

        if [ "$WINDOWS_MOUNT_POINTED_HERE" -eq 1 ]; then
            umount "$WINDOWS_MOUNT_POINT" || warn "Could not unmount $WINDOWS_MOUNT_POINT"
        fi
    fi

    # Download anything still missing after the mount attempt
    for f in wlanfw20.mbn phy_ucode20.elf bdwlan.elf regdb.bin; do
        if [ ! -f "$FW_STAGING/$f" ]; then
            info "Downloading $f ..."
            if wget -q --timeout=60 "${FW_URLS[$f]}" -O "$FW_STAGING/$f.tmp"; then
                mv "$FW_STAGING/$f.tmp" "$FW_STAGING/$f"
            else
                rm -f "$FW_STAGING/$f.tmp"
                warn "Failed to download $f from ${FW_URLS[$f]}"
            fi
        fi
    done
fi

FW_SRC_DIR="$FW_STAGING"

# -- Step 2: Get ath12k kernel source matching the running kernel ----------

if [ "$BUILD_ATH12K" = "true" ]; then

# KBASE_VER="$(echo "$KVER" | sed -E 's/-.*//')"   # e.g. 7.0.0-22-qcom-x1e -> 7.0.0
KBASE_VER="7.0.1"   # hardcoded kernel source version to fetch
KMAJOR="$(echo "$KBASE_VER" | cut -d. -f1)"
TARBALL="$WORK_DIR/linux.tar.xz"
KSRC_DIR="$WORK_DIR/kernel-source"

rm -rf "$KSRC_DIR"

# This is a downstream Ubuntu Concept / Qualcomm kernel (qcom-x1e), which
# ships its own ath12k_wifi7 fork that does NOT exist in vanilla kernel.org
# source under any version number. apt source (the actual PPA package) is
# therefore the only correct source and is tried first; kernel.org is kept
# only as a last-resort fallback for non-Concept kernels.
info "Fetching kernel source via apt-get source for $KVER ..."
apt-get update -qq

RESOLUTE_LIST="/etc/apt/sources.list.d/resolute-source.list"
if ! apt-get source -qq "linux-image-$KVER" 2>/dev/null; then
    if [ ! -f "$RESOLUTE_LIST" ]; then
        info "Adding deb-src for the Ubuntu Concept resolute PPA ..."
        echo "deb-src https://ppa.launchpadcontent.net/ubuntu-concept/x1e/ubuntu resolute main" \
            > "$RESOLUTE_LIST"
        apt-get update -qq
    fi
    apt-get source -qq "linux-image-$KVER" 2>/dev/null || true
fi

EXTRACTED=$(find "$WORK_DIR" -maxdepth 1 -type d -name "linux-*" ! -name "kernel-source" | head -1)
if [ -n "$EXTRACTED" ]; then
    mv "$EXTRACTED" "$KSRC_DIR"
    info "Got downstream kernel source via apt: $KSRC_DIR"
else
    warn "apt source failed (no deb-src available for this exact version)."
    info "Falling back to kernel.org source for v$KBASE_VER (won't contain"
    info "the ath12k_wifi7 fork if this is a Concept kernel) ..."
    set +e
    wget -q --timeout=60 \
        "https://cdn.kernel.org/pub/linux/kernel/v${KMAJOR}.x/linux-${KBASE_VER}.tar.xz" \
        -O "$TARBALL"
    DL_OK=$?
    set -e
    if [ $DL_OK -eq 0 ] && [ -s "$TARBALL" ]; then
        mkdir -p "$KSRC_DIR"
        tar -xJf "$TARBALL" -C "$WORK_DIR"
        EXTRACTED=$(find "$WORK_DIR" -maxdepth 1 -type d -name "linux-${KBASE_VER}*" | head -1)
        [ -n "$EXTRACTED" ] && { rm -rf "$KSRC_DIR"; mv "$EXTRACTED" "$KSRC_DIR"; }
        rm -f "$TARBALL"
    fi
fi

ATH12K_SRC="$KSRC_DIR/drivers/net/wireless/ath/ath12k"
if [ ! -d "$ATH12K_SRC" ]; then
    echo "ath12k source not found in $KSRC_DIR"
    exit 1
fi
info "ath12k source: $ATH12K_SRC"

# -- Step 3: Apply the WiFi patches -----------------------------------------

if grep -q "disable-rfkill" "$ATH12K_SRC/core.c" 2>/dev/null; then
    info "WiFi patches already present, skipping ..."
else
    info "Applying WiFi patches to ath12k ..."
    for p in "$PATCHES_DIR"/0002-*.patch "$PATCHES_DIR"/0004-*.patch; do
        [ -f "$p" ] || continue
        echo "  $(basename "$p")"
        patch -d "$KSRC_DIR" -p1 < "$p"
    done
fi

# -- Step 4: Build ONLY ath12k against the running kernel's build tree ------

info "Building patched ath12k module against $BUILD_TREE ..."
make -C "$BUILD_TREE" M="$ATH12K_SRC" modules

BUILT_KO=$(find "$ATH12K_SRC" -name "*.ko" | head -1)
[ -n "$BUILT_KO" ] || { echo "Build failed: no .ko produced"; exit 1; }
BUILT_VERMAGIC=$(modinfo -F vermagic "$BUILT_KO" 2>/dev/null || echo "unknown")
info "Built module vermagic: $BUILT_VERMAGIC (running kernel: $KVER)"

# -- Step 5: Install the patched module into the live module tree ----------

MOD_DIR=$(find "$MOD_ROOT" -type d -name "ath12k" | head -1)
[ -n "$MOD_DIR" ] || { echo "ath12k module directory not found under $MOD_ROOT"; exit 1; }

info "Backing up original modules to ${MOD_DIR}.orig ..."
[ -d "${MOD_DIR}.orig" ] || cp -r "$MOD_DIR" "${MOD_DIR}.orig"

# Match whatever compression the distro already uses for this module tree
if find "$MOD_DIR" -name '*.ko.zst' | grep -q .; then
    COMPRESS=zstd
elif find "$MOD_DIR" -name '*.ko.xz' | grep -q .; then
    COMPRESS=xz
else
    COMPRESS=none
fi
info "Existing module compression: $COMPRESS"

for ko in "$ATH12K_SRC"/*.ko "$ATH12K_SRC"/wifi7/*.ko; do
    [ -f "$ko" ] || continue
    rel="${ko#$ATH12K_SRC/}"
    target="$MOD_DIR/$rel"
    mkdir -p "$(dirname "$target")"
    rm -f "${target}" "${target}.zst" "${target}.xz"
    case "$COMPRESS" in
        zstd) zstd -f --quiet "$ko" -o "${target}.zst" ;;
        xz)   xz -f -k -c "$ko" > "${target}.xz" ;;
        *)    cp "$ko" "$target" ;;
    esac
    echo "  Installed $rel"
done

info "Running depmod ..."
depmod -a "$KVER"

else
    info "BUILD_ATH12K=false, skipping kernel source fetch/patch/build/install ..."
fi

# -- Step 6: Install WiFi firmware ------------------------------------------

FW_DIR="/lib/firmware/ath12k/WCN7850/hw2.0"
mkdir -p "$FW_DIR"
FW_MISSING=0

install_fw() {
    local src="$1" dest="$2" required="${3:-1}"
    if [ -f "$FW_SRC_DIR/$src" ]; then
        cp "$FW_SRC_DIR/$src" "$FW_DIR/$dest"
        info "Installed $src as $dest"
    elif [ "$required" -eq 1 ]; then
        warn "$src not found (checked Windows partition + download), skipping"
        FW_MISSING=1
    fi
}

install_fw wlanfw20.mbn amss.bin
install_fw phy_ucode20.elf m3.bin
install_fw bdwlan.elf board.bin
install_fw regdb.bin regdb.bin 0   # optional

[ "$FW_MISSING" -ne 0 ] && warn "Some firmware files were missing — WiFi may not come up."

# -- Step 7: Kernel cmdline tweaks (efi=novamap + audio blacklist) ---------

GRUB_DEFAULT="/etc/default/grub"
EXTRA_CMDLINE="efi=novamap module_blacklist=snd_sof_qcom_x1e,snd_soc_qcom_common,qc_adsp_pas"

if [ -f "$GRUB_DEFAULT" ]; then
    if grep -q "efi=novamap" "$GRUB_DEFAULT"; then
        info "GRUB cmdline already patched, skipping ..."
    else
        info "Updating $GRUB_DEFAULT ..."
        cp "$GRUB_DEFAULT" "${GRUB_DEFAULT}.bak"
        sed -i -E "s/^(GRUB_CMDLINE_LINUX_DEFAULT=\")([^\"]*)(\")/\1\2 ${EXTRA_CMDLINE}\3/" "$GRUB_DEFAULT"
        update-grub
        info "GRUB updated. A reboot is required for this to take effect."
    fi
else
    warn "$GRUB_DEFAULT not found — set efi=novamap and the module_blacklist"
    warn "manually via your bootloader config."
fi

# Note: the original script's "Goldilocks Maneuver" (swapping the Microsoft
# shim for full GRUB in the ISO's EFI boot image) is a live-boot-media
# workaround. An already-installed system's ESP is normally set up correctly
# by the installer, so it's skipped here. If you hit boot issues, see:
# https://github.com/linux-surface/linux-surface/discussions/2128

# -- Step 8: Reload the driver and unblock rfkill ---------------------------

info "Reloading ath12k ..."
modprobe -r ath12k_wifi7 2>/dev/null || true
modprobe -r ath12k 2>/dev/null || true
modprobe ath12k || warn "modprobe ath12k failed — check dmesg"
modprobe ath12k_wifi7 2>/dev/null || true
rfkill unblock all 2>/dev/null || true
sleep 2

LOADED_FILE=$(modinfo -F filename $(modinfo -n ath12k 2>/dev/null) 2>/dev/null || true)
if [ "$BUILD_ATH12K" = "true" ] && [ -n "${MOD_DIR:-}" ]; then
    case "$LOADED_FILE" in
        "$MOD_DIR"/*) info "Confirmed: loaded ath12k module is the patched build ($LOADED_FILE)" ;;
        *) warn "Loaded ath12k module is $LOADED_FILE — NOT the freshly patched"
           warn "one in $MOD_DIR. Hard-block will persist until this is fixed." ;;
    esac
fi

WIFI_DT_NODE=$(find /sys/firmware/devicetree/base -maxdepth 6 -type d -iname 'wifi@*' 2>/dev/null | head -1)
if [ -n "$WIFI_DT_NODE" ]; then
    if [ -e "$WIFI_DT_NODE/disable-rfkill" ]; then
        info "devicetree: disable-rfkill property IS present on $WIFI_DT_NODE"
    else
        warn "devicetree: no disable-rfkill property on $WIFI_DT_NODE"
        warn "The driver patch alone can't help if the DTB never sets this —"
        warn "hard-block will persist until the DTB itself carries the property."
    fi
fi

echo ""
info "Done. Check WiFi with: sudo /debug-wifi.sh"
info "rfkill state:"
rfkill list
echo ""
info "A reboot is recommended so the GRUB cmdline changes take effect:"
echo "  sudo reboot"
echo ""
