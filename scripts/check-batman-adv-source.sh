#!/bin/sh
# check-batman-adv-source.sh — refuse to build unless batman-adv/batctl come from the expected feed
# and version (Batman #247). Run after openmanet_setup.sh, before make; build-board.sh step 2 does.
#
# Why: the feeds/patch steps of openmanet_setup.sh have swallowed failures before (1.5.1-wsl.1 built
# without patch 022), and a routing pin that moved without -i leaves OpenMANET's batman-adv 2025.4
# installed. Both would ship the wrong mesh core under a new version number, so check the result,
# not the steps. The built image is checked again by check-image-manifest.sh (exact versions).
#
# Expected: routing feed = openwrt/routing openwrt-24.10 (feeds.conf.default pin), batman-adv 2024.3
# PKG_RELEASE 13, batctl 2024.3 PKG_RELEASE 5, exactly one batctl variant (=y) in .config (the 24.10
# batctl Makefile has no per-variant PKG_BUILD_DIR, so two variants would share one build dir).
# Bump these together with the routing pin.
set -eu
FEED=routing
EXPECT="batman-adv:2024.3:13 batctl:2024.3:5"

[ -f feeds.conf.default ] && [ -f .config ] || { echo "check-batman-adv-source: run from the firmware tree root after setup" >&2; exit 2; }
bad=0
fail(){ echo "check-batman-adv-source: $*" >&2; bad=1; }

pin=$(sed -n "s|^src-git $FEED [^^ ]*\^\([0-9a-f]\{7,40\}\).*|\1|p" feeds.conf.default | head -1)
head=$(git -C "feeds/$FEED" rev-parse HEAD 2>/dev/null || echo none)
[ -n "$pin" ] || fail "no $FEED pin in feeds.conf.default"
case "$head" in "$pin"*) ;; *) fail "feeds/$FEED is $head, pin is $pin (re-run openmanet_setup.sh -i)" ;; esac

for e in $EXPECT; do
	pkg=${e%%:*}; rest=${e#*:}; ver=${rest%%:*}; rel=${rest#*:}
	set -- package/feeds/*/"$pkg"
	if [ "$#" -ne 1 ] || [ ! -e "$1" ]; then
		fail "$pkg installed $([ -e "$1" ] && echo "$#" || echo 0) times (want exactly 1, from $FEED): $*"; continue
	fi
	tgt=$(readlink -f "$1")
	case "$tgt" in */feeds/$FEED/$pkg) ;; *) fail "$pkg comes from $tgt, want feeds/$FEED/$pkg" ;; esac
	mk=$tgt/Makefile
	v=$(sed -n 's/^PKG_VERSION:=//p' "$mk" | head -1); r=$(sed -n 's/^PKG_RELEASE:=//p' "$mk" | head -1)
	[ "$v" = "$ver" ] && [ "$r" = "$rel" ] || fail "$pkg is $v-$r, want $ver-$rel"
done

n=$(grep -cE '^CONFIG_PACKAGE_batctl-(tiny|default|full)=[ym]$' .config || true)
[ "$n" = 1 ] || fail "$n batctl variants selected in .config (want exactly 1): $(grep -E '^CONFIG_PACKAGE_batctl-' .config | tr '\n' ' ')"
grep -q '^CONFIG_BATMAN_ADV_NC=y' .config && fail "CONFIG_BATMAN_ADV_NC=y (network coding must stay off, #247 D3)"

[ "$bad" = 0 ] || { echo "check-batman-adv-source: REFUSING to build" >&2; exit 1; }
echo "check-batman-adv-source: OK — $EXPECT from feeds/$FEED @ $(printf %.7s "$head"), 1 batctl variant, NC off"
