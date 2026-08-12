################################################################################
#
# flipper-btrfs-tools
#
################################################################################

# Tracks the upstream dev branch by default. VERSION is overridable from the
# environment or the make command line, so a build can pin an exact commit:
#   make FLIPPER_BTRFS_TOOLS_VERSION=<sha>
# build.sh resolves the dev tip to a sha and passes it, so plain builds follow
# latest AND Buildroot actually rebuilds (the sha keys the build dir - a moving
# `dev` alone would stay cached and never rebuild).
FLIPPER_BTRFS_TOOLS_VERSION ?= dev
FLIPPER_BTRFS_TOOLS_SITE = https://github.com/flipperdevices/flipperos-btrfs-tools.git
FLIPPER_BTRFS_TOOLS_SITE_METHOD = git
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
