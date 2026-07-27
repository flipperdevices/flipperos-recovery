#!/bin/sh
# post-image.sh - assemble a flashable SD test image with genimage (native).
#
# Buildroot runs this after the images are built. It stages a BLS boot tree
# (kernel Image + dtb + initrd + loader entry) and hands it to genimage, which
# builds the ext4 boot partition and wraps it in a GPT disk. The device's U-Boot
# 'bls' bootmeth finds /boot/loader/entries/recovery.conf and boots it; the
# initramfs is the whole recovery OS (runs from RAM), so there is no rootfs
# partition. This is a TEST convenience: 512-byte sectors (SD cards); the final
# UFS-LU flash is the device's Falcon path, not this image.
#
# Env (all optional):
#   UBOOT=/path/u-boot-rockchip.bin  embed the Rockchip loader at sector 64 so the
#                                    SD boots standalone; omit if the on-device
#                                    U-Boot already scans the SD.
#   DTB_NAME=<file>   dtb in $BINARIES_DIR         (default rk3576-flipper-one-rev-f0b0c1.dtb)
#   PART_MIB=<n>      boot partition size, MiB     (default 256)
#   KVER=<v>          version shown in the BLS entry
#   CMDLINE=<args>    kernel command line
set -eu

BINARIES_DIR="${1:-${BINARIES_DIR:?}}"
BUILD_DIR="${BUILD_DIR:-$BINARIES_DIR/../build}"
HOST_DIR="${HOST_DIR:-$BINARIES_DIR/../host}"

: "${DTB_NAME:=rk3576-flipper-one-rev-f0b0c1.dtb}"
: "${PART_MIB:=256}"
: "${KVER:=7.2.0}"
# Defaults to AP-setup mode (no recovery.wifi token); add recovery.wifi.country=<CC>
# (AP) | recovery.wifi=sta | recovery.wifi=off to change it.
: "${CMDLINE:=console=ttyS0,1500000n8 console=tty1 rdinit=/init}"
: "${UBOOT:=}"

IMAGE="$BINARIES_DIR/Image"
DTB="$BINARIES_DIR/$DTB_NAME"
INITRD="$BINARIES_DIR/rootfs.cpio.zst"
for f in "$IMAGE" "$DTB" "$INITRD"; do
	[ -f "$f" ] || { echo "post-image: input not found: $f" >&2; exit 1; }
done

# --- stage the BLS boot tree (paths are relative to the ext4 partition root;
#     recovery is a plain ext4 partition, no btrfs subvolumes). The DTB goes in a
#     'devicetreedir' so U-Boot selects it by the board fdtfile name. ---
BOOT="$BUILD_DIR/recovery-boot"
rm -rf "$BOOT"
mkdir -p "$BOOT/boot/loader/entries" "$BOOT/boot/dtb/rockchip"
cp "$IMAGE"  "$BOOT/boot/Image"
cp "$DTB"    "$BOOT/boot/dtb/rockchip/$DTB_NAME"
cp "$INITRD" "$BOOT/boot/rootfs.cpio.zst"
cat > "$BOOT/boot/loader/entries/recovery.conf" <<EOF
# Boot Loader Specification type#1 entry (FlipperOS Recovery)
title         FlipperOS Recovery
version       ${KVER}-recovery
sort-key      recovery
options       ${CMDLINE}
linux         /boot/Image
devicetreedir /boot/dtb
initrd        /boot/rootfs.cpio.zst
EOF

# --- genimage config: ext4 boot partition + GPT disk. The loader partition (the
#     Rockchip U-Boot at sector 64 / offset 32K) is included only when UBOOT is
#     set. The root partition starts at 64MiB, leaving room for the loader. ---
loader_part=""
if [ -n "$UBOOT" ]; then
	[ -f "$UBOOT" ] || { echo "post-image: UBOOT not found: $UBOOT" >&2; exit 1; }
	cp "$UBOOT" "$BINARIES_DIR/u-boot-rockchip.bin"
	loader_part='
	partition loader {
		image = "u-boot-rockchip.bin"
		offset = 32K
		in-partition-table = false
	}'
fi

CFG="$BUILD_DIR/genimage-recovery.cfg"
cat > "$CFG" <<EOF
image boot.ext4 {
	ext4 {
		label = "recovery"
		use-mke2fs = true
	}
	size = ${PART_MIB}M
}

image recovery.img {
	hdimage {
		partition-table-type = "gpt"
	}
${loader_part}
	partition root {
		partition-type-uuid = "B921B045-1DF0-41C3-AF44-4C6F280D3FAE"
		image = "boot.ext4"
		offset = 64M
		bootable = "true"
	}
}
EOF

# genimage builds the ext4 from --rootpath (our staged boot tree), then the GPT.
GENIMAGE_TMP="$BUILD_DIR/genimage.tmp"
rm -rf "$GENIMAGE_TMP"
"$HOST_DIR/bin/genimage" \
	--rootpath "$BOOT" \
	--tmppath "$GENIMAGE_TMP" \
	--inputpath "$BINARIES_DIR" \
	--outputpath "$BINARIES_DIR" \
	--config "$CFG"

# compress the raw image (what you flash); keep the raw too.
zstd -q -f -T0 "$BINARIES_DIR/recovery.img" -o "$BINARIES_DIR/recovery.img.zst"

echo "post-image: wrote recovery.img (+ .zst) in images/"
if [ -z "$UBOOT" ]; then
	echo "post-image: no UBOOT embedded - boots only where U-Boot already scans the SD;"
	echo "            re-run with UBOOT=/path/u-boot-rockchip.bin for a standalone SD."
fi
