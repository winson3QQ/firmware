# Batman #254: Bluetooth patchram firmware for the Raspberry Pi 4 on-board CYW43455 (BCM4345C0).
# OpenWrt ships the WiFi half (cypress-firmware-43455-sdio: brcmfmac43455-sdio.bin/.clm_blob) but no
# .hcd; btbcm.c looks for brcm/BCM4345C0.raspberrypi,4-model-b.hcd then brcm/BCM4345C0.hcd.
# Source: RPi-Distro/bluez-firmware (branch pios/trixie) debian/firmware/broadcom/BCM4345C0.hcd,
# redistributed under LICENSE.cypress (same binary-redistribution licence as the WiFi blobs);
# the file is vendored here with its sha256 pinned so the image is reproducible offline.

include $(TOPDIR)/rules.mk

PKG_NAME:=brcm-bt-firmware
PKG_RELEASE:=1
PKG_LICENSE:=Cypress-binary
PKG_LICENSE_FILES:=files/LICENSE.cypress

include $(INCLUDE_DIR)/package.mk

HCD_SHA256:=$(shell cat ./files/BCM4345C0.hcd.sha256 2>/dev/null | cut -d' ' -f1)

define Package/brcm-bt-firmware-4345c0
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=CYW43455 (BCM4345C0) Bluetooth patchram firmware
  PKGARCH:=all
endef

define Build/Compile
	# refuse to package a blob that is not the one we reviewed
	echo "$(HCD_SHA256)  ./files/BCM4345C0.hcd" | sha256sum -c -
endef

define Package/brcm-bt-firmware-4345c0/install
	$(INSTALL_DIR) $(1)/lib/firmware/brcm
	$(INSTALL_DATA) ./files/BCM4345C0.hcd $(1)/lib/firmware/brcm/BCM4345C0.hcd
	$(INSTALL_DIR) $(1)/usr/share/licenses/brcm-bt-firmware
	$(INSTALL_DATA) ./files/LICENSE.cypress $(1)/usr/share/licenses/brcm-bt-firmware/LICENSE.cypress
endef

$(eval $(call BuildPackage,brcm-bt-firmware-4345c0))
