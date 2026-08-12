################################################################################
#
# flipper-btrfs-tools
#
################################################################################

# Nominal upstream: a github tarball of the dev branch. In this tree the source
# is always taken from the src/btrfs-tools submodule via
# FLIPPER_BTRFS_TOOLS_OVERRIDE_SRCDIR (local.mk), so this is never fetched - it
# only pins a coherent fallback and lets the override rsync then rebuild on
# change, the same follow-latest wiring the kernel uses.
FLIPPER_BTRFS_TOOLS_VERSION = dev
FLIPPER_BTRFS_TOOLS_SITE = $(call github,flipperdevices,flipperos-btrfs-tools,$(FLIPPER_BTRFS_TOOLS_VERSION))
FLIPPER_BTRFS_TOOLS_LICENSE = MIT
FLIPPER_BTRFS_TOOLS_LICENSE_FILES = LICENSE

# Pure shell tools, nothing to compile. Install the two helpers the tools source
# into /usr/lib, then every profile/snapshot tool into /usr/local/sbin.
# migrate-profile is skipped (needs dpkg/apt/git the recovery does not carry);
# the etc/kernel/install.d hooks are dpkg kernel-install glue and do not apply.
define FLIPPER_BTRFS_TOOLS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/usr/lib/flipper-btrfs.sh $(TARGET_DIR)/usr/lib/flipper-btrfs.sh
	$(INSTALL) -D -m 0644 $(@D)/usr/lib/flipper-bls.sh $(TARGET_DIR)/usr/lib/flipper-bls.sh
	for t in $(@D)/usr/local/sbin/*; do \
		case "$${t##*/}" in migrate-profile) continue ;; esac ; \
		$(INSTALL) -D -m 0755 "$$t" "$(TARGET_DIR)/usr/local/sbin/$${t##*/}" ; \
	done
endef

$(eval $(generic-package))
