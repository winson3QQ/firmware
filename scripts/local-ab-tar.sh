#!/bin/sh
# local-ab-tar.sh — after a local (WSL) OpenWrt build, assemble the batman A/B sysupgrade tar
# for the mm6108-spi board from the built whole-disk image, fully rootless. Pi 4 (ekh-bcm2711, the
# default) or Pi 3A+ (ekh-bcm2710, #209).
#
# Mirrors the verified CI carve (build-firmware.yml / fast-build.yml): parse the MBR, carve the
# p2 squashfs by its own bytes_used, extract the p1 boot FAT with mtools (no loop-mount / no root),
# then hand both to the batman feed's build-ab-payload.sh. The result is a `sysupgrade -n`-able
# A/B tar dropped next to the images in bin/targets, exactly like the CI artifact.
#
#   local-ab-tar.sh [<firmware_top>] [<board>]
#
# <firmware_top> defaults to $PWD (run it from the firmware tree root, or after `make`).
# <board> defaults to ekh-bcm2711. Before packing, the built manifest must pass
# scripts/check-image-manifest.sh (brcmfmac/43455, mm6108, batman packages — the 1.4.12 lesson).
set -eu

TOP=${1:-$PWD}
BOARD=${2:-ekh-bcm2711}
case "$BOARD" in *bcm2711*) SUB=bcm2711 ;; *bcm2710*) SUB=bcm2710 ;; *) echo "unknown board $BOARD" >&2; exit 1 ;; esac
BT="$TOP/bin/targets/bcm27xx/$SUB"
PAYLOAD_SH="$TOP/feeds/batman/scripts/build-ab-payload.sh"

[ -d "$BT" ] || { echo "no bin/targets dir: $BT — run a build first" >&2; exit 1; }
[ -f "$PAYLOAD_SH" ] || { echo "build-ab-payload.sh not found: $PAYLOAD_SH (feed installed?)" >&2; exit 1; }
command -v mcopy >/dev/null || { echo "mtools/mcopy missing — apt-get install mtools" >&2; exit 1; }

# shellcheck disable=SC2012
MAN=$(ls "$BT"/*.manifest 2>/dev/null | head -1)
[ -n "$MAN" ] || { echo "no image manifest in $BT" >&2; exit 1; }
sh "$TOP/scripts/check-image-manifest.sh" "$MAN" "$BOARD"

# shellcheck disable=SC2012  # ls is fine here: fixed ASCII image names
IMGGZ=$(ls "$BT"/*mm6108-spi*squashfs-sysupgrade.img.gz 2>/dev/null | head -1)
[ -n "$IMGGZ" ] || { echo "no mm6108-spi sysupgrade image in $BT" >&2; exit 1; }
echo "source image: $IMGGZ"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# gzip returns 2 ("trailing garbage ignored") on some sysupgrade images; tolerate it, then require output.
gunzip -c "$IMGGZ" > "$T/disk.img" 2>/dev/null || true
[ -s "$T/disk.img" ] || { echo "gunzip produced no disk image" >&2; exit 1; }

# Parse MBR: p1 = boot FAT (offset/len), p2 = rootfs squashfs (offset + real bytes_used @ +40).
eval "$(python3 - "$T/disk.img" <<'PY'
import sys, struct
f = open(sys.argv[1], "rb"); mbr = f.read(512)
def part(i):
    e = mbr[446 + i*16 : 446 + (i+1)*16]
    return e[4], struct.unpack("<I", e[8:12])[0]*512, struct.unpack("<I", e[12:16])[0]*512
_, p1off, p1len = part(0)
_, p2off, _     = part(1)
f.seek(p2off); assert f.read(4) == b"hsqs", "p2 is not a squashfs (hsqs)"
f.seek(p2off + 40); bu = struct.unpack("<Q", f.read(8))[0]
print(f"P1OFF={p1off}\nP1LEN={p1len}\nP2OFF={p2off}\nSQBYTES={bu}")
PY
)"
echo "carve: boot p1 @${P1OFF} (${P1LEN}B), squashfs p2 @${P2OFF} (${SQBYTES}B)"

# rootfs: NOT carved from the image any more (#209 S5) — the pristine per-device squashfs that this
# image carries, identified by scripts/pick-rootfs.sh (see its header: a carve can be truncated, and
# the target-generic build_dir rootfs can lack the device's packages). Card and OTA use the same file.
ROOTSQ=$(cd "$TOP" && sh scripts/pick-rootfs.sh "$BOARD")
cp "$TOP/$ROOTSQ" "$T/root.squashfs"
echo "rootfs: $ROOTSQ ($(wc -c < "$T/root.squashfs") B; image p2 header says $SQBYTES B)"
[ "$(wc -c < "$T/root.squashfs")" = "$SQBYTES" ] || { echo "pristine rootfs size differs from the image's p2 bytes_used" >&2; exit 1; }

# boot: carve the FAT partition and extract rootless with mtools
dd if="$T/disk.img" of="$T/boot.fat" bs=1M iflag=skip_bytes,count_bytes \
   skip="$P1OFF" count="$P1LEN" status=none
mkdir -p "$T/bootdir"
mcopy -s -i "$T/boot.fat" ::/ "$T/bootdir/"

# FAT may surface names 8.3-uppercase; build-ab-payload.sh matches lowercase (kernel8.img, *.dtb, overlays/).
# Normalise deepest-first so directory renames don't invalidate child paths.
find "$T/bootdir" -depth -mindepth 1 | while IFS= read -r p; do
    d=$(dirname "$p"); b=$(basename "$p"); lb=$(printf '%s' "$b" | tr '[:upper:]' '[:lower:]')
    [ "$b" = "$lb" ] || mv "$p" "$d/$lb"
done

# BOOTDIR_OUT=<dir>: also leave the extracted boot files there, so build-board.sh --card builds the card
# from exactly these files (no second extraction, no SRC_IMG loop-mount of a possibly short image).
if [ -n "${BOOTDIR_OUT:-}" ]; then rm -rf "$BOOTDIR_OUT"; mkdir -p "$BOOTDIR_OUT"; cp -a "$T/bootdir/." "$BOOTDIR_OUT/"; fi

OUT="$BT/ab-payload-$BOARD.tar.gz"
sh "$PAYLOAD_SH" "$T/root.squashfs" "$T/bootdir" "$BOARD" "$OUT"
echo "A/B tar ready: $OUT"
