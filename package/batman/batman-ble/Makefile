# Batman #254: BLE platform glue for the phone-app provisioning transport (PR-F spike).
# Owns the three files the bluez package deliberately no longer installs (board patch 0012):
#   /etc/bluetooth/main.conf          LE only, no bonding, RPA privacy (BlueZ 5.72 keys only)
#   /etc/dbus-1/system.d/bluetooth.conf  default DENY (upstream allows every local uid to drive org.bluez)
#   /etc/init.d/bluetoothd            respawn, BlueZ store 0700 on tmpfs, starts after dbus (60)
# No conffiles: main.conf must come from the image (a restored backup must not undo SecureConnections=only).
# Lives in the firmware tree for the spike; final home is the Batman feed (docs/design/254-stage1-impl.md §4.6).

include $(TOPDIR)/rules.mk

PKG_NAME:=batman-ble
PKG_VERSION:=0.1.0
PKG_RELEASE:=2
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/batman-ble
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Batman BLE platform (bluetoothd config, dbus policy, service)
  DEPENDS:=+bluez-daemon +kmod-batman-bt +brcm-bt-firmware-4345c0 +dbus
  PKGARCH:=all
endef

define Build/Prepare
endef
define Build/Compile
endef

define Package/batman-ble/install
	$(INSTALL_DIR) $(1)/etc/bluetooth $(1)/etc/dbus-1/system.d $(1)/etc/init.d
	$(INSTALL_DATA) ./files/main.conf $(1)/etc/bluetooth/main.conf
	$(INSTALL_DATA) ./files/bluetooth.conf $(1)/etc/dbus-1/system.d/bluetooth.conf
	$(INSTALL_BIN) ./files/bluetoothd.init $(1)/etc/init.d/bluetoothd
endef

$(eval $(call BuildPackage,batman-ble))
