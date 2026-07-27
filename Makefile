# Toplevel Makefile - out-of-tree Buildroot build for the FlipperOS recovery
# initramfs. Every target is forwarded to the vendored Buildroot tree, built
# out-of-tree (O=) with this directory attached as the BR2_EXTERNAL tree.
#
#   make                 configure (if needed) + build the initramfs
#   make menuconfig      tweak the config   |  make savedefconfig  save it back
#   make clean|distclean |  make <pkg>-rebuild  |  ... any Buildroot target
#   O=<dir>              override the output directory (default: ./output)
#
# Result images land in $(O)/images/: rootfs.cpio and rootfs.cpio.zst

BR2_EXTERNAL := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
O            ?= $(BR2_EXTERNAL)/output

# Keep Buildroot's download cache out of the vendored tree and persist it
# across runs and across `make distclean`.
BR2_DL_DIR   ?= $(BR2_EXTERNAL)/dl
export BR2_DL_DIR

BR_MAKE       = $(MAKE) -C $(BR2_EXTERNAL)/buildroot O=$(O) BR2_EXTERNAL=$(BR2_EXTERNAL)

# Default build: load the defconfig on first use, then let Buildroot build.
.DEFAULT_GOAL := all
all:
	@test -f $(O)/.config || $(BR_MAKE) flipperos_recovery_defconfig
	@$(BR_MAKE)

# Forward every other target straight to Buildroot.
%:
	@$(BR_MAKE) $@
