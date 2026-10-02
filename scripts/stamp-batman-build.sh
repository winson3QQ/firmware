#!/bin/sh
# stamp-batman-build.sh — write files/etc/batman-build for this build (#209 S5). Never hand-edit it.
#
#   scripts/stamp-batman-build.sh <board>        board = ekh-bcm2711 | ekh-bcm2710 | ...
#
# Run from the firmware tree root, AFTER openmanet_setup.sh (needs .config and feeds/batman) and
# BEFORE make (OpenWrt bakes files/ into the rootfs). Release metadata comes from batman-release.env;
# everything provable comes from git, so the stamp cannot name the wrong commits again (1.4.14's
# hand-written stamp said feed 6763ed8 / fw c19763a; the build was feed 8685c5a / fw 397e313).
#
# Refuses (exit 1) when the checked-out batman feed is not the commit feeds.conf.default pins —
# that is a stale feed (openmanet_setup.sh -i was not re-run after a pin bump), and the image
# would silently carry old Batman code under a new version number.
#
# BATMAN_DIRTY=1 when the build does not equal its commits: tracked changes in this tree, untracked
# files under the build inputs, a feeds.conf override, or a modified feeds/batman checkout. A dirty
# build may be tested, never released (scripts/build-board.sh prints it; batman-version shows it).
set -eu
BOARD=${1:?usage: stamp-batman-build.sh <board>}
[ -f batman-release.env ] && [ -f .config ] && [ -d feeds/batman/.git ] || {
	echo "stamp: run from the firmware tree root after openmanet_setup.sh (need batman-release.env, .config, feeds/batman)" >&2; exit 1; }
get(){ sed -n "s/^$1=//p" batman-release.env | head -1; }
REL=$(get BATMAN_RELEASE); CH=$(get BATMAN_CHANNEL); N=$(get BATMAN_BUILD_N)
[ -n "$REL" ] && [ -n "$CH" ] && [ -n "$N" ] || { echo "stamp: batman-release.env lacks BATMAN_RELEASE/CHANNEL/BUILD_N" >&2; exit 1; }

PIN=$(sed -n 's|^src-git batman [^^]*\^\([0-9a-f]\{7,40\}\).*|\1|p' feeds.conf.default | head -1)
[ -n "$PIN" ] || { echo "stamp: no batman pin in feeds.conf.default" >&2; exit 1; }
FEED=$(git -C feeds/batman rev-parse HEAD)
case "$FEED" in "$PIN"*) ;; *)
	echo "stamp: feeds/batman is at $FEED but feeds.conf.default pins $PIN — stale feed." >&2
	echo "       Re-run openmanet_setup.sh with -i (scripts/build-board.sh does this when needed)." >&2
	exit 1 ;;
esac
FW=$(git rev-parse HEAD)

DIRTY=0; why=""
git diff --quiet HEAD -- || { DIRTY=1; why="$why tracked-changes"; }
u=$(git ls-files --others --exclude-standard -- files boards target package include scripts config toolchain tools \
	rules.mk Makefile feeds.conf.default batman-release.env | head -5)
[ -z "$u" ] || { DIRTY=1; why="$why untracked:$(echo "$u" | tr '\n' ' ')"; }
[ ! -f feeds.conf ] || cmp -s feeds.conf feeds.conf.default || { DIRTY=1; why="$why feeds.conf-override"; }
[ -z "$(git -C feeds/batman status --porcelain)" ] || { DIRTY=1; why="$why feeds/batman-modified"; }

CODE=$(sed -n 's/^CONFIG_VERSION_CODE="\(.*\)"$/\1/p' .config); REV=$(./scripts/getver.sh 2>/dev/null || echo unknown)
F7=$(printf %.7s "$FEED"); W7=$(printf %.7s "$FW")
VER="$REL-$CH.$N+$F7.fw$W7"; [ "$DIRTY" = 1 ] && VER="$VER.dirty"

mkdir -p files/etc
{
	echo "BATMAN_VERSION=$VER"
	echo "BATMAN_BOARD=$BOARD"
	echo "BATMAN_CHANNEL=$CH"
	echo "BATMAN_MILESTONE=$(get BATMAN_MILESTONE)"
	echo "BATMAN_BUILD_DATE=$(date -u +%Y-%m-%d)"
	echo "BATMAN_BASE=OpenMANET-${CODE:-?}-$REV"
	echo "BATMAN_FEED_COMMIT=$F7"
	echo "BATMAN_FW_COMMIT=$W7"
	echo "BATMAN_FW_FEED_PIN=$(printf %.7s "$PIN")"
	echo "BATMAN_DIRTY=$DIRTY"
	echo "BATMAN_FEATURES=$(get BATMAN_FEATURES)"
	echo "BATMAN_NOTE=$(get BATMAN_NOTE)"
} > files/etc/batman-build
echo "stamp: $VER board=$BOARD dirty=$DIRTY${why:+ ($why)}"
