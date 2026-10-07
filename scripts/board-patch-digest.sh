#!/bin/sh
# board-patch-digest.sh <board> — content digest of patches/<board>/*.patch (Batman #275).
# openmanet_setup.sh -i records "<board> <digest>" in feeds/.batman-patched-board; build-board.sh re-runs -i
# whenever the board's patch set (added, changed or removed patch) no longer matches what the feeds carry.
# Content and names only (modes do not matter); empty/missing dir -> the digest of nothing.
B=${1:?usage: board-patch-digest.sh <board>}
cd "$(dirname "$0")/.." || exit 2
{ [ -d "patches/$B" ] && ( cd "patches/$B" && ls -1 -- *.patch 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do sha256sum -- "$p"; done ); } \
	| sha256sum | cut -c1-16
