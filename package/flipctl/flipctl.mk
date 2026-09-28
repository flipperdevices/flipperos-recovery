################################################################################
#
# flipctl
#
################################################################################
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Flipper FZCO

# Pinned to a sha, like every other source here: a branch name would keep
# Buildroot's version-keyed download cache and build directory forever, so it
# would never pick up a new commit. Override to test a different revision:
#   make FLIPCTL_VERSION=<sha>
FLIPCTL_VERSION ?= 4f2934c072f4849bf16fa599157a853eff8666c3
FLIPCTL_SITE = https://github.com/flipperdevices/flipctl-slint.git
FLIPCTL_SITE_METHOD = git

# The binary is a workspace member and cargo cannot install from a virtual
# manifest, so the build happens in its own directory. The workspace root still
# supplies [profile.release].
FLIPCTL_SUBDIR = bin/flipctl

# What the image builds (build-flipctl.sh in flipperone-linux-build-scripts) less
# wayland and gpu: recovery hosts no apps, so there is no sway, no EGL and no
# AppImage code in the binary.
FLIPCTL_CARGO_BUILD_OPTS = --features device,slint,remote

# The binary statically links Slint, whose GPL-3.0-only terms govern it; see
# flipper-boot-menu in flipperos-boot-menu for the full reasoning. A stable copy
# of the text lives in this package dir so legal-info always captures it.
FLIPCTL_LICENSE = \
	GPL-3.0-only (whole binary: statically links Slint), \
	MIT (our source, Busy9px font), \
	CC-BY-SA-3.0 (HaxrCorp 4090 font), \
	Unlicense (Born2bSportyV2 font)
FLIPCTL_LICENSE_FILES = \
	GPL-3.0-only.txt \
	LICENSES/MIT.txt \
	third_party/flipctl-fonts/HaxrCorp4090-FlipCTL/LICENSE \
	third_party/flipctl-fonts/Busy9px-FlipCTL/LICENSE \
	third_party/flipctl-fonts/Born2bSportyV2-FlipCTL/LICENSE

define FLIPCTL_STAGE_GPL_TEXT
	$(INSTALL) -m 0644 $(FLIPCTL_PKGDIR)/GPL-3.0-only.txt $(FLIPCTL_DIR)/
endef
FLIPCTL_POST_PATCH_HOOKS += FLIPCTL_STAGE_GPL_TEXT

# Install what the build step made. The generic step runs `cargo install`, which
# compiles the whole binary a second time. The workspace root owns target/.
#
# Then the rest of the layout build-flipctl.sh stages, from the same files in the
# repository: the browser view's assets, the unit and what it needs in place to
# start. Plus the repository's recovery drop-in, which runs the unit as root and
# orders it after the panel's card, and the rule that makes the card a unit.
FLIPCTL_PROFILE_DIR = $(if $(BR2_ENABLE_DEBUG),debug,release)
define FLIPCTL_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/target/$(RUSTC_TARGET_NAME)/$(FLIPCTL_PROFILE_DIR)/flipctl \
		$(TARGET_DIR)/usr/bin/flipctl
	mkdir -p $(TARGET_DIR)/usr/share/flipctl/assets
	cp -a $(@D)/crates/flipper-ui/assets/remote $(TARGET_DIR)/usr/share/flipctl/assets/
	$(INSTALL) -D -m 0644 $(@D)/systemd/flipctl.service \
		$(TARGET_DIR)/usr/lib/systemd/system/flipctl.service
	$(INSTALL) -D -m 0644 $(@D)/systemd/flipctl-recovery.conf \
		$(TARGET_DIR)/usr/lib/systemd/system/flipctl.service.d/50-recovery.conf
	$(INSTALL) -D -m 0644 $(@D)/systemd/flipctl.sysusers.conf \
		$(TARGET_DIR)/usr/lib/sysusers.d/flipctl.conf
	$(INSTALL) -D -m 0644 $(@D)/systemd/70-flipctl-devices.rules \
		$(TARGET_DIR)/usr/lib/udev/rules.d/70-flipctl-devices.rules
	$(INSTALL) -D -m 0644 $(@D)/systemd/flipctl-recovery.rules \
		$(TARGET_DIR)/usr/lib/udev/rules.d/70-flipctl-recovery.rules
	$(INSTALL) -D -m 0644 $(@D)/systemd/flipctl-devices.conf \
		$(TARGET_DIR)/usr/lib/modules-load.d/flipctl-devices.conf
endef

FLIPCTL_DEPENDENCIES = host-pkgconf

$(eval $(cargo-package))
