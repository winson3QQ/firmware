#!/bin/bash
# test-prov-test-gate.sh — self-test of scripts/check-prov-test-gate.sh: every case must PASS, or FAIL for the
# listed reason (a FAIL for another reason is BAD: it would hide that the listed check is gone).
# Builds real arm64 helpers (-s -w -trimpath, like OpenWrt) from BATMAN_SRC: release, prov_test, and mutants:
#   h-mut   prov_test build whose seam stayed in a _test.go file (marker, no armed literal)
#   h-mark  release build that carries the marker string only
#   h-kp    release build that carries a "killpoint" string only
#   BATMAN_SRC=<batman-prov/src> [GO=<go>] scripts/test-prov-test-gate.sh
set -u
FW=$(cd "$(dirname "$0")/.." && pwd); G=$FW/scripts/check-prov-test-gate.sh
SRC=${BATMAN_SRC:?BATMAN_SRC = a batman-prov/src with the seam package}
GO=${GO:-$FW/staging_dir/hostpkg/lib/go-$(sed -n 's/^GO_DEFAULT_VERSION:=//p' $FW/feeds/openmanet/lang/golang/golang-values.mk | head -1)/bin/go}
[ -x "$GO" ] || { echo "no Go at $GO"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GOFLAGS=-mod=vendor GOTOOLCHAIN=local GOCACHE=$T/gocache GOARCH=arm64 CGO_ENABLED=0
b(){ (cd "$1" && "$GO" build -trimpath -buildvcs=false ${2:+-tags $2} -ldflags='-s -w' -o "$3" ./cmd/batman-provhelper) || { echo "build failed"; exit 1; }; }
b "$SRC" "" $T/h-rel; b "$SRC" prov_test $T/h-pt
cp -r "$SRC" $T/msrc; mv $T/msrc/seam/seam_provtest.go $T/msrc/seam/zz_impl_test.go; rm -f $T/msrc/seam/hook_provtest.go
sed -i 's#^//go:build !prov_test#//go:build never#' $T/msrc/seam/seam_release.go
printf '//go:build prov_test\n\npackage seam\n\nconst Marker = "BATMAN_PROV_TEST_BUILD_7f3a"\nconst Enabled = true\n\nfunc Arm(func(string, ...any))         {}\nfunc At(string, func(string, ...any)) {}\n' > $T/msrc/seam/stub.go
rm -f $T/msrc/node/seam_points_test.go
b $T/msrc prov_test $T/h-mut
cp -r "$SRC" $T/ksrc; sed -i 's#^const Marker = ""#const Marker = "BATMAN_PROV_TEST_BUILD_7f3a"#' $T/ksrc/seam/seam_release.go
grep -q 'BATMAN_PROV_TEST_BUILD_7f3a' $T/ksrc/seam/seam_release.go || { echo "h-mark mutant not applied"; exit 1; }
b $T/ksrc "" $T/h-mark; [ "$(strings $T/h-mark | grep -c BATMAN_PROV_TEST_BUILD_7f3a)" -ge 1 ] || { echo "h-mark mutant carries no marker"; exit 1; }
cp -r "$SRC" $T/psrc; printf '\nvar kpProbe int\n\nfunc init() {\n\tif kpProbe > 0 {\n\t\tprintln("killpoint probe")\n\t}\n}\n' >> $T/psrc/seam/seam_release.go
b $T/psrc "" $T/h-kp; [ "$(strings $T/h-kp | grep -c killpoint)" -ge 1 ] || { echo "h-kp mutant carries no killpoint string"; exit 1; }
mkdir -p $T/wbox
printf 'test prov_test helper\nhelper-notrial prov_test helper\n96-noprov release same\nchan release same\ntypo prov-test helper\n' > $T/wbox/helpers.list
printf '# wbox 96-noprov: 96 does not copy prov\n# wbox-witness: WBOX-96-noprov-0a1b2c3d\n+++ b/feed/batman-provision/files/etc/uci-defaults/96\n' > $T/wbox/96-noprov.patch
printf '# wbox chan: channel mutant\n# wbox-witness: WBOX-chan-11223344\n+++ b/feed/batman-provision/files/etc/init.d/wbox-chan\n' > $T/wbox/chan.patch
printf '# wbox helper-notrial\n# wbox-witness: WBOX-helper-notrial-55667788\n+++ b/feed/batman-prov/src/node/node.go\n' > $T/wbox/helper-notrial.patch
printf '# wbox typo\n# wbox-witness: WBOX-typo-99aabbcc\n' > $T/wbox/typo.patch
# mk <dir> <helper> <version> [wbox] [witness...] — witnesses ending in .rcd make etc/rc.d/<name> instead
mk(){ local d=$T/$1 h=$2 v=$3 wb=${4:-} i=0; shift 3; [ $# -gt 0 ] && shift
  mkdir -p $d/etc/rc.d $d/usr/bin; cp $h $d/usr/bin/batman-provhelper
  { echo "BATMAN_VERSION=$v"; [ -n "$wb" ] && echo "BATMAN_WBOX=$wb"; } > $d/etc/batman-build
  for x in "$@"; do case "$x" in *.rcd) touch $d/etc/rc.d/${x%.rcd} ;; *) i=$((i+1)); echo "$x" > $d/etc/wbox-witness-$i ;; esac; done
  echo $d; }
pass=0; bad=0
# want PASS <case> <args...> | want FAIL:<reason substring> <case> <args...>
want(){ local exp=$1 name=$2; shift 2; out=$(WBOX_DIR=$T/wbox GO=$GO bash $G "$@" 2>&1); rc=$?
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
want FAIL:"not extracted"         "no rootfs"                            $T/missing
echo "RESULT gate self-test: $pass ok, $bad bad"; [ $bad = 0 ] && [ $pass -gt 0 ]
