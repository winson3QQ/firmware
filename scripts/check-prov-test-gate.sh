#!/bin/bash
# check-prov-test-gate.sh ROOTFS_DIR [WBOX_NAME] — #254 build gate for the provisioning helper's test seams
# (Batman docs/design/254-h23-harness.md §4.1.3, §15.4). Reads the extracted rootfs (build-board.sh step 7, CI).
#
# Without WBOX_NAME (a normal build): the image must carry NO test seam at all —
#   helper built without -tags prov_test; no marker string; the word "killpoint" nowhere in the helper;
#   no BATMAN_WBOX= in /etc/batman-build; no wbox witness string anywhere in the rootfs.
# With WBOX_NAME (build-board.sh --wbox NAME): the variant, and ONLY that variant, is in THIS rootfs —
#   BATMAN_WBOX=NAME and a .dirty.wbox-NAME version; its witness string present and no other variant's;
#   a prov_test variant's helper carries the marker AND the armed-killpoint format literal (the seam was compiled
#   in, not left in a _test.go file); a release variant's Go helper carries no seam at all (same rules as a normal
#   build); an init mutant is enabled (etc/rc.d/S??wbox-*).
# Any input that cannot be read is a FAIL, never a pass.
set -u
R=${1:?usage: check-prov-test-gate.sh ROOTFS_DIR [WBOX_NAME]}
NAME=${2:-}
TOP=$(cd "$(dirname "$0")/.." && pwd)
H=$R/usr/bin/batman-provhelper
fail(){ echo "check-prov-test-gate: FAIL: $*" >&2; exit 1; }
cnt(){ strings "$H" | grep -c -- "$1"; }     # Go strings have no NUL: grep -c counts the line it sits in
# W = every wbox witness in the rootfs (space-separated, sorted, unique); grep rc 2 = a file it could not read = FAIL,
# not "none". Runs in the gate's own shell (a fail() inside $(...) would only leave the subshell).
witnesses(){ local o rc; o=$(cd "$R" && grep -rhaoE 'WBOX-[a-z0-9-]+-[0-9a-f]{8}' .); rc=$?
	[ $rc -le 1 ] || fail "cannot scan the rootfs for wbox witnesses (grep rc $rc)"
	W=$(printf '%s\n' "$o" | sed '/^$/d' | sort -u | tr '\n' ' '); W=${W% }; }

[ -d "$R/etc" ] || fail "rootfs '$R' not extracted (no etc/)"
[ ! -L "$R/etc/batman-build" ] || fail "rootfs /etc/batman-build is a symlink"
[ -f "$R/etc/batman-build" ] || fail "rootfs has no /etc/batman-build"
[ ! -L "$H" ] || fail "rootfs /usr/bin/batman-provhelper is a symlink (an absolute one would make this gate read a build-host file)"
[ -f "$H" ] || fail "rootfs has no /usr/bin/batman-provhelper"
command -v strings >/dev/null || fail "no strings(1) on the build host"
GOV=$(sed -n 's/^GO_DEFAULT_VERSION:=//p' "$TOP"/feeds/openmanet/lang/golang/golang-values.mk 2>/dev/null | head -1)
GO=${GO:-$TOP/staging_dir/hostpkg/lib/go-$GOV/bin/go}   # the tree's own Go, same rule as build-board.sh step 5
VER=$(sed -n 's/^BATMAN_VERSION=//p' "$R/etc/batman-build")
WB=$(sed -n 's/^BATMAN_WBOX=//p' "$R/etc/batman-build")
# go version -m prints nothing for a non-Go file (helper-exit1 replaces the binary with a shell script)
TAGS=""; ISGO=0
if [ -x "$GO" ] && BI=$("$GO" version -m "$H" 2>/dev/null) && [ -n "$BI" ]; then
	ISGO=1; TAGS=$(sed -n 's/^[[:space:]]*build[[:space:]]*-tags=//p' <<< "$BI")
elif head -c 4 "$H" | grep -q $'\x7fELF'; then
	fail "helper is an ELF but '$GO' cannot read its build info (no host Go?)"
fi
# a Go helper without any test seam (normal build, release-tag variant)
noseam(){
	case ",$TAGS," in *,prov_test,*) fail "$1: helper built with -tags $TAGS" ;; esac
	[ "$(cnt BATMAN_PROV_TEST_BUILD_7f3a)" = 0 ] || fail "$1: helper carries the prov_test marker"
	[ "$(cnt killpoint)" = 0 ] || fail "$1: helper carries killpoint strings ($(cnt killpoint))"
	[ "$(cnt 'claim-after-persist\|claim-before-shadow')" = 0 ] || fail "$1: helper carries killpoint point names"
}

if [ -z "$NAME" ]; then
	[ -z "$WB" ] || fail "/etc/batman-build carries BATMAN_WBOX=$WB in a normal build"
	case "$VER" in *wbox*) fail "version $VER names a wbox variant in a normal build" ;; esac
	[ "$ISGO" = 1 ] || fail "the helper is not a Go binary in a normal build"
	noseam "normal build"
	witnesses
	[ -z "$W" ] || fail "rootfs carries wbox witness strings: $W"
	echo "check-prov-test-gate: ok (no test seam; helper tags=[${TAGS}])"
	exit 0
fi

case "$NAME" in *[!a-z0-9-]*|'') fail "bad wbox name '$NAME'" ;; esac
[ "$WB" = "$NAME" ] || fail "/etc/batman-build BATMAN_WBOX=[$WB], want $NAME"
case "$VER" in *.dirty.wbox-"$NAME") ;; *) fail "version $VER does not end in .dirty.wbox-$NAME" ;; esac
WD=${WBOX_DIR:-$TOP/feeds/batman/tests/wbox}   # override only for the gate self-test
LIST=$WD/helpers.list
[ -f "$LIST" ] || fail "no $LIST"
TAG=$(awk -v n="$NAME" '$1 == n { print $2; exit }' "$LIST")
KIND=$(awk -v n="$NAME" '$1 == n { print $3; exit }' "$LIST")
[ -n "$TAG" ] || fail "$NAME not in helpers.list"
# column 3: `helper` = the variant ships its own helper; `same` = the release helper (a Go binary without any seam)
case "$KIND" in
	helper) ;;
	same) [ "$TAG" = release ] || fail "helpers.list: $NAME is 'same' but tag $TAG"
		[ "$ISGO" = 1 ] || fail "$NAME ships the release helper ('same') but the helper is not a Go binary" ;;
	*) fail "helpers.list helper column '$KIND' for $NAME (want helper or same)" ;;
esac
case "$TAG" in
	prov_test)
		[ "$ISGO" = 1 ] || fail "prov_test variant but the helper is not a Go binary"
		case ",$TAGS," in *,prov_test,*) ;; *) fail "prov_test variant but helper tags=[$TAGS]" ;; esac
		[ "$(cnt BATMAN_PROV_TEST_BUILD_7f3a)" -ge 1 ] || fail "prov_test variant without the marker"
		[ "$(cnt 'killpoint .*: armed')" -ge 1 ] || fail "prov_test variant without the armed-killpoint literal (seam not compiled in)"
		;;
	release) [ "$ISGO" = 0 ] || noseam "release variant $NAME" ;;   # a shell-script helper (helper-exit1) has no tags
	*) fail "helpers.list tag '$TAG' for $NAME (want prov_test or release)" ;;
esac
WANT=""
if [ "$NAME" != test ]; then
	P=$WD/$NAME.patch
	[ -f "$P" ] || fail "no $P"
	WANT=$(sed -n 's/^# wbox-witness: //p' "$P" | head -1)
	[ -n "$WANT" ] || fail "$P has no '# wbox-witness:' line"
	case "$WANT" in WBOX-"$NAME"-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
		*) fail "$P witness '$WANT' is not WBOX-$NAME-<8 hex>" ;; esac
	if grep -qE '^\+\+\+ b/.*/files/etc/init\.d/wbox-' "$P"; then   # an init mutant of any package (r1 A-m4)
		ls "$R"/etc/rc.d/S??wbox-* >/dev/null 2>&1 || fail "init mutant not enabled (no etc/rc.d/S??wbox-*)"
	fi
fi
# exactly this variant's witness (none for `test`): a mutant left behind by an earlier killed build is a FAIL
witnesses
[ "$W" = "$WANT" ] || fail "wbox witnesses in the rootfs [$W], want [$WANT] only"
echo "check-prov-test-gate: ok (wbox $NAME, tag $TAG, $KIND, helper tags=[${TAGS}])"
