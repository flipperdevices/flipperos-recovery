#!/bin/sh
# build.sh - thin convenience wrapper around the Buildroot-native build.
#
# All sources are pinned git submodules (buildroot, src/linux, src/build-scripts);
# this just makes sure they are checked out, then runs the toplevel Makefile, which
# forwards to Buildroot. Buildroot builds the toolchain, the monolithic kernel from
# src/linux (via override-srcdir), the initramfs, and - via post-image.sh - the
# flashable SD test image. Everything lands in output/images/.
#
#   ./build.sh              check out submodules, then build everything
#   ./build.sh clean        make clean first, then build
#   ./build.sh distclean    make distclean first (also drops output/), then build
#
# Embed a bootloader in the SD image:  UBOOT=/path/u-boot-rockchip.bin ./build.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

# submodules are pinned by gitlink (shallow per .gitmodules); a fresh clone builds
# without a manual `git submodule update`.
git submodule update --init --recursive

case "${1:-}" in
clean)     make clean ;;
distclean) make distclean ;;
"")        : ;;
*) echo "usage: $0 [clean|distclean]" >&2; exit 2 ;;
esac

make

echo "done -> output/images/"
