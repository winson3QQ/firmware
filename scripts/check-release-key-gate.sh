#!/bin/bash
# check-release-key-gate.sh — #254 P3 §3.7.2: the release root key in an image (what the app update trusts) is the
# one its build kind may carry. Run on an EXTRACTED rootfs (gate-rootfs.sh does the extraction for every path that
# ships one; build-board.sh step 7 calls it on its own extraction).
#
#   check-release-key-gate.sh <rootfs-dir> [--normal | --ci]
#
#   rel           release-root.pub's fingerprint = the Batman feed's scripts/release-root.fpr (that pin missing,
#                 i.e. before R exists (#255) = FAIL); release-min-serial well formed; never BATMAN_BENCH_TRUST
#   bench         (BATMAN_BENCH_TRUST=T, channel wsl / ci) release-root.pub = the feed's tests/keys/T.pub, serial 1
#   wsl / ci      (and a rootfs without /etc/batman-build, e.g. fast-build) no key file at all
#   --ci          the above, and any bench build is a FAIL (CI builds never trust the public test root)
# Key files must be regular files (not symlinks), one line each. BATMAN_FEED (default feeds/batman under the
# firmware tree) is where the pins come from. This guards against our own mistakes, not a compromised repo:
# whoever can change both the key and its pin can pass it (§3.7.2 界線).
set -u
fail(){ echo "release-key-gate: FAIL: $*" >&2; exit 1; }
TOP=$(cd "$(dirname "$0")/.." && pwd)
FEED=${BATMAN_FEED:-$TOP/feeds/batman}
R=${1:-}; MODE=${2:---normal}
[ -n "$R" ] && [ -d "$R" ] || fail "usage: check-release-key-gate.sh <rootfs-dir> [--normal | --ci]"
case "$MODE" in --normal | --ci) ;; *) fail "unknown mode $MODE" ;; esac
[ $# -le 2 ] || fail "too many arguments"
KP=$R/usr/share/batman/release-root.pub
KS=$R/usr/share/batman/release-min-serial
ST=$R/etc/batman-build
sv(){ [ -f "$ST" ] && sed -n "s/^$1=//p" "$ST" | head -1; }
CH=$(sv BATMAN_CHANNEL); BENCH=$(sv BATMAN_BENCH_TRUST)
oneline(){ # <file> -> its single line (fails on anything else)
	[ -f "$1" ] && [ ! -L "$1" ] || fail "${1#"$R"} is not a regular file"
	[ "$(wc -l < "$1")" -le 1 ] && [ "$(wc -c < "$1")" -le 256 ] || fail "${1#"$R"} is not one short line"
	tr -d '\n' < "$1"
}
have=0; { [ -e "$KP" ] || [ -L "$KP" ] || [ -e "$KS" ] || [ -L "$KS" ]; } && have=1
case "$BENCH" in '' | T) ;; *) fail "BATMAN_BENCH_TRUST='$BENCH' (only T exists)" ;; esac
[ -z "$BENCH" ] || [ "$MODE" != --ci ] || fail "a bench build (BATMAN_BENCH_TRUST=T) in CI — CI builds never trust the test root"
if [ "$CH" = rel ]; then
	[ -z "$BENCH" ] || fail "a rel build with BATMAN_BENCH_TRUST"
	[ $have = 1 ] || fail "a rel build without the release root key"
	pub=$(oneline "$KP") || exit 1; ser=$(oneline "$KS") || exit 1
	[[ $pub =~ ^04[0-9a-f]{128}$ ]] || fail "release-root.pub is not a hex P-256 point"
	[[ $ser =~ ^[1-9][0-9]{0,9}$ ]] || fail "release-min-serial '$ser' is not a serial"
	PIN=$FEED/scripts/release-root.fpr
	[ -f "$PIN" ] && [ ! -L "$PIN" ] || fail "no pinned R fingerprint ($PIN): no rel build before R exists (#255)"
	want=$(tr -d ' \n' < "$PIN")
	got=$(printf %s "$pub" | xxd -r -p | sha256sum | cut -d' ' -f1)
	[ "$got" = "$want" ] || fail "release-root.pub is not R (fingerprint $got, pinned $want)"
	echo "release-key-gate: ok (rel: R ${got:0:16}…, min serial $ser)"
elif [ -n "$BENCH" ]; then
	case "$CH" in wsl | ci) ;; *) fail "a bench build on channel '$CH'" ;; esac
	[ $have = 1 ] || fail "a bench build without its key file"
	pub=$(oneline "$KP") || exit 1; ser=$(oneline "$KS") || exit 1
	tp=$(tr -d '\n' < "$FEED/tests/keys/T.pub" 2>/dev/null) || tp=""
	[ -n "$tp" ] || fail "no $FEED/tests/keys/T.pub to compare with"
	[ "$pub" = "$tp" ] || fail "a bench build carrying a key that is not the feed's T"
	[ "$ser" = 1 ] || fail "a bench build with min serial '$ser' (want 1)"
	echo "release-key-gate: ok (bench: T)"
else
	case "$CH" in wsl | ci | '') ;; *) fail "channel '$CH' is not wsl / ci / rel" ;; esac
	[ $have = 0 ] || fail "a ${CH:-stampless} build carries a release root key file (only rel / --bench may)"
	echo "release-key-gate: ok (${CH:-no stamp}: no release root key)"
fi
