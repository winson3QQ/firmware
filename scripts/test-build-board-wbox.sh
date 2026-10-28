#!/bin/bash
# test-build-board-wbox.sh — regression test of the -wbox steps build-board.sh runs (scripts/lib-wbox.sh, sourced as
# is): a fake Batman feed (git repo with tests/wbox/), every case PASSes or FAILs for the listed reason, and the feed
# ends exactly as the case wants (restored, or the developer's work kept). Also checks build-board.sh itself calls
# the lib (so a test of the lib is a test of the build). No build, no network; runs as the tree owner.
#   scripts/test-build-board-wbox.sh [LIB]      LIB defaults to scripts/lib-wbox.sh (mutant runs pass a copy)
set -u
FW=$(cd "$(dirname "$0")/.." && pwd)
LIB=${1:-$FW/scripts/lib-wbox.sh}
[ -f "$LIB" ] || { echo "no $LIB"; exit 1; }
command -v flock >/dev/null || { echo "no flock(1)"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
F=$T/feed
git init -q $F; git -C $F config user.email t@t; git -C $F config user.name t
mkdir -p $F/tests/wbox $F/feed/batman-provision/files/etc/init.d
printf 'test prov_test helper\nhelper-notrial prov_test helper\nchan release same\ntypo prov-test helper\nkind prov_test hlper\n' > $F/tests/wbox/helpers.list
echo base > $F/feed/batman-provision/files/etc/init.d/keep
printf '# wbox chan\n# wbox-witness: WBOX-chan-11223344\n--- /dev/null\n+++ b/feed/batman-provision/files/etc/init.d/wbox-chan\n@@ -0,0 +1 @@\n+WBOX-chan-11223344\n' > $F/tests/wbox/chan.patch
printf '# wbox helper-notrial\n# wbox-witness: WBOX-helper-notrial-55667788\n--- a/feed/batman-provision/files/etc/init.d/keep\n+++ b/feed/batman-provision/files/etc/init.d/keep\n@@ -1 +1 @@\n-base\n+WBOX-helper-notrial-55667788\n' > $F/tests/wbox/helper-notrial.patch
printf '# wbox listedit\n# wbox-witness: WBOX-listedit-0a0a0a0a\n--- a/tests/wbox/helpers.list\n+++ b/tests/wbox/helpers.list\n@@ -1 +1 @@\n-test prov_test helper\n+test release same\n' > $F/tests/wbox/listedit.patch
mkdir -p $F/feed/other; echo o > $F/feed/other/x
printf '# wbox-witness: WBOX-otherpkg-0b0b0b0b\n--- a/feed/other/x\n+++ b/feed/other/x\n@@ -1 +1 @@\n-o\n+WBOX-otherpkg-0b0b0b0b\n' > $F/tests/wbox/otherpkg.patch
printf 'listedit release same\notherpkg release same\n' >> $F/tests/wbox/helpers.list
printf '/ignored-*\n' > $F/.gitignore
git -C $F add -A; git -C $F commit -qm base
pass=0; bad=0
res(){ if [ "$1" = 1 ]; then pass=$((pass+1)); echo "ok   $2"; else bad=$((bad+1)); echo "BAD  $2 — $3"; fi; }
clean(){ [ -z "$(git -C $F status --porcelain --ignored)" ]; }
# run NAME [ENV...]: wbox_apply in a child shell that sources the lib (like build-board.sh); prints the child's
# output then "APPLIED <BATMAN_WBOX> <BATMAN_PROV_TEST> <keep content>" as seen INSIDE the child, before its trap
run(){ local n=$1; shift; env "$@" bash -c '. "$1"; wbox_env_reset; set -e; wbox_apply "$2" "$3"
	echo "APPLIED ${BATMAN_WBOX:-} ${BATMAN_PROV_TEST:-0} $(cat "$3"/feed/batman-provision/files/etc/init.d/keep) $(ls "$3"/feed/batman-provision/files/etc/init.d | tr "\n" ,)"' _ "$LIB" "$n" "$F" 2>&1; }
# case DESC NAME want-substring [setup] — setup runs before, the feed must be clean after unless setup dirtied it
ok_case(){ local d=$1 n=$2 w=$3 o; o=$(run "$n"); case "$o" in *"$w"*) clean && res 1 "$d" || res 0 "$d" "feed not restored: $(git -C $F status --porcelain --ignored | tr '\n' ' ')" ;; *) res 0 "$d" "$o" ;; esac; }
no_case(){ local d=$1 n=$2 w=$3 o rc; o=$(run "$n"); rc=$?
	if [ $rc != 0 ] && case "$o" in *"$w"*) true ;; *) false ;; esac && ! case "$o" in *APPLIED*) true ;; *) false ;; esac; then res 1 "$d"; else res 0 "$d" "rc=$rc $o"; fi; }

ok_case "test: no patch, prov_test exported, restored" test "APPLIED test 1 base keep,"
ok_case "chan: patch applied inside, release tag, restored after" chan "APPLIED chan 0 base keep,wbox-chan,"
ok_case "helper-notrial: tracked file patched inside, restored after" helper-notrial "APPLIED helper-notrial 1 WBOX-helper-notrial-55667788"
no_case "name not in helpers.list" nope "nope is not in"
no_case "bad name" 'Bad_Name' "bad --wbox name"
no_case "empty name" '' "bad --wbox name"
no_case "tag typo" typo "tag 'prov-test' for typo"
no_case "helper column typo" kind "helper column 'hlper' for kind"
# a dirty feed is refused and the dirt is KEPT (the trap must not be armed yet)
echo dev-work >> $F/feed/batman-provision/files/etc/init.d/keep
no_case "tracked change -> refused" chan "is not clean"
[ "$(tail -1 $F/feed/batman-provision/files/etc/init.d/keep)" = dev-work ] && res 1 "tracked change kept" || res 0 "tracked change kept" "the developer's change was wiped"
git -C $F checkout -q -- .
echo x > $F/untracked-file
no_case "untracked file -> refused" chan "is not clean"
[ -f $F/untracked-file ] && res 1 "untracked file kept" || res 0 "untracked file kept" "wiped"
rm -f $F/untracked-file
echo x > $F/ignored-1
no_case "ignored file -> refused" chan "is not clean"
[ -f $F/ignored-1 ] && res 1 "ignored file kept" || res 0 "ignored file kept" "wiped"
rm -f $F/ignored-1
# a leftover mutant from a SIGKILLed build (its trap never ran) is refused, not stacked
git -C $F apply tests/wbox/chan.patch
no_case "leftover mutant -> refused" helper-notrial "is not clean"
[ -f $F/feed/batman-provision/files/etc/init.d/wbox-chan ] && res 1 "leftover kept for inspection" || res 0 "leftover kept for inspection" "wiped"
git -C $F clean -qfdx; clean && res 1 "feed clean again" || res 0 "feed clean again" "$(git -C $F status --porcelain)"
# a mutant may only touch the two packages the stamp step cleans (r3 A-m5)
no_case "patch that edits tests/wbox/helpers.list -> refused" listedit "touches files outside"
no_case "patch that edits another package -> refused" otherpkg "touches files outside"
clean && res 1 "feed clean after refused patches" || res 0 "feed clean after refused patches" "$(git -C $F status --porcelain --ignored | tr '\n' ' ')"
# an ignored file made during the build (a variant's build output in the feed) goes too: clean -x (r3 A-m1)
bash -c '. "$1"; set -e; wbox_apply chan "$2" >/dev/null; echo gen > "$2"/ignored-gen' _ "$LIB" "$F"
clean && res 1 "ignored file made during the build -> removed on exit" || res 0 "ignored file made during the build" "$(git -C $F status --porcelain --ignored | tr '\n' ' ')"
# a normal build refuses a leftover mutant (killed -wbox build), allows other uncommitted work (r3 B-m4)
nc(){ bash -c '. "$1"; wbox_normal_check "$2"; echo NORMAL-OK' _ "$LIB" "$F" 2>&1; }
git -C $F apply tests/wbox/chan.patch
o=$(nc); case "$o" in *"still carries a wbox mutant"*wbox-chan*) res 1 "normal build: leftover untracked mutant -> refused" ;; *) res 0 "normal build: leftover untracked mutant" "$o" ;; esac
git -C $F clean -qfdx; git -C $F apply tests/wbox/helper-notrial.patch
o=$(nc); case "$o" in *"still carries a wbox mutant"*keep*) res 1 "normal build: leftover tracked mutant -> refused" ;; *) res 0 "normal build: leftover tracked mutant" "$o" ;; esac
git -C $F checkout -q -- .; echo WBOX-chan-11223344 > $F/ignored-w
o=$(nc); case "$o" in *"still carries a wbox mutant"*ignored-w*) res 1 "normal build: ignored file with a witness -> refused" ;; *) res 0 "normal build: ignored witness" "$o" ;; esac
rm -f $F/ignored-w; echo dev >> $F/feed/batman-provision/files/etc/init.d/keep; echo x > $F/untracked-dev
o=$(nc); [ "$o" = NORMAL-OK ] && res 1 "normal build: other uncommitted work allowed" || res 0 "normal build: other work" "$o"
git -C $F checkout -q -- .; git -C $F clean -qfdx
for sig in TERM INT HUP; do
	# like build-board.sh under a terminal: no trap but the lib's EXIT trap, the long step (here sleep, there make) in
	# the FOREGROUND, the job in its own process group with SIGINT/SIGTERM at their defaults, and the signal sent to the
	# whole group (what Ctrl-C does). No helper trap that would make the case pass on its own.
	setsid perl -e '$SIG{INT}="DEFAULT"; $SIG{TERM}="DEFAULT"; $SIG{HUP}="DEFAULT"; exec @ARGV or die' \
		bash -c '. "$1"; set -e; wbox_apply chan "$2" >/dev/null; sleep 30' _ "$LIB" "$F" & p=$!
	for i in $(seq 50); do [ -f $F/feed/batman-provision/files/etc/init.d/wbox-chan ] && break; sleep 0.1; done
	[ -f $F/feed/batman-provision/files/etc/init.d/wbox-chan ] || res 0 "SIG$sig mid-build" "patch never applied"
	kill -$sig -- -$p; for i in $(seq 100); do kill -0 $p 2>/dev/null || break; sleep 0.1; done
	wait $p 2>/dev/null; rc=$?
	clean && [ $rc -ge 128 ] && res 1 "SIG$sig to the job's group mid-build -> rc $rc, restored" || res 0 "SIG$sig mid-build -> restored" "rc=$rc $(git -C $F status --porcelain --ignored | tr '\n' ' ')"
done
# environment from the calling shell never reaches a normal build
o=$(env BATMAN_WBOX=chan BATMAN_PROV_TEST=1 GO_PKG_TAGS=prov_test GOFLAGS=-tags=prov_test bash -c '. "$1"; wbox_env_reset; echo "[${BATMAN_WBOX:-}][${BATMAN_PROV_TEST:-}][${GO_PKG_TAGS:-}][${GOFLAGS:-}]"' _ "$LIB")
[ "$o" = "[][][][]" ] && res 1 "inherited BATMAN_WBOX / BATMAN_PROV_TEST / GO_PKG_TAGS / GOFLAGS unset" || res 0 "inherited env unset" "$o"
# stamp: changed -> clean + in-progress; done -> NOW; same -> no clean; interrupted (in-progress) -> clean again
ST=$T/stamp; CL=$T/cleaned
st(){ bash -c '. "$1"; wbox_stamp_begin "$2" "$3" touch "$4"' _ "$LIB" "$ST" "$1" "$CL" >/dev/null; }
rm -f $CL; st 'test|1'; [ -f $CL ] && [ "$(cat $ST)" = 'in-progress:test|1' ] && res 1 "stamp: no stamp -> clean, in-progress" || res 0 "stamp: no stamp" "$(cat $ST 2>&1)"
bash -c '. "$1"; wbox_stamp_done "$2" "test|1"' _ "$LIB" "$ST"
rm -f $CL; st 'test|1'; [ ! -f $CL ] && res 1 "stamp: same variant finished -> no clean" || res 0 "stamp: same variant" "cleaned"
rm -f $CL; st 'none|0'; [ -f $CL ] && res 1 "stamp: variant changed -> clean" || res 0 "stamp: changed" "not cleaned"
rm -f $CL; st 'none|0'; [ -f $CL ] && res 1 "stamp: interrupted build (in-progress) -> clean again" || res 0 "stamp: interrupted" "not cleaned"
o=$(bash -c '. "$1"; wbox_stamp_begin "$2" "x|0" false; echo survived' _ "$LIB" "$ST" 2>&1); [ "$o" != "${o%survived}" ] && res 0 "stamp: clean failure stops the build" "$o" || res 1 "stamp: clean failure stops the build"
# one build per tree
L=$T/lock
bash -c '. "$1"; bb_lock "$2"; sleep 5' _ "$LIB" "$L" & p=$!; sleep 0.5
o=$(bash -c '. "$1"; bb_lock "$2"; echo got-lock' _ "$LIB" "$L" 2>&1); rc=$?
[ $rc = 2 ] && case "$o" in *"another build-board.sh holds"*) true ;; *) false ;; esac && res 1 "second build refused while the first holds the lock" || res 0 "lock" "rc=$rc $o"
kill $p; wait $p 2>/dev/null
o=$(bash -c '. "$1"; bb_lock "$2"; echo got-lock' _ "$LIB" "$L" 2>&1); [ "$o" = got-lock ] && res 1 "lock free again after the holder exits" || res 0 "lock released" "$o"
# build-board.sh really uses these functions (a test of the lib is a test of the build)
B=$FW/scripts/build-board.sh
for w in '. scripts/lib-wbox.sh' 'bb_lock logs/.build-board.lock' 'wbox_env_reset' 'wbox_apply "$WBOX" feeds/batman' 'wbox_normal_check feeds/batman' 'wbox_stamp_begin "$WBSTAMP" "$WBNOW" wbclean' 'wbox_stamp_done "$WBSTAMP" "$WBNOW"'; do
	grep -qF -- "$w" $B && res 1 "build-board.sh calls: $w" || res 0 "build-board.sh calls: $w" "missing"
done
[ -z "$(grep -n 'git -C feeds/batman apply\|unset BATMAN_WBOX' $B)" ] && res 1 "build-board.sh has no second copy of the steps" || res 0 "no second copy" "$(grep -n 'git -C feeds/batman apply\|unset BATMAN_WBOX' $B)"
# ... and in this order (a step moved after make would only be caught by the gate, after a whole build — r3 B-m2):
# lock -> env reset -> setup done -> apply / normal check -> stamp begin -> make -> stamp done -> step 7 gate
ln(){ grep -nF -- "$1" $B | head -1 | cut -d: -f1; }
prev=0; prevw=start
for w in 'bb_lock logs/.build-board.lock' 'wbox_env_reset' 'sh scripts/check-golang-rules.sh' 'wbox_apply "$WBOX" feeds/batman' 'wbox_normal_check feeds/batman' 'wbox_stamp_begin "$WBSTAMP" "$WBNOW" wbclean' 'make -j"$JOBS"' 'wbox_stamp_done "$WBSTAMP" "$WBNOW"' 'bash scripts/check-prov-test-gate.sh'; do
	n=$(ln "$w"); if [ -n "$n" ] && [ "$n" -gt "$prev" ]; then res 1 "build-board.sh order: $prevw < $w"; else res 0 "build-board.sh order" "$w at line [$n], not after $prevw (line $prev)"; fi
	prev=${n:-0}; prevw=$w
done
echo "RESULT build-board wbox test: $pass ok, $bad bad"; [ $bad = 0 ] && [ $pass -gt 0 ]
