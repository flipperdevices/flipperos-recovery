################################################################################
#
# compsize
#
################################################################################

COMPSIZE_VERSION = 1.5
COMPSIZE_SITE = $(call github,kilobyte,compsize,v$(COMPSIZE_VERSION))
COMPSIZE_LICENSE = GPL-2.0-or-later
COMPSIZE_LICENSE_FILES = LICENSE

# compsize.c includes <btrfs/ioctl.h> and <btrfs/ctree.h>, which come from
# btrfs-progs' staged development headers.
COMPSIZE_DEPENDENCIES = btrfs-progs

# Plain Makefile honouring CC/CFLAGS/CPPFLAGS/LDFLAGS via TARGET_CONFIGURE_OPTS
# (the staging sysroot is baked into TARGET_CC, so <btrfs/*.h> resolves).
define COMPSIZE_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D)
endef

define COMPSIZE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/compsize $(TARGET_DIR)/usr/bin/compsize
endef

$(eval $(generic-package))
