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
# Embed a bootloader in the SD image:  UBOOT=/path/u-boot-rockchip.bin ./build.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

# buildroot stays at its pinned gitlink; the kernel (src/linux) and build-scripts
# follow their branches - `--remote` fetches the latest tip per .gitmodules
# (flipper-devel / dev). The Makefile then regenerates the monolithic kernel config
# for that kernel, so both track upstream automatically each build.
git submodule update --init buildroot
git submodule update --init --remote src/linux src/build-scripts

case "${1:-}" in
clean)     make clean ;;
distclean) make distclean ;;
"")        : ;;
*) echo "usage: $0 [clean|distclean]" >&2; exit 2 ;;
esac

make

echo "done -> output/images/"
