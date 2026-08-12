#!/bin/sh
# build.sh - thin convenience wrapper around the Buildroot-native build.
#
# buildroot is pinned; the kernel (src/linux) and build-scripts follow their
# branches (flipper-devel / dev), so this fetches their latest tips. The toplevel
# Makefile regenerates the monolithic kernel config for that kernel, then Buildroot
# builds the toolchain, the kernel (via override-srcdir), the initramfs, and - via
# post-image.sh - the flashable SD test image, all into output/images/.
#
#   ./build.sh              check out submodules, then build everything
#   ./build.sh clean        make clean first, then build
#   ./build.sh distclean    make distclean first (also drops output/), then build
#
# Each source follows its branch by default; pin an exact commit via env:
#   KERNEL_REF=<ref> BUILD_SCRIPTS_REF=<ref> FLIPPER_BTRFS_TOOLS_VERSION=<sha> ./build.sh
# Embed a bootloader in the SD image:  UBOOT=/path/u-boot-rockchip.bin ./build.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

# buildroot stays at its pinned gitlink. The kernel (src/linux) and build-scripts
# follow their branches by default - `--remote` fetches the latest tip per
# .gitmodules (flipper-devel / dev) - or pin an exact commit with KERNEL_REF /
# BUILD_SCRIPTS_REF. The Makefile then regenerates the monolithic kernel config for
# whatever kernel is checked out, so it tracks upstream automatically each build.
git submodule update --init buildroot

# $1 = submodule path, $2 = override ref (empty -> follow the branch tip)
sync_sub() {
	if [ -n "$2" ]; then
		git submodule update --init "$1"
		git -C "$1" fetch -q --depth 1 origin "$2"
		git -C "$1" checkout -q FETCH_HEAD
	else
		git submodule update --init --remote "$1"
	fi
}
sync_sub src/linux "${KERNEL_REF:-}"
sync_sub src/build-scripts "${BUILD_SCRIPTS_REF:-}"

# btrfs tools are a versioned Buildroot package (not a submodule): resolve the
# flipperos-btrfs-tools dev tip to a commit sha and pass it as the package
# VERSION. This makes plain builds follow latest AND actually rebuild - Buildroot
# keys the build dir on VERSION, so a fresh sha triggers a re-fetch and rebuild
# where a moving `dev` alone would stay cached. Override by presetting it:
#   FLIPPER_BTRFS_TOOLS_VERSION=<sha> ./build.sh
if [ -z "${FLIPPER_BTRFS_TOOLS_VERSION:-}" ]; then
	FLIPPER_BTRFS_TOOLS_VERSION=$(git ls-remote https://github.com/flipperdevices/flipperos-btrfs-tools.git dev 2>/dev/null | awk 'NR==1{print $1}')
	[ -n "$FLIPPER_BTRFS_TOOLS_VERSION" ] || FLIPPER_BTRFS_TOOLS_VERSION=dev
fi
export FLIPPER_BTRFS_TOOLS_VERSION

case "${1:-}" in
clean)     make clean ;;
distclean) make distclean ;;
"")        : ;;
*) echo "usage: $0 [clean|distclean]" >&2; exit 2 ;;
esac

make

echo "done -> output/images/"
