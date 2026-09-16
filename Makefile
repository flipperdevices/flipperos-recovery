# Toplevel Makefile - out-of-tree Buildroot build for the FlipperOS recovery
# initramfs. Every target is forwarded to the vendored Buildroot tree, built
# out-of-tree (O=) with this directory attached as the BR2_EXTERNAL tree.
#
#   make                 configure (if needed) + build the initramfs
#   make regen-defconfig regenerate the committed kernel defconfig (out-of-band)
#   make menuconfig      tweak the config   |  make savedefconfig  save it back
#   make clean|distclean |  make <pkg>-rebuild  |  ... any Buildroot target
#   O=<dir>              override the output directory (default: ./output)
#
# Result artifacts land in $(O)/images/: rootfs.cpio{,.zst}, vmlinuz, config,
# System.map, dtbs/ and - unless SD_IMAGE=0 - recovery.img{,.zst}.

BR2_EXTERNAL := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
O            ?= $(BR2_EXTERNAL)/output

# Keep Buildroot's download cache out of the vendored tree and persist it
# across runs and across `make distclean`.
BR2_DL_DIR   ?= $(BR2_EXTERNAL)/dl
export BR2_DL_DIR

BR_MAKE       = $(MAKE) -C $(BR2_EXTERNAL)/buildroot O=$(O) BR2_EXTERNAL=$(BR2_EXTERNAL)

# Buildroot is the only submodule left. Check it out on demand, so a plain clone
# builds with `make` and there is no wrapper script to read first.
BR_MAKEFILE   = $(BR2_EXTERNAL)/buildroot/Makefile

$(BR_MAKEFILE):
	git -C $(BR2_EXTERNAL) submodule update --init buildroot

# Default build: load the defconfig on first use, then build. The monolithic
# kernel config is a committed artifact, so a build only ever consumes it.
.DEFAULT_GOAL := all
all: | $(BR_MAKEFILE)
	@test -f $(O)/.config || $(BR_MAKE) flipperos_recovery_defconfig
	@$(BR_MAKE)

# Regenerate that committed kernel defconfig. Occasional and out-of-band: run it
# when the kernel or the config fragments move, review the diff, commit. It fails
# loudly if a driver refuses to build in, so the monolithic kernel can never
# silently drop one - now at review time, where the diff is visible.
# An explicit rule, so the catch-all below does not forward it to Buildroot.
regen-defconfig:
	@$(BR2_EXTERNAL)/scripts/regen-defconfig.sh

.PHONY: all regen-defconfig

# Forward every other target straight to Buildroot.
%: | $(BR_MAKEFILE)
	@$(BR_MAKE) $@
