################################################################################
#
# flipper-usb-gadget
#
################################################################################
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Flipper FZCO

# The USB-gadget files live in the main OS's build-scripts repository, so
# recovery and the main OS drive the same gadget. Pinned to a sha, like every
# other source here: a branch name would keep Buildroot's version-keyed download
# cache and build directory forever, so it would never pick up a new commit.
# Override to test a different revision:
#   make FLIPPER_USB_GADGET_VERSION=<sha>
FLIPPER_USB_GADGET_VERSION ?= f4d9acc8391e620612baf6b46a077b991d9ed81d
FLIPPER_USB_GADGET_SITE = https://github.com/flipperdevices/flipperone-linux-build-scripts.git
FLIPPER_USB_GADGET_SITE_METHOD = git
# Upstream ships no LICENSE file and no SPDX headers, so there is nothing to
# collect for legal-info; it is a Flipper-internal repository.
FLIPPER_USB_GADGET_LICENSE = PROPRIETARY

# Pure shell, units and rules - nothing to compile. Only the pieces recovery
# uses: the composite gadget is auto-started by the enable symlink committed in
# the board overlay, and the other presets' units are deliberately NOT installed
# because their [Install] lines would let preset-all enable them and race for the
# single UDC. The preset *scripts* are harmless as manual tools, so the whole
# usb-*.sh set comes along with the engine.
define FLIPPER_USB_GADGET_INSTALL_TARGET_CMDS
	for s in $(@D)/overlays/usr/local/bin/usb-*.sh; do \
		$(INSTALL) -D -m 0755 "$$s" "$(TARGET_DIR)/usr/local/bin/$${s##*/}" ; \
	done
	$(INSTALL) -D -m 0644 $(@D)/overlays/configs/systemd/system/usb-ncm-msc-mtp-gadget.service \
		$(TARGET_DIR)/usr/lib/systemd/system/usb-ncm-msc-mtp-gadget.service
	$(INSTALL) -D -m 0644 $(@D)/overlays/configs/systemd/system/usb-gadget-reconnect.service \
		$(TARGET_DIR)/usr/lib/systemd/system/usb-gadget-reconnect.service
	$(INSTALL) -D -m 0644 $(@D)/overlays/configs/systemd/network/10-flipusb.link \
		$(TARGET_DIR)/etc/systemd/network/10-flipusb.link
	$(INSTALL) -D -m 0644 $(@D)/overlays/configs/udev/rules.d/90-flipusb-managed.rules \
		$(TARGET_DIR)/etc/udev/rules.d/90-flipusb-managed.rules
	$(INSTALL) -D -m 0644 $(@D)/overlays/configs/udev/rules.d/91-usb-gadget-reconnect.rules \
		$(TARGET_DIR)/etc/udev/rules.d/91-usb-gadget-reconnect.rules
endef

$(eval $(generic-package))
