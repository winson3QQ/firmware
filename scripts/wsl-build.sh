#!/bin/sh
# wsl-build.sh — canonical local (WSL) build entrypoint for the mm6108-spi (manet01) image.
# Builds, then auto-assembles the batman A/B sysupgrade tar (scripts/local-ab-tar.sh), so
# bin/targets ends up with BOTH the whole-disk image and a ready-to-`sysupgrade -n` A/B tar —
# the same tar CI emits, no manual carve.
#
#   scripts/wsl-build.sh            # incremental `make` + A/B tar (the usual iteration)
#   SETUP=1 scripts/wsl-build.sh    # also re-run openmanet_setup first (feeds/config changed)
#   AB_ONLY=1 scripts/wsl-build.sh  # skip the build, just (re)assemble the A/B tar from existing images
#
# Run as a NON-root user (OpenWrt refuses root builds). Needs mtools for the tar step
# (apt-get install mtools). Set JOBS to override the -j level (default: nproc).
set -eu
TOP=$(cd "$(dirname "$0")/.." && pwd)
cd "$TOP"
BOARD_CFG=ekh-bcm2711
JOBS=${JOBS:-$(nproc)}
log() { echo "=== $(date) $* ==="; }

if [ "${AB_ONLY:-0}" != 1 ]; then
	if [ "${SETUP:-0}" = 1 ]; then
		log "configure (openmanet_setup -i -b $BOARD_CFG)"
		./openmanet_setup -i -b "$BOARD_CFG"
	fi
	log "make download -j$JOBS"
	make download -j"$JOBS"
	log "make -j$JOBS"
	make -j"$JOBS"
fi

log "assemble A/B tar (local-ab-tar.sh)"
sh scripts/local-ab-tar.sh "$TOP"
log "DONE — image + A/B tar in bin/targets/bcm27xx/bcm2711/"
