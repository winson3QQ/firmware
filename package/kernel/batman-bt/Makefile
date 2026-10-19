# Batman #254: the node's Bluetooth stack, LE only — the on-board CYW43455 BT over the mini UART
# (dtoverlay=miniuart-bt, serdev child node "bluetooth" under uart1, driver hci_bcm via hci_uart).
#
# Why not OpenWrt's kmod-bluetooth (package/kernel/linux/modules/other.mk): it hard-codes
# CONFIG_BT_HCIUART_BCM=n (so the Pi's UART BT never probes), BT_BREDR=y, and bundles RFCOMM/BNEP/HIDP/btusb
# — attack surface a headless mesh node never uses. This package is the single owner of the BT kernel
# config: CONFLICTS with kmod-bluetooth, and the board diffconfig deselects kmod-bluetooth so the two
# KCONFIG sets never merge (they contradict each other).
#
# CONFIG_SERIAL_DEV_CTRL_TTYPORT=y is what makes the 8250 mini UART a serdev controller; without it
# ttyS0 stays a plain tty and hci_bcm has nothing to bind to (verified missing on 1.5.12: /sys/bus/serial
# empty, /sys/class/tty/ttyS0 present). It is a built-in bool -> changes the kernel image, not a module.
# Design: docs/design/254-stage1-impl.md §4.6 (winson3QQ/Batman).

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=batman-bt
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0

include $(INCLUDE_DIR)/package.mk

define KernelPackage/batman-bt
  SUBMENU:=Other modules
  TITLE:=Batman Bluetooth LE stack (hci_uart + btbcm, no BR/EDR)
  DEPENDS:=+kmod-crypto-hash +kmod-crypto-ecb +kmod-lib-crc16 +kmod-crypto-cmac +kmod-regmap-core +kmod-crypto-ecdh
  CONFLICTS:=kmod-bluetooth
  KCONFIG:= \
	CONFIG_BT \
	CONFIG_BT_BREDR=n \
	CONFIG_BT_LE=y \
	CONFIG_BT_LE_L2CAP_ECRED=y \
	CONFIG_BT_DEBUGFS=n \
	CONFIG_BT_MSFTEXT=n \
	CONFIG_BT_AOSPEXT=n \
	CONFIG_BT_RFCOMM=n \
	CONFIG_BT_BNEP=n \
	CONFIG_BT_HIDP=n \
	CONFIG_BT_HCIBTUSB=n \
	CONFIG_BT_HCIBTSDIO=n \
	CONFIG_BT_HCIUART \
	CONFIG_BT_HCIUART_SERDEV=y \
	CONFIG_BT_HCIUART_H4=y \
	CONFIG_BT_HCIUART_BCM=y \
	CONFIG_BT_HCIUART_NOKIA=n \
	CONFIG_BT_HCIUART_BCSP=n \
	CONFIG_BT_HCIUART_ATH3K=n \
	CONFIG_BT_HCIUART_LL=n \
	CONFIG_BT_HCIUART_3WIRE=n \
	CONFIG_BT_HCIUART_INTEL=n \
	CONFIG_BT_HCIUART_RTL=n \
	CONFIG_BT_HCIUART_QCA=n \
	CONFIG_BT_HCIUART_AG6XX=n \
	CONFIG_BT_HCIUART_MRVL=n \
	CONFIG_BT_BCM \
	CONFIG_SERIAL_DEV_CTRL_TTYPORT=y
  FILES:= \
	$(LINUX_DIR)/net/bluetooth/bluetooth.ko \
	$(LINUX_DIR)/drivers/bluetooth/btbcm.ko \
	$(LINUX_DIR)/drivers/bluetooth/hci_uart.ko
  AUTOLOAD:=$(call AutoProbe,bluetooth btbcm hci_uart)
endef

define KernelPackage/batman-bt/description
 Bluetooth LE only (BR/EDR compiled out): bluetooth core, btbcm (CYW43455 patchram loader,
 needs brcm/BCM4345C0.hcd from brcm-bt-firmware-4345c0) and hci_uart with the Broadcom serdev
 protocol. No RFCOMM/BNEP/HIDP/USB. Batman #254 phone-app provisioning transport.
endef

# in-kernel modules only: nothing to build here
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef
define Build/Compile
endef

$(eval $(call KernelPackage,batman-bt))
