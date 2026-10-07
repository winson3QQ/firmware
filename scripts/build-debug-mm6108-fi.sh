#!/bin/bash
# build-debug-mm6108-fi.sh <board> — build the #263 FAULT-INJECTION debug module for the board's CURRENT build.
#
#   scripts/build-debug-mm6108-fi.sh ekh-bcm2711 [stock]
#
# Run right after `scripts/build-board.sh <board>` (same tree, same .config, same kernel), so the module's
# vermagic/ABI match the image that build produced. Output, next to that build's payload:
#   $OUT_ROOT/<version>/<board>/debug/mm6108_sdio-fi263.ko         shipped driver (incl. patch 023) + FI knobs
#   $OUT_ROOT/<version>/<board>/debug/mm6108_sdio-fi263-stock.ko   with `stock`: WITHOUT 023 — the negative
#                                                                  control, panics a node on the first case
# Consumed by Batman scripts/daily-validation.sh (DV_T263_KO, suite halow-fi-263) and scripts/node/halow-fi-263.sh.
#
# NEVER SHIPPED: debug/990-DEBUG-fi-263.patch is copied into the driver's patch dir only for this compile and
# removed again, and the package is cleaned afterwards so the next image build recompiles the real driver.
set -euo pipefail
BOARD=${1:?usage: build-debug-mm6108-fi.sh <board> [stock]}; MODE=${2:-}
TOP=$(pwd); [ -f scripts/build-board.sh ] && [ -f batman-release.env ] || { echo "run from the firmware tree root" >&2; exit 2; }
case "$BOARD" in ekh-bcm2711) BD=target-aarch64_cortex-a72_musl/linux-bcm27xx_bcm2711 ;; ekh-bcm2710) BD=target-aarch64_cortex-a53_musl/linux-bcm27xx_bcm2710 ;; *) echo "unknown board $BOARD" >&2; exit 2 ;; esac
PB=$(cut -d" " -f1 feeds/.batman-patched-board 2>/dev/null)   # "<board> [<patch digest>]" (#275 adds the digest)
[ "$PB" = "$BOARD" ] || { echo "the feeds carry patches for '$PB', not $BOARD — run scripts/build-board.sh $BOARD first" >&2; exit 1; }
[ ! -f scripts/check-board-patches.sh ] || sh scripts/check-board-patches.sh "$BOARD" >/dev/null || { echo "board patches not applied in feeds/ — run scripts/build-board.sh $BOARD first" >&2; exit 1; }
STAMP=logs/stamp-$BOARD.txt; [ -f "$STAMP" ] || { echo "no $STAMP — build the board first" >&2; exit 1; }
VER=$(sed -n 's/^BATMAN_VERSION=//p' "$STAMP"); OWNER=$(stat -c %U "$TOP")
OUT=${OUT_ROOT:-$(getent passwd "$OWNER" | cut -d: -f6)/out}/$VER/$BOARD/debug; mkdir -p "$OUT"
PD=feeds/openmanet/morse-micro/mm6108-driver/patches; PKG=package/feeds/openmanet/mm6108-driver
DBG=$PD/990-DEBUG-fi-263.patch; HELD=""
cleanup(){ rm -f "$DBG"; [ -n "$HELD" ] && mv "$HELD" "$PD/"; make "$PKG/clean" >/dev/null 2>&1 || true; echo "debug patch removed, package cleaned (next image build recompiles the shipped driver)"; }
trap cleanup EXIT
cp debug/990-DEBUG-fi-263.patch "$DBG"
NAME=mm6108_sdio-fi263.ko
if [ "$MODE" = stock ]; then
	[ -f "$PD/023-cmd-inflight-263.patch" ] && { HELD=$(mktemp -d)/023-cmd-inflight-263.patch; mv "$PD/023-cmd-inflight-263.patch" "$HELD"; }
	NAME=mm6108_sdio-fi263-stock.ko
fi
make "$PKG/clean" >/dev/null 2>&1
make -j"$(nproc)" "$PKG/compile" > "logs/debug-fi263-$BOARD.log" 2>&1 || { tail -30 "logs/debug-fi263-$BOARD.log"; exit 1; }
ko=$(find "build_dir/$BD" -name mm6108_sdio.ko -path '*mm6108-driver*' | head -1)
[ -n "$ko" ] && grep -aq fi263_put_delay_ms "$ko" || { echo "built module has no fi263 knobs — refusing" >&2; exit 1; }
cp "$ko" "$OUT/$NAME"; ( cd "$OUT" && sha256sum "$NAME" > "$NAME.sha256" )
echo "$OUT/$NAME  ($(grep -a -o -m1 'vermagic=[^ ]*' "$OUT/$NAME"); patched-023=$(grep -aq cmd_timeout_in_flight "$OUT/$NAME" && echo yes || echo NO))"
