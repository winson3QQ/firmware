#!/bin/sh
# check-image-manifest.sh — refuse to ship an image whose package manifest lacks what a Batman node
# needs to stay reachable after it is flashed or OTA'd (#209 S4-6, the 1.4.12 lesson).
#
#   check-image-manifest.sh <manifest> <board>      board = ekh-bcm2711 | ekh-bcm2710
#
# Why these packages: a node is reached over HaLow (mm6108 driver + firmware) and set up through the
# onboard Wi-Fi (brcmfmac + the 43455 firmware/NVRAM, Pi 4 and Pi 3A+ alike). 1.4.12 shipped without
# kmod-brcmfmac: morse slid from radio1 to radio0 and an OTA stranded a seeded node, and batman-
# autocommit's service-level health gate committed it anyway. Only the BUILT manifest is trustworthy
# (a .config "=m" line does not mean the package is in the image). Exit 0 = OK, 1 = refuse.
set -eu
MAN=${1:-}; BOARD=${2:-}
[ -f "$MAN" ] && [ -n "$BOARD" ] || { echo "usage: check-image-manifest.sh <manifest> <board>" >&2; exit 1; }

need="kmod-brcmfmac cypress-firmware-43455-sdio brcmfmac-nvram-43455-sdio kmod-mm6108 mm6108-firmware batman-provision"
forbid="kmod-mm8108 mm8108-firmware"        # conflicts with mm6108 in one rootfs (#201 build notes)
case "$BOARD" in
	*bcm2711*) soc=bcm2711 ;;
	*bcm2710*) soc=bcm2710 ;;
	*) echo "check-image-manifest: board '$BOARD' names no known SoC" >&2; exit 1 ;;
esac
# OTS golden only belongs on the Pi 4 (512 MB Pi 3A+, #209 D6); the Docker engine is optional on both.
if grep -q '^batman-payload-host ' "$MAN"; then
	[ "$soc" = bcm2711 ] && need="$need batman-payload-ots"
	[ "$soc" = bcm2710 ] && forbid="$forbid batman-payload-ots"
fi

# Exact versions of the mesh core (#247): routing openwrt-24.10 batman-adv/batctl, OpenMANET alfred;
# and runc 1.3.6 (#247-2: container-escape CVEs fixed in >= 1.3.3 / 1.3.6).
# Exact, not "contains 2024.3": routing master's 2024.3-r7 (11 patches) must not pass for -r13 (101).
# Bump together with the routing pin / kernel version (the kmod version carries the kernel's).
exact="kmod-batman-adv=6.6.138.2024.3-r13 batctl-full=2024.3-r5 alfred=2025.5-r1 runc=1.3.6-r1"

bad=0
for e in $exact; do
	p=${e%%=*}; v=${e#*=}
	got=$(sed -n "s/^$p - //p" "$MAN" | head -1)
	[ "$got" = "$v" ] || { echo "check-image-manifest: $p is '${got:-absent}', want '$v'" >&2; bad=1; }
done
for p in $need; do
	grep -q "^$p " "$MAN" || { echo "check-image-manifest: MISSING $p (required on $soc)" >&2; bad=1; }
done
for p in $forbid; do
	grep -q "^$p " "$MAN" && { echo "check-image-manifest: FORBIDDEN $p present on $soc" >&2; bad=1; }
done
[ "$bad" = 0 ] || { echo "check-image-manifest: REFUSING $MAN for $BOARD" >&2; exit 1; }
echo "check-image-manifest: $BOARD ($soc) OK — $(echo $need | wc -w) required packages present, none forbidden, mesh core exact ($exact)"
