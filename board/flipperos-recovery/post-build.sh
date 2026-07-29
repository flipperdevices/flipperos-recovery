#!/bin/sh
# Runs after packages are installed and the overlay is copied, before the image
# is packed. Buildroot exports TARGET_DIR (also passed as $1).
set -eu

TARGET="${TARGET_DIR:-${1:?target directory not provided}}"

# --- Capture the recovery repo's git version at build time (like the main OS's
#     BUILD_GIT). Falls back to "unknown" until this tree is a git repo. ---
REPO="${BR2_EXTERNAL_FLIPPEROS_RECOVERY_PATH:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}"
GIT_VERSION=$(git -C "$REPO" describe --tags --always --dirty 2>/dev/null || true)
GIT_VERSION=${GIT_VERSION:-unknown}
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
BUILD_DATE="$BUILD_DATE"
EOF

# --- USB-gadget files: pulled from the build-scripts submodule (not vendored, so
#     they track the main OS) straight into the target. The composite gadget is
#     auto-started by the enable symlink committed in the overlay; the other
#     variants' units are deliberately NOT copied - their [Install] lines would let
#     preset-all enable them and race for the single UDC. ---
BS="$REPO/src/build-scripts/overlays"
if [ -d "$BS" ]; then
	install -d "$TARGET/usr/local/bin" "$TARGET/usr/lib/systemd/system" \
	           "$TARGET/etc/systemd/network" "$TARGET/etc/udev/rules.d"
	# gadget engine + preset launcher scripts (manual tools; extras are harmless)
	install -m 0755 "$BS"/usr/local/bin/usb-*.sh "$TARGET/usr/local/bin/"
	# only the two units recovery uses: the composite + the Type-C replug helper
	install -m 0644 "$BS"/configs/systemd/system/usb-ncm-msc-mtp-gadget.service \
	                "$BS"/configs/systemd/system/usb-gadget-reconnect.service \
	                "$TARGET/usr/lib/systemd/system/"
	# flipusb0 rename link + udev rules (90 re-manages flipusb0 in NM by MAC; 91 replug)
	install -m 0644 "$BS"/configs/systemd/network/10-flipusb.link "$TARGET/etc/systemd/network/"
	install -m 0644 "$BS"/configs/udev/rules.d/90-flipusb-managed.rules \
	                "$BS"/configs/udev/rules.d/91-usb-gadget-reconnect.rules \
	                "$TARGET/etc/udev/rules.d/"
else
	echo "post-build: WARNING - build-scripts submodule missing, USB gadget files NOT installed" >&2
fi

# --- btrfs profile/snapshot tooling (build-scripts submodule): create/delete/
#     rename profiles, snapshot send/receive/delete, maintenance, and show-space -
#     run against the internal btrfs from recovery (their -d mode targets the
#     unmounted profiles partition). Deps are already in the image (btrfs-progs,
#     compsize, duperemove, findmnt, flock, mawk). migrate-profile is EXCLUDED: it
#     needs dpkg/apt/git that a Buildroot recovery does not (and should not) carry;
#     flipper-accountdb.awk is its helper only, so it is skipped too. ---
if [ -d "$BS/usr/local/sbin" ]; then
	install -d "$TARGET/usr/local/sbin" "$TARGET/usr/lib"
	for t in "$BS"/usr/local/sbin/*; do
		[ -f "$t" ] || continue
		case "${t##*/}" in migrate-profile) continue ;; esac
		install -m 0755 "$t" "$TARGET/usr/local/sbin/"
	done
	# shared helpers the tools source (flipper-accountdb.awk is migrate-only, skipped)
	install -m 0644 "$BS"/usr/lib/flipper-btrfs.sh "$BS"/usr/lib/flipper-bls.sh "$TARGET/usr/lib/"
fi

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

# --- NetworkManager ignores connection profiles that are group/world readable.
#     git preserves only the exec bit, not the overlay's 0600, so a fresh clone
#     ships these 0644 and the AP + bridges never come up. Force 0600 here. ---
chmod 600 "$TARGET"/etc/NetworkManager/system-connections/*.nmconnection 2>/dev/null || true

echo "post-build: branded os-release, synced USB gadget + btrfs profile tools, removed unused libmvec + btrfs debug tools + N/A systemd units, fixed NM connection perms"
