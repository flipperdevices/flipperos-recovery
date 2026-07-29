################################################################################
#
# duperemove
#
################################################################################

DUPEREMOVE_VERSION = 0.15.2
DUPEREMOVE_SITE = $(call github,markfasheh,duperemove,v$(DUPEREMOVE_VERSION))
DUPEREMOVE_LICENSE = GPL-2.0
DUPEREMOVE_LICENSE_FILES = LICENSE

# 0.15+ links glib-2.0, sqlite3, libbsd and libxxhash (xxhash is no longer
# bundled), plus util-linux's blkid/mount/uuid - all found via pkg-config from
# the staging sysroot.
DUPEREMOVE_DEPENDENCIES = host-pkgconf sqlite libglib2 libbsd xxhash util-linux

# Plain Makefile. Pass VERSION explicitly (the github tarball has no .git, so its
# git-describe default would be empty) and the target pkg-config so the glib /
# sqlite / blkid / ... probes resolve against staging rather than the host.
define DUPEREMOVE_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) $(TARGET_CONFIGURE_OPTS) \
		VERSION=$(DUPEREMOVE_VERSION) PKG_CONFIG="$(PKG_CONFIG_HOST_BINARY)" -C $(@D)
endef

# Ship only the main tool (skip the btrfs-extent-same/hashstats helpers).
define DUPEREMOVE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/duperemove $(TARGET_DIR)/usr/bin/duperemove
endef

$(eval $(generic-package))
