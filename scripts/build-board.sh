#!/bin/bash
# build-board.sh — the ONE way to build a Batman board image (#209 S5). Every board, same steps,
# so nobody has to remember a recipe. Source of truth for the rules: docs/boards-and-builds.md in
# winson3QQ/Batman (also checked out at feeds/batman/docs/boards-and-builds.md).
#
#   scripts/build-board.sh <board> [--update-lock] [-j N]      as the tree owner: build + OTA payload
#   scripts/build-board.sh <board> --card-only                 AS ROOT, after a build: the card image
#
#     <board>        ekh-bcm2711 (Pi 4) | ekh-bcm2710 (Pi 3A+)
#     --update-lock  regenerate boards/<board>/batman-config.lock from the recipe and stop
#                    (review + commit the diff: it is a deliberate recipe change)
#     --card-only    (root: losetup/mount/mkfs) assemble the flash-able A/B card image from THIS build's
#                    rootfs + boot files and run the card invariants. Builds nothing; refuses if the
#                    build outputs do not match the board's saved stamp.
#                    P6_PAYLOAD=<dir> (env) bakes a p6 payload, e.g. the Pi 4 OTS flash-and-go tars.
#
# Steps (each one stops on failure):
#   1 recipe     boards/<board>/batman-recipe = the openmanet_setup.sh arguments (CI reads it too)
#   2 setup      openmanet_setup.sh (+ -i when any pinned feed is not at its pin: check-feed-pins.sh),
#                then check-batman-adv-source.sh (batman-adv/batctl feed + version, #247) and
#                check-golang-rules.sh (packages feed uses the OpenMANET golang rules, #252)
#   3 lock       normalised .config must equal boards/<board>/batman-config.lock
#   4 stamp      scripts/stamp-batman-build.sh -> files/etc/batman-build, saved as logs/stamp-<board>.txt
#                (both boards share files/; the per-board copy is what later steps compare against)
#   5 make       (a failed parallel make is retried -j1 V=s: OpenWrt has parallel-build races); the Go
#                packages are cleaned first when the golang rules or the staged Go changed (#252)
#   6 manifest   scripts/check-image-manifest.sh (brcmfmac/43455, mm6108, OTS rule per SoC), then
#                check-go-toolchain.sh: every Go binary in the rootfs built by the tree's own Go (#252)
#   7 rootfs     scripts/pick-rootfs.sh: the pristine per-device squashfs the image carries; its stamp
#                must equal step 4's and its DISTRIB_TARGET this board's SoC. Card AND payload use it.
#   8 payload    scripts/local-ab-tar.sh -> the sysupgrade A/B payload (+ boot files kept for the card)
#   9 card       (--card-only, root) feeds/batman/scripts/build-ab-image.sh + tests/ab-card-invariants.sh
#  10 out        $OUT_ROOT/<version>/<board>/ with SHA256SUMS
set -euo pipefail

BOARD=${1:-}; shift || true
UPDATE_LOCK=0; CARD_ONLY=0; JOBS=$(nproc)
while [ $# -gt 0 ]; do
	case "$1" in
		--update-lock) UPDATE_LOCK=1 ;;
		--card-only) CARD_ONLY=1 ;;
		-j) shift; JOBS=${1:?-j needs a number} ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac; shift
done
case "$BOARD" in
	ekh-bcm2711) SUB=bcm2711; SOC=bcm2711 ;;
	ekh-bcm2710) SUB=bcm2710; SOC=bcm2710 ;;
	*) echo "usage: build-board.sh <ekh-bcm2711|ekh-bcm2710> [--update-lock | --card-only] [-j N]" >&2; exit 2 ;;
esac
TOP=$(pwd)
[ -f scripts/openmanet_setup.sh ] && [ -f batman-release.env ] || { echo "run from the firmware tree root" >&2; exit 2; }
OWNER=$(stat -c %U "$TOP")
OUT_ROOT=${OUT_ROOT:-$(getent passwd "$OWNER" | cut -d: -f6)/out}
STAMP=logs/stamp-$BOARD.txt
BOOTDIR=$TOP/logs/bootdir-$BOARD
BT=bin/targets/bcm27xx/$SUB
mkdir -p logs
say(){ printf '\n=== [%s] %s\n' "$BOARD" "$*"; }
norm(){ grep -E '^CONFIG_|^# CONFIG_.* is not set' "$1" | sort; }
US=staging_dir/host/bin/unsquashfs4; command -v unsquashfs >/dev/null && US=unsquashfs

if [ "$CARD_ONLY" = 0 ]; then
	[ "$(id -u)" != 0 ] || { echo "build as the tree owner ($OWNER), not root; only --card-only runs as root" >&2; exit 2; }

	say "1 recipe"
	RECIPE_F=boards/$BOARD/batman-recipe
	[ -f "$RECIPE_F" ] || { echo "no $RECIPE_F" >&2; exit 1; }
	read -r -a RECIPE < <(grep -v '^#' "$RECIPE_F" | tr '\n' ' ') || true   # no trailing newline -> read returns 1
	[ "${#RECIPE[@]}" -gt 0 ] || { echo "$RECIPE_F is empty" >&2; exit 1; }
	echo "openmanet_setup.sh ${RECIPE[*]}"

	say "2 setup"
	# every pinned feed, not just batman (#247: a routing-only pin bump must also re-init the feeds)
	INIT=()
	if STALE=$(sh scripts/check-feed-pins.sh); then echo "all pinned feeds at their pins"
	else echo "$STALE"; echo "-> feeds update (-i)"; INIT=(-i); fi
	# the feeds carry ONE board's patches (patches/<board>/, applied by -i); building the other board
	# on them would silently mix boards — re-init when they are not this board's (#247)
	PB=$(cat feeds/.batman-patched-board 2>/dev/null || echo unknown)
	[ "$PB" = "$BOARD" ] || { echo "feeds carry patches for '$PB', not $BOARD -> feeds update (-i)"; INIT=(-i); }
	# #252: the packages feed must carry the OpenMANET golang rules (synced by -i)
	sh scripts/check-golang-rules.sh >/dev/null || { echo "packages-feed golang rules are not OpenMANET's -> feeds update (-i)"; INIT=(-i); }
	./scripts/openmanet_setup.sh "${INIT[@]}" "${RECIPE[@]}" > "logs/setup-$BOARD.log" 2>&1 || { tail -30 "logs/setup-$BOARD.log"; exit 1; }
	sh scripts/check-feed-pins.sh >&2 || { echo "feeds still not at their pins after setup" >&2; exit 1; }
	sh scripts/check-batman-adv-source.sh
	sh scripts/check-golang-rules.sh >&2 || { echo "golang rules still not synced after setup" >&2; exit 1; }

	say "3 config lock"
	LOCK=boards/$BOARD/batman-config.lock
	if [ "$UPDATE_LOCK" = 1 ]; then
		norm .config > "$LOCK"; echo "wrote $LOCK ($(wc -l < "$LOCK") lines) — review and commit it; nothing built"; exit 0
	fi
	[ -f "$LOCK" ] || { echo "no $LOCK — create it with --update-lock and commit it" >&2; exit 1; }
	if ! diff <(cat "$LOCK") <(norm .config) > "logs/lock-$BOARD.diff"; then
		echo "the generated .config differs from $LOCK:" >&2; head -40 "logs/lock-$BOARD.diff" >&2
		echo "A deliberate change? re-run with --update-lock, review the diff, commit it. Otherwise fix the recipe/feed." >&2
		exit 1
	fi
	echo ".config == $LOCK"

	say "4 stamp"
	sh scripts/stamp-batman-build.sh "$BOARD"
	cp files/etc/batman-build "$STAMP"

	say "5 make -j$JOBS"
	# #252: OpenWrt's rebuild check hashes only a package's own directory, not the golang rules it
	# includes nor the Go it runs — so after the rules or the staged Go change, the Go packages would be
	# reused as-is (still built by the old Go). Clean every selected Go package whenever that changes.
	GOV=$(sed -n 's/^GO_DEFAULT_VERSION:=//p' feeds/openmanet/lang/golang/golang-values.mk | head -1)
	GOSTAMP=logs/go-rules-$BOARD.stamp
	GOSUM=$( { cat feeds/packages/lang/golang/golang-*.mk feeds/openmanet/lang/golang/golang-*.mk; echo "go-$GOV"; head -1 "staging_dir/hostpkg/lib/go-$GOV/VERSION" 2>/dev/null; } | sha256sum | cut -c1-16)
	if [ "$(cat "$GOSTAMP" 2>/dev/null)" != "$GOSUM" ]; then
		GOPKGS=""
		for d in package/feeds/*/*; do
			p=${d##*/}; case "$p" in golang*) continue ;; esac
			grep -qs 'golang-package.mk' "$(readlink -f "$d")/Makefile" || continue
			grep -qE "^CONFIG_PACKAGE_$p=[ym]$" .config && GOPKGS="$GOPKGS $p"
		done
		echo "golang rules / staged Go changed -> cleaning Go packages:$GOPKGS"
		for p in $GOPKGS; do make "package/$p/clean" > "logs/goclean-$BOARD-$p.log" 2>&1 || { tail -20 "logs/goclean-$BOARD-$p.log" >&2; exit 1; }; done
		echo "$GOSUM" > "$GOSTAMP.pending"
	fi
	if ! make -j"$JOBS" > "logs/build-$BOARD.log" 2>&1; then
		echo "make failed — retrying -j1 V=s (parallel-build races happen; logs/build-$BOARD-v.log)" >&2
		make -j1 V=s > "logs/build-$BOARD-v.log" 2>&1 || { tail -40 "logs/build-$BOARD-v.log" >&2; exit 1; }
	fi

	say "6 manifest gate"
	MAN=$(ls "$BT"/*.manifest | head -1)
	sh scripts/check-image-manifest.sh "$MAN" "$BOARD"
	# #252: every Go program in the image built by the tree's own Go
	CPU=$([ "$SOC" = bcm2711 ] && echo a72 || echo a53)
	sh scripts/check-go-toolchain.sh "build_dir/target-aarch64_cortex-${CPU}_musl/root-bcm27xx"
	[ ! -f "logs/go-rules-$BOARD.stamp.pending" ] || mv "logs/go-rules-$BOARD.stamp.pending" "logs/go-rules-$BOARD.stamp"
fi

[ -f "$STAMP" ] || { echo "no $STAMP — build this board first (without --card-only)" >&2; exit 1; }
VER=$(sed -n 's/^BATMAN_VERSION=//p' "$STAMP")
OUTD=$OUT_ROOT/$VER/$BOARD

say "7 rootfs (the one file both the card and the OTA payload carry)"
ROOTSQ=$(sh scripts/pick-rootfs.sh "$BOARD")
echo "rootfs: $ROOTSQ ($(wc -c < "$ROOTSQ") B)"
"$US" -cat "$ROOTSQ" etc/batman-build > "logs/stamp-$BOARD.inimage" 2>/dev/null || true
cmp -s "$STAMP" "logs/stamp-$BOARD.inimage" || { echo "the rootfs carries a different /etc/batman-build than $STAMP (stale build_dir or other board?):" >&2; diff "$STAMP" "logs/stamp-$BOARD.inimage" >&2 || true; exit 1; }
T=$("$US" -cat "$ROOTSQ" etc/openwrt_release 2>/dev/null | sed -n "s/^DISTRIB_TARGET='*[^/]*\/\([^']*\)'*$/\1/p")
[ "$T" = "$SUB" ] || { echo "rootfs DISTRIB_TARGET is '$T', board wants $SUB" >&2; exit 1; }
echo "stamp in rootfs == $STAMP ($VER), DISTRIB_TARGET=$T"

if [ "$CARD_ONLY" = 0 ]; then
	say "8 A/B payload"
	BOOTDIR_OUT=$BOOTDIR sh scripts/local-ab-tar.sh "$TOP" "$BOARD"
	mkdir -p "$OUTD"
	cp "$BT/ab-payload-$BOARD.tar.gz" "$OUTD/batman-$VER-$BOARD-ab-payload.tar.gz"
	cp "$MAN" "$OUTD/batman-$VER-$BOARD.manifest"
	cp "$STAMP" "$OUTD/batman-build.txt"
	tar xzf "$OUTD/batman-$VER-$BOARD-ab-payload.tar.gz" -O root.squashfs | cmp -s - "$ROOTSQ" \
		|| { echo "the payload's root.squashfs is not $ROOTSQ" >&2; exit 1; }
	echo "payload root.squashfs == $ROOTSQ"
else
	say "9 card image + invariants"
	[ "$(id -u)" = 0 ] || { echo "--card-only needs root (losetup/mount/mkfs)" >&2; exit 1; }
	[ -d "$OUTD" ] && [ -d "$BOOTDIR" ] || { echo "no $OUTD or $BOOTDIR — run the build (without --card-only) first" >&2; exit 1; }
	CARDIMG="$OUTD/batman-$VER-$BOARD-ab.img"
	# root-owned copy of the boot files: build-ab-image.sh (Batman <= 61996cc) copies them onto the FAT
	# boot slots with `cp -a`, which fails ("preserve ownership") for files the tree owner extracted.
	BD=$(mktemp -d); trap 'rm -rf "$BD"' EXIT; cp -r "$BOOTDIR"/. "$BD"/
	CARDENV=(ROOTFS="$TOP/$ROOTSQ" BOOTDIR="$BD" OUT="$CARDIMG" SOC="$SOC")
	[ -n "${P6_PAYLOAD:-}" ] && CARDENV+=(P6_PAYLOAD="$P6_PAYLOAD")
	env "${CARDENV[@]}" bash feeds/batman/scripts/build-ab-image.sh
	SOC=$SOC bash feeds/batman/tests/ab-card-invariants.sh | tee "$OUTD/ab-card-invariants.txt"
	grep -q ' 0 failed' "$OUTD/ab-card-invariants.txt" || { echo "card invariants failed" >&2; exit 1; }
fi

say "10 out"
( cd "$OUTD" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort | xargs sha256sum > SHA256SUMS )
chown -R "$OWNER": "$OUTD" 2>/dev/null || true
cat "$OUTD/SHA256SUMS"
echo; echo "$VER for $BOARD -> $OUTD"
grep -q '^BATMAN_DIRTY=1' "$STAMP" && echo "!!! DIRTY build: fine for testing, NEVER a release"
exit 0
