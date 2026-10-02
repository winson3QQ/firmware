#!/bin/sh
# pick-rootfs.sh <board> — print the path of the PRISTINE root.squashfs that is exactly the rootfs of
# the board's shipped mm6108-spi image (#209 S5). Every consumer — the A/B OTA payload, the flash-able
# card image, the stamp check — must use this one file, so card and OTA can never differ.
#
# Why not the obvious candidates (both have bitten us):
#  * build_dir/.../root.squashfs is the TARGET-GENERIC rootfs. With CONFIG_TARGET_PER_DEVICE_ROOTFS the
#    device's DEVICE_PACKAGES are NOT in it — a card built from it once shipped without morse/mm6108.bin
#    (HaLow dead, manet02 rescue, 2026-09-16). It is only "complete" today because mm6108only_diffconfig
#    forces those packages =y; a recipe change could silently bring that back.
#  * carving p2 out of the gunzipped sysupgrade .img.gz: the .img.gz can decompress a few hundred bytes
#    short, cutting the squashfs tail -> "VFS: Unable to mount root" kernel panic (2026-09-25, -268 B).
# The per-device rootfs is kept whole in build_dir as root.squashfs+pkg=<hash>. We identify WHICH file
# the image carries by its first 4 KiB (the squashfs superblock: bytes_used, mkfs_time, inode table
# offsets — unique per build), so even a truncated image identifies correctly, and we hand out the
# complete file, checked against its own superblock size.
set -eu
BOARD=${1:?usage: pick-rootfs.sh <board>}
case "$BOARD" in *bcm2711*) SUB=bcm2711 ;; *bcm2710*) SUB=bcm2710 ;; *) echo "pick-rootfs: unknown board $BOARD" >&2; exit 1 ;; esac
fail(){ echo "pick-rootfs: $*" >&2; exit 1; }
BT=bin/targets/bcm27xx/$SUB
IMGGZ=$(ls "$BT"/*mm6108-spi*squashfs-sysupgrade.img.gz 2>/dev/null | head -1)
[ -n "$IMGGZ" ] || fail "no mm6108-spi sysupgrade image in $BT (run from the firmware tree root after a build)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
gunzip -c "$IMGGZ" > "$T/d.img" 2>/dev/null || true      # exit 2 "trailing garbage" is expected
[ -s "$T/d.img" ] || fail "gunzip produced nothing from $IMGGZ"
lba=$(dd if="$T/d.img" bs=1 skip=470 count=4 2>/dev/null | od -An -tu4 | tr -d ' ')   # MBR entry 2 start
dd if="$T/d.img" of="$T/head" bs=512 skip="$lba" count=8 2>/dev/null
[ "$(head -c4 "$T/head")" = hsqs ] || fail "image p2 is not a squashfs"
pick=""
for f in build_dir/target-*/linux-bcm27xx_"$SUB"/root.squashfs*; do
	[ -f "$f" ] || continue
	if cmp -s -n 4096 "$T/head" "$f"; then
		[ -z "$pick" ] || cmp -s "$pick" "$f" || fail "two different files match the image header: $pick $f"
		pick=$f
	fi
done
[ -n "$pick" ] || fail "no build_dir root.squashfs* matches the image's rootfs (stale build_dir?)"
bu=$(dd if="$pick" bs=1 skip=40 count=8 2>/dev/null | od -An -tu8 | tr -d ' ')
sz=$(wc -c < "$pick" | tr -d ' ')
[ "$bu" = "$sz" ] || fail "$pick is $sz bytes but its superblock says bytes_used=$bu (incomplete)"
echo "$pick"
