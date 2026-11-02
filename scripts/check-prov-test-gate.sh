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
#   build); an init mutant is enabled (etc/rc.d/S??wbox-*); the node-side product gate (batman-slot wbox_gate_self /
#   wbox_gate_target, autocommit WBOX_STATE / WBOX-NOCOMMIT) is in the image.
# Any input that cannot be read is a FAIL, never a pass.
#
# Self-test overrides come ONLY as options (security review F5, design 254-h23 §20.5 / §23.5): environment variables
# are inherited by every child, so the gate reads no WBOX_DIR / GO from the environment.
#   --selftest-wbox-dir DIR   helpers.list + patches from DIR instead of feeds/batman/tests/wbox
#   --selftest-go GO          this Go for `go version -m` instead of the tree's own
# Any other --option is a FAIL (an option that looked like a variant name would pass the name check).
set -u
fail(){ echo "check-prov-test-gate: FAIL: $*" >&2; exit 1; }
POS=(); OPT_WD=""; OPT_GO=""
while [ $# -gt 0 ]; do
	case "$1" in
		--selftest-wbox-dir) [ $# -ge 2 ] || fail "--selftest-wbox-dir needs a dir"; OPT_WD=$2; shift 2 ;;
		--selftest-go) [ $# -ge 2 ] || fail "--selftest-go needs a path"; OPT_GO=$2; shift 2 ;;
		--*) fail "unknown option $1" ;;
		*) POS+=("$1"); shift ;;
	esac
done
[ "${#POS[@]}" -ge 1 ] && [ "${#POS[@]}" -le 2 ] || fail "usage: check-prov-test-gate.sh ROOTFS_DIR [WBOX_NAME] [--selftest-wbox-dir DIR] [--selftest-go GO]"
R=${POS[0]}
NAME=${POS[1]:-}
TOP=$(cd "$(dirname "$0")/.." && pwd)
H=$R/usr/bin/batman-provhelper
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
GO=${OPT_GO:-$TOP/staging_dir/hostpkg/lib/go-$GOV/bin/go}   # the tree's own Go (build-board.sh step 5); never from the environment
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

# #254 P2 (Batman docs/design/254-p2-impl.md §9): batman-provd in its release shape — no prov_test switch or frame
# socket in the binary, the release init (it never reads provd.env), the provd dbus policy, the root policy's
# call-back lines without a destination (§4.7: that is what lets bluetoothd call provd's objects), no btmgmt.
# A rootfs without provd (a pre-P2 Batman pin) has nothing to check.
provd_release(){
	local P=$R/usr/bin/batman-provd I=$R/etc/init.d/batman-provd C=$R/etc/dbus-1/system.d/bluetooth.conf n i
	[ -e "$P" ] || [ -L "$P" ] || return 0
	[ -f "$P" ] && [ ! -L "$P" ] || fail "$1: /usr/bin/batman-provd is a symlink or not a regular file"
	n=$(strings "$P" | grep -c -e SOCK_ONLY -e ADV_LEN_TEST -e provd-test)
	[ "$n" = 0 ] || fail "$1: batman-provd carries prov_test strings ($n)"
	[ -f "$I" ] && [ ! -L "$I" ] || fail "$1: no regular /etc/init.d/batman-provd"
	! grep -q provd.env "$I" || fail "$1: /etc/init.d/batman-provd is the prov_test init (reads provd.env)"
	[ -f "$C" ] && [ ! -L "$C" ] || fail "$1: no regular /etc/dbus-1/system.d/bluetooth.conf"
	grep -q '<policy user="provd">' "$C" || fail "$1: bluetooth.conf has no provd policy"
	for i in org.bluez.GattCharacteristic1 org.bluez.GattDescriptor1 org.bluez.LEAdvertisement1 \
		org.freedesktop.DBus.ObjectManager org.freedesktop.DBus.Properties; do
		grep -qF "<allow send_interface=\"$i\"/>" "$C" || fail "$1: bluetooth.conf root call-back line for $i is gone or has a destination"
	done
	[ ! -e "$R/usr/bin/btmgmt" ] || fail "$1: btmgmt in a release image"
}

if [ -z "$NAME" ]; then
	[ -z "$WB" ] || fail "/etc/batman-build carries BATMAN_WBOX=$WB in a normal build"
	case "$VER" in *wbox*) fail "version $VER names a wbox variant in a normal build" ;; esac
	[ "$ISGO" = 1 ] || fail "the helper is not a Go binary in a normal build"
	noseam "normal build"
	# the whole rootfs, not only /usr/bin/batman-provhelper: a prov_test binary under another name or path is caught
	# too (security review F3). grep rc 2 (a file it could not read) = FAIL, not "none".
	for pat in BATMAN_PROV_TEST_BUILD_7f3a 'killpoint [^ ]*: armed'; do
		hit=$(cd "$R" && grep -rlaE -- "$pat" . 2>/dev/null); rc=$?
		[ $rc -le 1 ] || fail "cannot scan the rootfs for test seams (grep rc $rc)"
		[ -z "$hit" ] || fail "normal build: rootfs carries a test seam ($pat) in: $(echo $hit | cut -c1-200)"
	done
	witnesses
	[ -z "$W" ] || fail "rootfs carries wbox witness strings: $W"
	provd_release "normal build"
	echo "check-prov-test-gate: ok (no test seam; helper tags=[${TAGS}]$([ -f "$R/usr/bin/batman-provd" ] && echo "; provd release"))"
	exit 0
fi

case "$NAME" in *[!a-z0-9-]*|'') fail "bad wbox name '$NAME'" ;; esac
# the node-side product gate (Batman 5a7e9f3, security review F1) must be in every wbox image: built from a pre-gate pin,
# a healthy trial of the mutant would be committed (code review A-M1 / B-M1). Regular files, not symlinks.
for kv in "usr/sbin/batman-slot:wbox_gate_self" "usr/sbin/batman-slot:wbox_gate_target" "usr/sbin/batman-slot:holds a -wbox test image" \
	"usr/bin/batman-autocommit:WBOX_STATE" "usr/bin/batman-autocommit:WBOX-NOCOMMIT"; do
	f=$R/${kv%%:*}; s=${kv#*:}
	[ -f "$f" ] && [ ! -L "$f" ] || fail "wbox image without ${kv%%:*} (or it is a symlink)"
	grep -qF -- "$s" "$f" || fail "wbox image without the node gate ('$s' missing in ${kv%%:*}) — built from a pre-gate Batman pin"
done
[ "$WB" = "$NAME" ] || fail "/etc/batman-build BATMAN_WBOX=[$WB], want $NAME"
case "$VER" in *.dirty.wbox-"$NAME") ;; *) fail "version $VER does not end in .dirty.wbox-$NAME" ;; esac
WD=${OPT_WD:-$TOP/feeds/batman/tests/wbox}   # --selftest-wbox-dir only; never from the environment
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
