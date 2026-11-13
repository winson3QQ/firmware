#!/bin/sh
# stamp-batman-build.sh — write files/etc/batman-build for this build (#209 S5). Never hand-edit it.
#
#   scripts/stamp-batman-build.sh <board> [--bench T]        board = ekh-bcm2711 | ekh-bcm2710 | ...
#
# #254 P3 §3.7.2: the image's release root key (what the app update trusts) is placed HERE, by the build kind:
#   rel           keys/release-root.pub (R) + keys/release-min-serial — missing (before #255) = the rel build fails
#   --bench T     the batman feed's tests/keys/T.pub + min-serial 1, BATMAN_BENCH_TRUST=T, ".bench" in the version
#                 (bench nodes such as 02 / 04 only; only from this ARGUMENT — never from the environment — so a CI
#                 env: or a bare stamp run never makes one; rel + --bench refuses)
#   wsl / ci      no key: the app update answers reason 24 (ssh sysupgrade / reflash only)
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
BOARD=${1:?usage: stamp-batman-build.sh <board> [--bench T]}
BENCH=""
case "${2:-}" in
'') ;;
--bench) [ "${3:-}" = T ] || { echo "stamp: --bench takes exactly T" >&2; exit 1; }; BENCH=T ;;
*) echo "usage: stamp-batman-build.sh <board> [--bench T]" >&2; exit 1 ;;
esac
[ -f batman-release.env ] && [ -f .config ] && [ -d feeds/batman/.git ] || {
	echo "stamp: run from the firmware tree root after openmanet_setup.sh (need batman-release.env, .config, feeds/batman)" >&2; exit 1; }
get(){ sed -n "s/^$1=//p" batman-release.env | head -1; }
REL=$(get BATMAN_RELEASE); CH=$(get BATMAN_CHANNEL); N=$(get BATMAN_BUILD_N)
[ -n "$REL" ] && [ -n "$CH" ] && [ -n "$N" ] || { echo "stamp: batman-release.env lacks BATMAN_RELEASE/CHANNEL/BUILD_N" >&2; exit 1; }
case "$CH" in wsl | ci | rel) ;; *) echo "stamp: BATMAN_CHANNEL '$CH' is not wsl / ci / rel" >&2; exit 1 ;; esac
[ "$CH" = rel ] && [ -n "$BENCH" ] && { echo "stamp: a rel build never trusts the test root (--bench)" >&2; exit 1; }

PIN=$(sed -n 's|^src-git batman [^^]*\^\([0-9a-f]\{7,40\}\).*|\1|p' feeds.conf.default | head -1)
[ -n "$PIN" ] || { echo "stamp: no batman pin in feeds.conf.default" >&2; exit 1; }
FEED=$(git -C feeds/batman rev-parse HEAD)
case "$FEED" in "$PIN"*) ;; *)
	echo "stamp: feeds/batman is at $FEED but feeds.conf.default pins $PIN — stale feed." >&2
	echo "       Re-run openmanet_setup.sh with -i (scripts/build-board.sh does this when needed)." >&2
	exit 1 ;;
esac
STALE=$(sh scripts/check-feed-pins.sh) || {
	echo "stamp: pinned feeds are stale (#247) — re-run openmanet_setup.sh with -i:" >&2; echo "$STALE" >&2; exit 1; }
FW=$(git rev-parse HEAD)

DIRTY=0; why=""
git diff --quiet HEAD -- || { DIRTY=1; why="$why tracked-changes"; }
u=$(git ls-files --others --exclude-standard -- files boards target package include scripts config toolchain tools \
	rules.mk Makefile feeds.conf.default batman-release.env | head -5)
[ -z "$u" ] || { DIRTY=1; why="$why untracked:$(echo "$u" | tr '\n' ' ')"; }
[ ! -f feeds.conf ] || cmp -s feeds.conf feeds.conf.default || { DIRTY=1; why="$why feeds.conf-override"; }
[ -z "$(git -C feeds/batman status --porcelain)" ] || { DIRTY=1; why="$why feeds/batman-modified"; }

# #275: never stamp a build whose board patches are not all applied, and bake each patch's witness into the
# image (/etc/batman-patch-witness) so build-board/CI check it in the rootfs and daily-validation on the node.
sh scripts/check-board-patches.sh "$BOARD" >&2 || { echo "stamp: board patches of $BOARD are not applied in feeds/ (#275)" >&2; exit 1; }
WIT=$(sh scripts/patch-witness.sh list "$BOARD") || { echo "stamp: a patches/$BOARD patch lacks a valid Batman-Witness line (#275)" >&2; exit 1; }
NP=$(ls patches/"$BOARD"/*.patch 2>/dev/null | wc -l); PD=$(sh scripts/board-patch-digest.sh "$BOARD")

CODE=$(sed -n 's/^CONFIG_VERSION_CODE="\(.*\)"$/\1/p' .config); REV=$(./scripts/getver.sh 2>/dev/null || echo unknown)
F7=$(printf %.7s "$FEED"); W7=$(printf %.7s "$FW")
# #254 (254-h23 §4.2): a -wbox test variant is never a release: DIRTY forced, the variant in the version
WBOX=${BATMAN_WBOX:-}
case "$WBOX" in '') ;; *[!a-z0-9-]*) echo "stamp: bad BATMAN_WBOX '$WBOX'" >&2; exit 1 ;; *) DIRTY=1; why="$why wbox-$WBOX" ;; esac
VER="$REL-$CH.$N+$F7.fw$W7"; [ -n "$BENCH" ] && VER="$VER.bench" # before .dirty / .wbox- (prov-254.sh name match)
[ "$DIRTY" = 1 ] && VER="$VER.dirty"; [ -n "$WBOX" ] && VER="$VER.wbox-$WBOX"

# the root key files: removed first (they are .gitignore'd; a tree that built bench before must not leave T in
# the next ordinary build), then placed by the build kind
KD=files/usr/share/batman
rm -f "$KD/release-root.pub" "$KD/release-min-serial"
case "$CH:$BENCH" in
rel:)
	[ -f keys/release-root.pub ] && [ ! -L keys/release-root.pub ] && [ -f keys/release-min-serial ] && [ ! -L keys/release-min-serial ] || {
		echo "stamp: a rel build needs keys/release-root.pub and keys/release-min-serial (the release root R, #255)" >&2; exit 1; }
	mkdir -p "$KD"; cp keys/release-root.pub "$KD/release-root.pub"; cp keys/release-min-serial "$KD/release-min-serial" ;;
*:T)
	TP=feeds/batman/tests/keys/T.pub
	[ -f "$TP" ] && [ ! -L "$TP" ] || { echo "stamp: --bench but the batman feed has no tests/keys/T.pub" >&2; exit 1; }
	mkdir -p "$KD"; cp "$TP" "$KD/release-root.pub"; echo 1 > "$KD/release-min-serial" ;;
esac

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
	echo "BATMAN_BOARD_PATCHES=$NP:$PD"
	echo "BATMAN_FEATURES=$(get BATMAN_FEATURES)"
	echo "BATMAN_NOTE=$(get BATMAN_NOTE)"
	[ -z "$WBOX" ] || echo "BATMAN_WBOX=$WBOX"
	[ -z "$BENCH" ] || echo "BATMAN_BENCH_TRUST=$BENCH"
} > files/etc/batman-build
printf '%s
' "$WIT" | grep . > files/etc/batman-patch-witness || : > files/etc/batman-patch-witness
echo "stamp: $VER board=$BOARD dirty=$DIRTY${why:+ ($why)} root-key=$([ -f "$KD/release-root.pub" ] && { [ -n "$BENCH" ] && echo T || echo R; } || echo none)"
