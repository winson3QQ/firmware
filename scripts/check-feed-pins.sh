#!/bin/sh
# check-feed-pins.sh — is every pinned feed checked out at the commit feeds.conf.default pins? (Batman #247)
#
#   scripts/check-feed-pins.sh          exit 0 = all pinned feeds match, 1 = at least one is stale
#
# A pinned feed (src-git <name> <url>^<sha>) is only re-fetched by "feeds update -a", i.e. by
# openmanet_setup.sh -i. build-board.sh used to add -i only when the *batman* pin moved, so a commit
# that moved any other pin (e.g. routing -> openwrt-24.10 for #247) built the old feed silently.
# build-board.sh now runs -i when this fails; stamp-batman-build.sh refuses to stamp when it fails.
# Prints one line per stale feed. Run from the firmware tree root.
set -eu
[ -f feeds.conf.default ] || { echo "check-feed-pins: run from the firmware tree root" >&2; exit 2; }
bad=0
# scripts/feeds reads feeds.conf before feeds.conf.default; a differing override is not a Batman build
if [ -f feeds.conf ] && ! cmp -s feeds.conf feeds.conf.default; then
	echo "feeds.conf overrides feeds.conf.default — remove it (the pins this tree builds are in feeds.conf.default)"; bad=1
fi
# every src-git feed must be pinned to a commit: an unpinned (;branch) feed is not reproducible
n_git=$(grep -c '^src-git ' feeds.conf.default || true)
n_pin=$(grep -cE '^src-git [A-Za-z0-9_-]+ [^^ ]+\^[0-9a-f]{7,40}( |$)' feeds.conf.default || true)
[ "$n_git" = "$n_pin" ] || { echo "$((n_git - n_pin)) src-git feed(s) in feeds.conf.default carry no ^<sha> pin"; bad=1; }
for line in $(sed -n 's|^src-git \([A-Za-z0-9_-]*\) [^^ ]*\^\([0-9a-f]\{7,40\}\).*|\1=\2|p' feeds.conf.default); do
	name=${line%%=*}; pin=${line#*=}
	head=$(git -C "feeds/$name" rev-parse HEAD 2>/dev/null || echo none)
	case "$head" in
		"$pin"*) ;;
		*) echo "feeds/$name is $head, feeds.conf.default pins $pin"; bad=1 ;;
	esac
done
exit $bad
