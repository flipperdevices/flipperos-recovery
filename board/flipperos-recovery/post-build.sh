#!/bin/sh
# Runs after packages are installed and the overlay is copied, before the image
# is packed. Buildroot exports TARGET_DIR (also passed as $1).
set -eu

TARGET="${TARGET_DIR:-${1:?target directory not provided}}"

# --- Capture the recovery repo's git version at build time (like the main OS's
#     BUILD_GIT). Falls back to "unknown" until this tree is a git repo. ---
REPO="${BR2_EXTERNAL_FLIPPEROS_RECOVERY_PATH:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}"
# describe without --dirty, then append -dirty for any edit to the recovery tree.
# Every source is pinned in a tracked file now, so an edit anywhere here - the
# buildroot gitlink included - genuinely changes what the image is.
GIT_VERSION=$(git -C "$REPO" describe --tags --always 2>/dev/null || true)
GIT_VERSION=${GIT_VERSION:-unknown}
if [ "$GIT_VERSION" != unknown ] \
   && ! git -C "$REPO" diff --quiet HEAD 2>/dev/null; then
	GIT_VERSION="$GIT_VERSION-dirty"
fi
# Provenance: the exact sources this image was built from, so every image is
# self-describing even when someone overrides a version on the command line.
# Versioned packages carry their sha in Buildroot's version-keyed build directory
# name, which is the sha that was actually built whether it came from the .mk
# default or an override on the command line.
pkg_git() {
	v=$(basename "$(ls -d "${BUILD_DIR:-$(dirname "$TARGET")/build}/$1-"* 2>/dev/null | head -n1)" 2>/dev/null | sed "s/^$1-//")
	printf %s "${v:-unknown}" | cut -c1-12
}
# The kernel is pinned in the config Buildroot is building from (exported as
# BR2_CONFIG), which is the one place that decides which commit gets built.
KERNEL_GIT=$(sed -n 's/^BR2_LINUX_KERNEL_CUSTOM_REPO_VERSION="\(.*\)"$/\1/p' \
	"${BR2_CONFIG:-${O:-$(dirname "$TARGET")}/.config}" 2>/dev/null || true)
KERNEL_GIT=$(printf %s "${KERNEL_GIT:-unknown}" | cut -c1-12)
BUILD_SCRIPTS_GIT=$(pkg_git flipper-usb-gadget)
BTRFS_TOOLS_GIT=$(pkg_git flipper-btrfs-tools)
FLIPCTL_GIT=$(pkg_git flipctl)
BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)

# --- Brand the OS identity (Buildroot writes a generic Buildroot os-release
#     earlier in target-finalize; overwrite it here). /etc/os-release is a
#     symlink to this file. recovery-banner sources these (BUILD_GIT etc.). ---
cat > "$TARGET/usr/lib/os-release" <<EOF
NAME="FlipperOS Recovery"
ID=flipperos-recovery
PRETTY_NAME="FlipperOS Recovery"
ANSI_COLOR="1;31"
VERSION="$GIT_VERSION"
VERSION_ID="$GIT_VERSION"
BUILD_GIT="$GIT_VERSION"
KERNEL_GIT="$KERNEL_GIT"
BUILD_SCRIPTS_GIT="$BUILD_SCRIPTS_GIT"
BTRFS_TOOLS_GIT="$BTRFS_TOOLS_GIT"
FLIPCTL_GIT="$FLIPCTL_GIT"
BUILD_DATE="$BUILD_DATE"
EOF

# USB-gadget files are the flipper-usb-gadget package, and btrfs profile/snapshot
# tooling the flipper-btrfs-tools package; neither is synced here.

# --- Trim files no package flag removes ---
# glibc's vectorized-math library: copied in as part of the C runtime, but
# nothing in the image links it and libm does not depend on it (~216 KB).
rm -f "$TARGET"/lib/libmvec.so* "$TARGET"/usr/lib/libmvec.so*

# btrfs-progs debug/recovery-internals tools the recovery flow never runs.
# btrfs-progs has no Buildroot sub-option to install a subset, so purge them
# here. Kept: mkfs.btrfs, the btrfs multi-tool, btrfsck/fsck.btrfs, btrfs-convert.
for t in btrfs-image btrfstune btrfs-select-super btrfs-map-logical \
         btrfs-find-root btrfs-corrupt-block; do
	rm -f "$TARGET/usr/bin/$t" "$TARGET/usr/sbin/$t" "$TARGET/sbin/$t"
done

# systemd units that don't apply to this recovery. Removing the unit files (this
# script runs BEFORE `systemctl preset-all`) keeps preset warning-free - masking
# would only trade the warning for "Failed to preset unit: ... is masked". These
# never ran anyway: NetworkManager's dracut-initrd helpers are WantedBy=initrd.target
# (we run systemd as real PID 1, no initrd.target), nvme-cli's NVMe-over-Fabrics
# autoconnect units have nothing to connect to on a recovery box, and ifupdown-scripts'
# network.service runs ifup/ifdown (absent; NetworkManager owns the interfaces).
for u in NetworkManager-initrd NetworkManager-config-initrd NetworkManager-wait-online-initrd \
         nvmf-autoconnect nvmefc-boot-connections network; do
	rm -f "$TARGET/usr/lib/systemd/system/$u.service" "$TARGET/etc/systemd/system/$u.service"
done

# NetworkManager connection profile permissions are set declaratively, in
# board/flipperos-recovery/device_table.txt (BR2_ROOTFS_DEVICE_TABLE).

echo "post-build: branded os-release, removed unused libmvec + btrfs debug tools + N/A systemd units"
