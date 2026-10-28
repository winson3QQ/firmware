#!/bin/bash
# test-prov-test-gate.sh — self-test of scripts/check-prov-test-gate.sh: every case must PASS, or FAIL for the
# listed reason (a FAIL for another reason is BAD: it would hide that the listed check is gone).
# Builds real arm64 helpers (-s -w -trimpath, like OpenWrt) from BATMAN_SRC: release, prov_test, and mutants:
#   h-mut   prov_test build whose seam stayed in a _test.go file (marker, no armed literal)
#   h-mark  release build that carries the marker string only
#   h-kp    release build that carries a "killpoint" string only
#   h-names release build that carries a point name only; h-nomark prov_test build without the marker
#   BATMAN_SRC=<batman-prov/src> [GO=<go>] scripts/test-prov-test-gate.sh
set -u
FW=$(cd "$(dirname "$0")/.." && pwd); G=$FW/scripts/check-prov-test-gate.sh
SRC=${BATMAN_SRC:?BATMAN_SRC = a batman-prov/src with the seam package}
# the pinned Batman must carry the P1b seams (seam/points.go + seam/seam_provtest.go): an older pin cannot build the
# helpers this test needs. Say so plainly instead of failing on a mutant (r2 A-m3 / B-m8). Merge order: Batman P1b
# first, then the firmware PR that pins it.
[ -f "$SRC/seam/points.go" ] && [ -f "$SRC/seam/seam_provtest.go" ] || {
	echo "BATMAN_SRC $SRC predates the #254 P1b seams (no seam/points.go / seam/seam_provtest.go): pin a Batman that has them"; exit 1; }
GO=${GO:-$FW/staging_dir/hostpkg/lib/go-$(sed -n 's/^GO_DEFAULT_VERSION:=//p' $FW/feeds/openmanet/lang/golang/golang-values.mk | head -1)/bin/go}
[ -x "$GO" ] || { echo "no Go at $GO"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GOFLAGS=-mod=vendor GOTOOLCHAIN=local GOCACHE=$T/gocache GOARCH=arm64 CGO_ENABLED=0
b(){ (cd "$1" && "$GO" build -trimpath -buildvcs=false ${2:+-tags $2} -ldflags='-s -w' -o "$3" ./cmd/batman-provhelper) || { echo "build of $3 failed"; exit 1; }; }
sc(){ strings "$1" | grep -c -- "$2"; }
# need <helper> <pattern> <op> <n> — every helper is checked to be what its case assumes before any case runs
need(){ [ "$(sc "$1" "$2")" "$3" "$4" ] || { echo "precondition: $(basename "$1") has $(sc "$1" "$2") x [$2], want $3 $4"; exit 1; }; }
b "$SRC" "" $T/h-rel; b "$SRC" prov_test $T/h-pt
need $T/h-rel killpoint -eq 0; need $T/h-rel BATMAN_PROV_TEST_BUILD_7f3a -eq 0; need $T/h-pt 'killpoint .*: armed' -ge 1; need $T/h-pt BATMAN_PROV_TEST_BUILD_7f3a -ge 1
# h-mut: the seam implementation moved into a _test.go file (not linked) behind a stub with the marker
cp -r "$SRC" $T/msrc; mv $T/msrc/seam/seam_provtest.go $T/msrc/seam/zz_impl_test.go; rm -f $T/msrc/seam/hook_provtest.go $T/msrc/seam/*_test.go $T/msrc/node/seam_points_test.go
sed -i 's#^//go:build !prov_test#//go:build never#' $T/msrc/seam/seam_release.go
printf '//go:build prov_test\n\npackage seam\n\nconst Marker = "BATMAN_PROV_TEST_BUILD_7f3a"\nconst Enabled = true\n\nfunc Arm(func(string, ...any))        {}\nfunc At(Point, func(string, ...any)) {}\n' > $T/msrc/seam/stub.go
b $T/msrc prov_test $T/h-mut; need $T/h-mut BATMAN_PROV_TEST_BUILD_7f3a -ge 1; need $T/h-mut 'killpoint .*: armed' -eq 0
# h-nomark: a prov_test build whose marker is gone (armed literal still there)
cp -r "$SRC" $T/nsrc; sed -i 's#^const Marker = "BATMAN_PROV_TEST_BUILD_7f3a"#const Marker = "NOT_THE_MARKER"#' $T/nsrc/seam/seam_provtest.go
b $T/nsrc prov_test $T/h-nomark; need $T/h-nomark BATMAN_PROV_TEST_BUILD_7f3a -eq 0; need $T/h-nomark 'killpoint .*: armed' -ge 1
# h-mark / h-kp / h-names: release builds that carry one forbidden string each (a runtime-guarded println keeps it)
probe(){ printf '\nvar probe%s int\n\nfunc init() {\n\tif probe%s > 0 {\n\t\tprintln("%s")\n\t}\n}\n' "$1" "$1" "$2"; }
cp -r "$SRC" $T/ksrc; probe M BATMAN_PROV_TEST_BUILD_7f3a >> $T/ksrc/seam/seam_release.go; b $T/ksrc "" $T/h-mark
need $T/h-mark BATMAN_PROV_TEST_BUILD_7f3a -ge 1; need $T/h-mark killpoint -eq 0
cp -r "$SRC" $T/psrc; probe K "killpoint probe" >> $T/psrc/seam/seam_release.go; b $T/psrc "" $T/h-kp
need $T/h-kp killpoint -ge 1; need $T/h-kp BATMAN_PROV_TEST_BUILD_7f3a -eq 0
cp -r "$SRC" $T/qsrc; probe N claim-before-shadow >> $T/qsrc/seam/seam_release.go; b $T/qsrc "" $T/h-names
need $T/h-names claim-before-shadow -ge 1; need $T/h-names killpoint -eq 0; need $T/h-names BATMAN_PROV_TEST_BUILD_7f3a -eq 0
mkdir -p $T/wbox
printf 'test prov_test helper\nhelper-notrial prov_test helper\n96-noprov release same\nchan release same\ntypo prov-test helper\nkindtypo prov_test hlper\nsamept prov_test same\nbadwit release same\ninitx release same\nhelper-exit1 release helper\nnopatch release same\nnowit release same\nmisc-l38 release same\n' > $T/wbox/helpers.list
printf '# wbox 96-noprov: 96 does not copy prov\n# wbox-witness: WBOX-96-noprov-0a1b2c3d\n+++ b/feed/batman-provision/files/etc/uci-defaults/96\n' > $T/wbox/96-noprov.patch
printf '# wbox chan: channel mutant\n# wbox-witness: WBOX-chan-11223344\n+++ b/feed/batman-provision/files/etc/init.d/wbox-chan\n' > $T/wbox/chan.patch
printf '# wbox helper-notrial\n# wbox-witness: WBOX-helper-notrial-55667788\n+++ b/feed/batman-prov/src/node/node.go\n' > $T/wbox/helper-notrial.patch
printf '# wbox typo\n# wbox-witness: WBOX-typo-99aabbcc\n' > $T/wbox/typo.patch
printf '# wbox badwit\n# wbox-witness: WBOX-badwit-zz\n' > $T/wbox/badwit.patch
printf '# wbox initx: init mutant in another package\n# wbox-witness: WBOX-initx-0badf00d\n+++ b/feed/batman-prov/files/etc/init.d/wbox-initx\n' > $T/wbox/initx.patch
printf '# wbox helper-exit1\n# wbox-witness: WBOX-helper-exit1-1234abcd\n+++ b/feed/batman-prov/files/usr/bin/batman-provhelper\n' > $T/wbox/helper-exit1.patch
printf '# wbox nowit: no witness line\n+++ b/feed/batman-provision/files/etc/uci-defaults/97\n' > $T/wbox/nowit.patch
printf '# wbox misc-l38: autocommit mutant\n# wbox-witness: WBOX-misc-l38-6a1c9e30\n+++ b/feed/batman-provision/files/usr/bin/batman-autocommit\n' > $T/wbox/misc-l38.patch
# mk <dir> <helper> <version> [wbox] [witness...] — witnesses ending in .rcd make etc/rc.d/<name> instead
mk(){ local d=$T/$1 h=$2 v=$3 wb=${4:-} i=0; shift 3; [ $# -gt 0 ] && shift
  mkdir -p $d/etc/rc.d $d/usr/bin; cp $h $d/usr/bin/batman-provhelper
  { echo "BATMAN_VERSION=$v"; [ -n "$wb" ] && echo "BATMAN_WBOX=$wb"; } > $d/etc/batman-build
  for x in "$@"; do case "$x" in *.rcd) touch $d/etc/rc.d/${x%.rcd} ;; *) i=$((i+1)); echo "$x" > $d/etc/wbox-witness-$i ;; esac; done
  echo $d; }
pass=0; bad=0
# want PASS <case> <args...> | want FAIL:<reason substring> <case> <args...>
want(){ local exp=$1 name=$2; shift 2; out=$(env -u GO -u WBOX_DIR bash $G "$@" --selftest-wbox-dir $T/wbox --selftest-go $GO 2>&1); rc=$?
  case "$exp" in
	PASS) [ $rc = 0 ] && ok=1 || ok=0 ;;
	FAIL:*) [ $rc != 0 ] && case "$out" in *"${exp#FAIL:}"*) ok=1 ;; *) ok=0 ;; esac || ok=0 ;;
  esac
  if [ $ok = 1 ]; then pass=$((pass+1)); echo "ok   $name — $out"; else bad=$((bad+1)); echo "BAD  want $exp: $name — rc=$rc $out"; fi; }
V=1.5.14-wsl.5+abc1234.fwdef5678
want PASS                         "release build"                        $(mk r1 $T/h-rel $V)
want FAIL:"-tags prov_test"       "normal build with prov_test helper"   $(mk r2 $T/h-pt $V)
want FAIL:"prov_test marker"      "normal build, marker only"            $(mk r2m $T/h-mark $V)
want FAIL:"killpoint strings"     "normal build, killpoint string only"  $(mk r2k $T/h-kp $V)
want FAIL:"carries BATMAN_WBOX"   "normal build with BATMAN_WBOX line"   $(mk r3 $T/h-rel $V x)
want FAIL:"witness strings"       "normal build with a witness string"   $(mk r4 $T/h-rel $V "" WBOX-x-00000000)
printf '#!/bin/sh\nexit 1\n' > $T/h-sh; chmod 755 $T/h-sh
want FAIL:"not a Go binary"       "normal build, helper is a shell script" $(mk r5 $T/h-sh $V)
d=$(mk r6 $T/h-rel $V); echo WBOX-x-00000000 > $d/etc/unreadable; chmod 000 $d/etc/unreadable
if [ "$(id -u)" = 0 ]; then echo "skip unreadable-file case as root (root reads mode 000)"; else
want FAIL:"cannot scan"           "normal build, unreadable file"        $d; fi
want PASS                         "wbox test"                            $(mk w1 $T/h-pt $V.dirty.wbox-test test) test
want FAIL:"seam not compiled in"  "wbox test, seam not compiled in (mutant)" $(mk w2 $T/h-mut $V.dirty.wbox-test test) test
want FAIL:"helper tags=[]"        "wbox test, release helper"            $(mk w3 $T/h-rel $V.dirty.wbox-test test) test
want FAIL:"does not end in"       "wbox test, version not .dirty.wbox-test" $(mk w4 $T/h-pt $V.dirty test) test
want FAIL:"want [] only"          "wbox test + a leftover mutant's witness" $(mk w4b $T/h-pt $V.dirty.wbox-test test WBOX-chan-11223344) test
want PASS                         "wbox helper-notrial"                  $(mk w5 $T/h-pt $V.dirty.wbox-helper-notrial helper-notrial WBOX-helper-notrial-55667788) helper-notrial
want FAIL:"want [WBOX-helper-notrial-55667788] only" "wbox helper-notrial, witness lost" $(mk w6 $T/h-pt $V.dirty.wbox-helper-notrial helper-notrial) helper-notrial
want PASS                         "wbox 96-noprov (release helper)"      $(mk w7 $T/h-rel $V.dirty.wbox-96-noprov 96-noprov WBOX-96-noprov-0a1b2c3d) 96-noprov
want FAIL:"release variant 96-noprov: helper built with -tags" "wbox 96-noprov with a prov_test helper" $(mk w7b $T/h-pt $V.dirty.wbox-96-noprov 96-noprov WBOX-96-noprov-0a1b2c3d) 96-noprov
want FAIL:"want [WBOX-96-noprov-0a1b2c3d] only" "wbox 96-noprov + chan's witness (stacked)" $(mk w7c $T/h-rel $V.dirty.wbox-96-noprov 96-noprov WBOX-96-noprov-0a1b2c3d WBOX-chan-11223344) 96-noprov
want PASS                         "wbox chan, enabled"                   $(mk w8 $T/h-rel $V.dirty.wbox-chan chan WBOX-chan-11223344 S99wbox-chan.rcd) chan
want FAIL:"init mutant not enabled" "wbox chan, not enabled"             $(mk w9 $T/h-rel $V.dirty.wbox-chan chan WBOX-chan-11223344) chan
want FAIL:"not in helpers.list"   "wbox name not in helpers.list"        $(mk wa $T/h-pt $V.dirty.wbox-nope nope) nope
want FAIL:"tag 'prov-test'"       "helpers.list tag typo"                $(mk wb $T/h-pt $V.dirty.wbox-typo typo WBOX-typo-99aabbcc) typo
want FAIL:"names a wbox variant"  "normal build, version names a wbox variant" $(mk r7 $T/h-rel $V.dirty.wbox-x)
want FAIL:"point names"           "normal build, point names only"       $(mk r8 $T/h-names $V)
d=$(mk r9 $T/h-rel $V); rm $d/usr/bin/batman-provhelper; ln -s $T/h-rel $d/usr/bin/batman-provhelper
want FAIL:"is a symlink"          "normal build, helper is an absolute symlink to a host file" $d
d=$(mk ra $T/h-rel $V); out=$(bash $G $d --selftest-go $T/no-go 2>&1); rc=$?
case "$out" in *"cannot read its build info"*) [ $rc != 0 ] && { pass=$((pass+1)); echo "ok   ELF helper but no host Go — $out"; } || { bad=$((bad+1)); echo "BAD  ELF/no Go rc=$rc $out"; } ;; *) bad=$((bad+1)); echo "BAD  ELF/no Go: $out" ;; esac
want FAIL:"bad wbox name"         "wbox name with bad characters"        $(mk rb $T/h-pt $V.dirty.wbox-Bad_Name Bad_Name) Bad_Name
want FAIL:"without the marker"    "wbox test, prov_test helper without the marker" $(mk rc $T/h-nomark $V.dirty.wbox-test test) test
want FAIL:"is not WBOX-badwit-<8 hex>" "witness of the wrong format"     $(mk rd $T/h-rel $V.dirty.wbox-badwit badwit WBOX-badwit-zz) badwit
want FAIL:"helper column 'hlper'" "helpers.list helper column typo"      $(mk re $T/h-pt $V.dirty.wbox-kindtypo kindtypo) kindtypo
want FAIL:"is 'same' but tag prov_test" "'same' with a prov_test tag"    $(mk rf $T/h-pt $V.dirty.wbox-samept samept) samept
want FAIL:"ships the release helper ('same') but the helper is not a Go binary" "'same' variant with a shell-script helper" $(mk rg $T/h-sh $V.dirty.wbox-96-noprov 96-noprov WBOX-96-noprov-0a1b2c3d) 96-noprov
want PASS                         "helper-exit1 (shell-script helper, release, helper)" $(mk rh $T/h-sh $V.dirty.wbox-helper-exit1 helper-exit1 WBOX-helper-exit1-1234abcd) helper-exit1
want FAIL:"init mutant not enabled" "init mutant in another package, not enabled" $(mk ri $T/h-rel $V.dirty.wbox-initx initx WBOX-initx-0badf00d) initx
want PASS                         "init mutant in another package, enabled" $(mk rj $T/h-rel $V.dirty.wbox-initx initx WBOX-initx-0badf00d S95wbox-initx.rcd) initx
want FAIL:"point names"           "release variant, point names only"    $(mk rk $T/h-names $V.dirty.wbox-chan chan WBOX-chan-11223344 S99wbox-chan.rcd) chan
d=$(mk rl $T/h-rel $V); rm $d/etc/batman-build
want FAIL:"has no /etc/batman-build" "rootfs without /etc/batman-build"  $d
d=$(mk rm $T/h-rel $V); rm $d/usr/bin/batman-provhelper
want FAIL:"has no /usr/bin/batman-provhelper" "rootfs without the helper" $d
mkdir -p $T/nostrings; for t in sed awk grep head sort tr ls dirname cat; do ln -sf "$(command -v $t)" $T/nostrings/$t; done
d=$(mk rn $T/h-rel $V); out=$(PATH=$T/nostrings $(command -v bash) $G $d --selftest-go $GO 2>&1); rc=$?
case "$out" in *"no strings(1)"*) [ $rc != 0 ] && { pass=$((pass+1)); echo "ok   no strings(1) on the host — $out"; } || { bad=$((bad+1)); echo "BAD  no strings rc=$rc"; } ;; *) bad=$((bad+1)); echo "BAD  no strings: rc=$rc $out" ;; esac
want FAIL:"BATMAN_WBOX=[test], want chan" "BATMAN_WBOX line names another variant" $(mk ro $T/h-rel $V.dirty.wbox-chan test WBOX-chan-11223344 S99wbox-chan.rcd) chan
d=$(mk rp $T/h-pt $V.dirty.wbox-test test); out=$(bash $G $d test --selftest-wbox-dir $T/no-such-dir --selftest-go $GO 2>&1); rc=$?
case "$out" in *"no $T/no-such-dir/helpers.list"*) [ $rc != 0 ] && { pass=$((pass+1)); echo "ok   no helpers.list — $out"; } || { bad=$((bad+1)); echo "BAD  no helpers.list rc=$rc"; } ;; *) bad=$((bad+1)); echo "BAD  no helpers.list: rc=$rc $out" ;; esac
want FAIL:"prov_test variant but the helper is not a Go binary" "prov_test variant with a shell-script helper" $(mk rq $T/h-sh $V.dirty.wbox-test test) test
want FAIL:"FAIL: no $T/wbox/nopatch.patch"         "helpers.list entry without a patch"   $(mk rr $T/h-rel $V.dirty.wbox-nopatch nopatch) nopatch
want FAIL:"has no '# wbox-witness:' line" "patch without a witness line" $(mk rs $T/h-rel $V.dirty.wbox-nowit nowit) nowit
d=$(mk rt $T/h-rel $V); printf 'BATMAN_VERSION=%s\n' "$V" > $T/host-batman-build; rm $d/etc/batman-build; ln -s $T/host-batman-build $d/etc/batman-build
want FAIL:"/etc/batman-build is a symlink" "batman-build is an absolute symlink to a host file" $d
want PASS                         "misc-l38 (lower-case misc witness)"    $(mk ru $T/h-rel $V.dirty.wbox-misc-l38 misc-l38 WBOX-misc-l38-6a1c9e30) misc-l38
d=$(mk rv $T/h-rel $V); mkdir -p $d/usr/sbin; cp $T/h-pt $d/usr/sbin/other-helper
want FAIL:"rootfs carries a test seam" "normal build, a prov_test binary under another path (F3)" $d
want FAIL:"unknown option --bogus" "unknown --option"                  $(mk rw $T/h-rel $V) --bogus
# F5: GO / WBOX_DIR in the environment change nothing — a sentinel GO is never run, a decoy helpers.list never read
mkdir -p $T/decoy; printf 'test release same\n' > $T/decoy/helpers.list
printf '#!/bin/sh\ntouch %s/go-sentinel\nexit 0\n' "$T" > $T/sentinel-go; chmod 755 $T/sentinel-go
d=$(mk rx $T/h-pt $V.dirty.wbox-test test)
a=$(env -u GO -u WBOX_DIR bash $G $d test --selftest-wbox-dir $T/wbox --selftest-go $GO 2>&1; echo "rc=$?")
b=$(env GO=$T/sentinel-go WBOX_DIR=$T/decoy bash $G $d test --selftest-wbox-dir $T/wbox --selftest-go $GO 2>&1; echo "rc=$?")
c2=$(env GO=$T/sentinel-go WBOX_DIR=$T/decoy bash $G $(mk ry $T/h-rel $V) 2>&1; echo "rc=$?")
if [ "$a" = "$b" ] && [ ! -e $T/go-sentinel ] && ! echo "$c2" | grep -q 'helpers.list'; then pass=$((pass+1)); echo "ok   F5: GO / WBOX_DIR in the environment are ignored (output identical, sentinel never run)"; else bad=$((bad+1)); echo "BAD  F5: env changed the gate — a=[$a] b=[$b] c=[$c2] sentinel=$([ -e $T/go-sentinel ] && echo CREATED)"; fi
# --selftest-* is passed only by this self-test (the gate parses it): no other script may pass it
hits=$(grep -rln -- '--selftest-' $FW/scripts $FW/.github 2>/dev/null | grep -v -e 'scripts/check-prov-test-gate.sh$' -e 'scripts/test-prov-test-gate.sh$' || true)
if [ -z "$hits" ]; then pass=$((pass+1)); echo "ok   --selftest-* appears only in the gate and its self-test"; else bad=$((bad+1)); echo "BAD  --selftest-* used in: $hits"; fi
want FAIL:"not extracted"         "no rootfs"                            $T/missing
echo "RESULT gate self-test: $pass ok, $bad bad"; [ $bad = 0 ] && [ $pass -gt 0 ]
