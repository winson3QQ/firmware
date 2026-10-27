#!/bin/bash
# test-prov-test-gate.sh — self-test of scripts/check-prov-test-gate.sh: every case must PASS or FAIL as listed.
# Builds real arm64 helpers (-s -w -trimpath, like OpenWrt) from BATMAN_SRC: release, prov_test, and the
# "seam not compiled in" mutant (implementation moved to a _test.go file).
set -u
FW=/home/yello/firmware-2710; G=$FW/scripts/check-prov-test-gate.sh
SRC=${BATMAN_SRC:?BATMAN_SRC = a batman-prov/src with the seam package}
GO=$FW/staging_dir/hostpkg/lib/go-$(sed -n 's/^GO_DEFAULT_VERSION:=//p' $FW/feeds/openmanet/lang/golang/golang-values.mk | head -1)/bin/go
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GOFLAGS=-mod=vendor GOTOOLCHAIN=local GOCACHE=$T/gocache GOARCH=arm64 CGO_ENABLED=0
b(){ (cd "$1" && $GO build -trimpath -buildvcs=false ${2:+-tags $2} -ldflags='-s -w' -o "$3" ./cmd/batman-provhelper) || { echo "build failed"; exit 1; }; }
b "$SRC" "" $T/h-rel; b "$SRC" prov_test $T/h-pt
cp -r "$SRC" $T/msrc; mv $T/msrc/seam/seam_provtest.go $T/msrc/seam/zz_impl_test.go
sed -i 's#^//go:build !prov_test#//go:build never#' $T/msrc/seam/seam_release.go
printf '//go:build prov_test\n\npackage seam\n\nconst Marker = "BATMAN_PROV_TEST_BUILD_7f3a"\nconst Enabled = true\n\nfunc Arm(func(string, ...any))         {}\nfunc At(string, func(string, ...any)) {}\n' > $T/msrc/seam/stub.go
b $T/msrc prov_test $T/h-mut
mkdir -p $T/wbox
printf 'test prov_test helper\nhelper-notrial prov_test helper\n96-noprov release same\nchan release same\n' > $T/wbox/helpers.list
printf '# wbox 96-noprov: 96 does not copy prov\n# wbox-witness: WBOX-96-noprov-0a1b2c3d\n+++ b/feed/batman-provision/files/etc/uci-defaults/96\n' > $T/wbox/96-noprov.patch
printf '# wbox chan: channel mutant\n# wbox-witness: WBOX-chan-11223344\n+++ b/feed/batman-provision/files/etc/init.d/wbox-chan\n' > $T/wbox/chan.patch
printf '# wbox helper-notrial\n# wbox-witness: WBOX-helper-notrial-55667788\n+++ b/feed/batman-prov/src/node/node.go\n' > $T/wbox/helper-notrial.patch
# mk <dir> <helper> <version> [wbox] [extra-file-with-witness] [rc.d-link]
mk(){ local d=$T/$1; mkdir -p $d/etc/rc.d $d/usr/bin; cp $2 $d/usr/bin/batman-provhelper
  { echo "BATMAN_VERSION=$3"; [ -n "${4:-}" ] && echo "BATMAN_WBOX=$4"; } > $d/etc/batman-build
  [ -n "${5:-}" ] && echo "$5" > $d/etc/wbox-witness-file; [ -n "${6:-}" ] && touch $d/etc/rc.d/$6; echo $d; }
pass=0; bad=0
want(){ local exp=$1 name=$2; shift 2; out=$(WBOX_DIR=$T/wbox GO=$GO bash $G "$@" 2>&1); rc=$?
  if { [ $exp = PASS ] && [ $rc = 0 ]; } || { [ $exp = FAIL ] && [ $rc != 0 ]; }; then pass=$((pass+1)); echo "ok   $exp $name — $out"
  else bad=$((bad+1)); echo "BAD  want $exp: $name — rc=$rc $out"; fi; }
V=1.5.14-wsl.5+abc1234.fwdef5678
want PASS "release build"                  $(mk r1 $T/h-rel $V)
want FAIL "normal build with prov_test helper" $(mk r2 $T/h-pt $V)
want FAIL "normal build with BATMAN_WBOX line" $(mk r3 $T/h-rel $V x)
want FAIL "normal build with a witness string" $(mk r4 $T/h-rel $V "" WBOX-x-00000000)
printf '#!/bin/sh
exit 1
' > $T/h-sh; chmod 755 $T/h-sh
want FAIL "normal build, helper is a shell script" $(mk r5 $T/h-sh $V)
want PASS "wbox test"                      $(mk w1 $T/h-pt $V.dirty.wbox-test test) test
want FAIL "wbox test, seam not compiled in (mutant)" $(mk w2 $T/h-mut $V.dirty.wbox-test test) test
want FAIL "wbox test, release helper"      $(mk w3 $T/h-rel $V.dirty.wbox-test test) test
want FAIL "wbox test, version not .dirty.wbox-test" $(mk w4 $T/h-pt $V.dirty test) test
want PASS "wbox helper-notrial"            $(mk w5 $T/h-pt $V.dirty.wbox-helper-notrial helper-notrial WBOX-helper-notrial-55667788) helper-notrial
want FAIL "wbox helper-notrial, witness lost" $(mk w6 $T/h-pt $V.dirty.wbox-helper-notrial helper-notrial) helper-notrial
want PASS "wbox 96-noprov (release helper)" $(mk w7 $T/h-rel $V.dirty.wbox-96-noprov 96-noprov WBOX-96-noprov-0a1b2c3d) 96-noprov
want PASS "wbox chan, enabled"             $(mk w8 $T/h-rel $V.dirty.wbox-chan chan WBOX-chan-11223344 S99wbox-chan) chan
want FAIL "wbox chan, not enabled"         $(mk w9 $T/h-rel $V.dirty.wbox-chan chan WBOX-chan-11223344) chan
want FAIL "wbox name not in helpers.list"  $(mk wa $T/h-pt $V.dirty.wbox-nope nope) nope
want FAIL "no rootfs"                      $T/missing
echo "RESULT gate self-test: $pass ok, $bad bad"; [ $bad = 0 ]
