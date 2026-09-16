################################################################################
#
# flipper-btrfs-tools
#
################################################################################

# Pinned to a sha, and bumped like any other dependency. A branch name cannot
# work here: Buildroot keys both the download cache entry and the build directory
# on VERSION, so a literal `dev` is fetched once and then never re-fetched or
# rebuilt however far upstream moves. Override to test a revision:
#   make FLIPPER_BTRFS_TOOLS_VERSION=<sha>
FLIPPER_BTRFS_TOOLS_VERSION ?= de53dfb1524207548952aa58588896bd793a46a5
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
