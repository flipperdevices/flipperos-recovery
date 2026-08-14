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

# Pure shell tools, nothing to compile. Upstream groups them by kind, so libs/ goes
# to /usr/lib and scripts/ to /usr/local/sbin, both by directory rather than by name:
# the libs source each other and every tool exits if one of them is missing. The
# tools include migrate-profile: with `-d DEV` it targets the unmounted profiles
# partition from recovery, replays packages with the profile's own apt via chroot,
# and 3-way merges files with `git merge-file` (see BR2_PACKAGE_GIT). The hooks/
# plugins are dpkg kernel-install glue and do not apply, so they are not installed.
define FLIPPER_BTRFS_TOOLS_INSTALL_TARGET_CMDS
	for l in $(@D)/libs/*; do \
		$(INSTALL) -D -m 0644 "$$l" "$(TARGET_DIR)/usr/lib/$${l##*/}" ; \
	done
	for t in $(@D)/scripts/*; do \
		$(INSTALL) -D -m 0755 "$$t" "$(TARGET_DIR)/usr/local/sbin/$${t##*/}" ; \
	done
endef

$(eval $(generic-package))
