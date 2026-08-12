# Buildroot override file (BR2_PACKAGE_OVERRIDE_FILE points here).
#
# Build the kernel and its uapi headers from the pinned src/linux submodule
# instead of downloading. The defconfig sets BR2_LINUX_KERNEL_CUSTOM_GIT and
# BR2_KERNEL_HEADERS_CUSTOM_GIT nominally; these overrides make both packages use
# the local checkout (same commit, no fetch). Buildroot rsyncs the srcdir per build.
LINUX_OVERRIDE_SRCDIR = $(BR2_EXTERNAL_FLIPPEROS_RECOVERY_PATH)/src/linux
LINUX_HEADERS_OVERRIDE_SRCDIR = $(BR2_EXTERNAL_FLIPPEROS_RECOVERY_PATH)/src/linux
