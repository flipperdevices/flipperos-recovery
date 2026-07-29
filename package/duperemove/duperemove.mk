################################################################################
#
# duperemove
#
################################################################################

DUPEREMOVE_VERSION = 0.14.1
DUPEREMOVE_SITE = $(call github,markfasheh,duperemove,v$(DUPEREMOVE_VERSION))
DUPEREMOVE_LICENSE = GPL-2.0, BSD-2-Clause (bundled xxhash)
DUPEREMOVE_LICENSE_FILES = LICENSE LICENSE.xxhash

# libsqlite3 for the hashfile DB; pkg-config (host-pkgconf) resolves it from the
# staging sysroot. xxhash is bundled in-tree.
DUPEREMOVE_DEPENDENCIES = sqlite host-pkgconf

# Plain Makefile honouring CC/CFLAGS/LDFLAGS via TARGET_CONFIGURE_OPTS; it calls
# pkg-config for sqlite3, so pass the target-configured binary.
define DUPEREMOVE_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) $(TARGET_CONFIGURE_OPTS) \
		PKG_CONFIG="$(PKG_CONFIG_HOST_BINARY)" -C $(@D)
endef

# Ship only the main tool (skip the btrfs-extent-same/hashstats helpers).
define DUPEREMOVE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/duperemove $(TARGET_DIR)/usr/bin/duperemove
endef

$(eval $(generic-package))
