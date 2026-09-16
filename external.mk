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
define FLIPPEROS_RECOVERY_STAGE_KERNEL_IMAGES
	mv -f $(BINARIES_DIR)/$(notdir $(LINUX_IMAGE_NAME)) $(BINARIES_DIR)/vmlinuz
	$(INSTALL) -D -m 0644 $(LINUX_DIR)/System.map $(BINARIES_DIR)/System.map
	$(INSTALL) -D -m 0644 $(LINUX_DIR)/.config $(BINARIES_DIR)/config
	$(foreach dtb,$(LINUX_DTBS), \
		$(INSTALL) -D -m 0644 \
			$(or $(wildcard $(LINUX_ARCH_PATH)/boot/dts/$(dtb)),$(LINUX_ARCH_PATH)/boot/$(dtb)) \
			$(BINARIES_DIR)/dtbs/$(dtb)
	)
	rm -f $(foreach dtb,$(LINUX_DTBS),$(BINARIES_DIR)/$(notdir $(dtb)))
endef
LINUX_POST_INSTALL_IMAGES_HOOKS += FLIPPEROS_RECOVERY_STAGE_KERNEL_IMAGES
