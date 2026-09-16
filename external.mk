include $(sort $(wildcard $(BR2_EXTERNAL_FLIPPEROS_RECOVERY_PATH)/package/*/*.mk))

# Stage the kernel artifacts under the names the rest of the Flipper tooling
# already uses (build-kernel-mainline.sh produces the same set for the mainline
# kernel): a gzipped vmlinuz, the effective config and System.map beside it, and
# the device trees under dtbs/<vendor>/. Buildroot leaves System.map and .config
# behind in the kernel build directory and installs the dtbs flat, so without
# this anything consuming images/ has to reach into $(O)/build/ and reshape the
# result by hand.
#
# pkg-generic runs the POST_INSTALL_IMAGES hooks after the package's own
# INSTALL_IMAGES_CMDS and dereferences the variable when the recipe runs, so
# appending from here - included after linux/linux.mk - works.
#
# Which device trees to publish. One recovery image should boot any RK3576
# Flipper One revision, not only the board BR2_LINUX_KERNEL_INTREE_DTS_NAME
# happens to name, and the overlays have to be on the image for add-dtbo to
# apply them - so publish the whole RK3576 set.
FLIPPEROS_RECOVERY_DTB_DIR  = $(LINUX_ARCH_PATH)/boot/dts/rockchip
FLIPPEROS_RECOVERY_DTB_GLOB = rk3576-*

# Buildroot only builds the DTBs named in the config. Build the arch's full
# dtbs target instead, so the other revisions, the overlays, and the composed
# base+overlay DTBs the rockchip Makefile defines (which have no .dts of their
# own, so they cannot be found by globbing sources) all get built. Only
# CONFIG_ARCH_ROCKCHIP is enabled, so this builds the rockchip trees and no
# other vendor's.
define FLIPPEROS_RECOVERY_BUILD_ALL_DTBS
	$(LINUX_MAKE_ENV) $(BR2_MAKE) $(LINUX_MAKE_FLAGS) -C $(LINUX_DIR) dtbs
endef
LINUX_POST_BUILD_HOOKS += FLIPPEROS_RECOVERY_BUILD_ALL_DTBS

define FLIPPEROS_RECOVERY_STAGE_KERNEL_IMAGES
	mv -f $(BINARIES_DIR)/$(notdir $(LINUX_IMAGE_NAME)) $(BINARIES_DIR)/vmlinuz
	$(INSTALL) -D -m 0644 $(LINUX_DIR)/System.map $(BINARIES_DIR)/System.map
	$(INSTALL) -D -m 0644 $(LINUX_DIR)/.config $(BINARIES_DIR)/config
	rm -rf $(BINARIES_DIR)/dtbs
	for f in $(FLIPPEROS_RECOVERY_DTB_DIR)/$(FLIPPEROS_RECOVERY_DTB_GLOB).dtb \
	         $(FLIPPEROS_RECOVERY_DTB_DIR)/$(FLIPPEROS_RECOVERY_DTB_GLOB).dtbo; do \
		if [ -f "$$f" ]; then \
			$(INSTALL) -D -m 0644 "$$f" \
				"$(BINARIES_DIR)/dtbs/rockchip/$${f##*/}" ; \
		fi ; \
	done
	rm -f $(foreach dtb,$(LINUX_DTBS),$(BINARIES_DIR)/$(notdir $(dtb)))
endef
LINUX_POST_INSTALL_IMAGES_HOOKS += FLIPPEROS_RECOVERY_STAGE_KERNEL_IMAGES
