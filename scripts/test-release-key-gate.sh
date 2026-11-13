#!/bin/bash
# test-release-key-gate.sh — scripts/check-release-key-gate.sh on fake extracted rootfs trees (#254 P3 §3.7.2 negative
# tests), plus the structural checks: every image / payload path runs it. Any case that is not what it should be is
# a FAIL; nothing checked = FAIL.
set -u
FW=$(cd "$(dirname "$0")/.." && pwd)
G=${GATE:-$FW/scripts/check-release-key-gate.sh}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; bad=0
# a fake feed: T, and a pinned "R" (any valid point: the K_test key of the feed, when present, else a fixed one)
mkdir -p $T/feed/tests/keys $T/feed/scripts
TP=0459a95dafd5670774442a12a22f495540ff4b2b0d9e537562dde39d354ce5507488761ce5cac4e4e2b71219610e6475f56e152a8a242a5ad2fada64010f60f630
RP=04$(printf 'ab%.0s' $(seq 64))
echo $TP > $T/feed/tests/keys/T.pub
fpr(){ printf %s "$1" | xxd -r -p | sha256sum | cut -d' ' -f1; }
root(){ # <name> <channel|-> <bench|-> [pub] [serial]
	local d=$T/$1; rm -rf $d; mkdir -p $d/etc $d/usr/share/batman
	[ "$2" = - ] || { echo "BATMAN_VERSION=1.5.14-$2.26+a.fwb"; echo "BATMAN_CHANNEL=$2"; [ "$3" = - ] || echo "BATMAN_BENCH_TRUST=$3"; } > $d/etc/batman-build
	[ -z "${4:-}" ] || echo "$4" > $d/usr/share/batman/release-root.pub
	[ -z "${5:-}" ] || echo "$5" > $d/usr/share/batman/release-min-serial
	echo $d
}
case_(){ # <want ok|FAIL[:reason]> <name> <dir> [mode] — a FAIL must give the expected reason, not just any
	local out rc why=${1#FAIL:}; out=$(BATMAN_FEED=$T/feed bash "$G" "$3" ${4:-} 2>&1); rc=$?
	[ "$why" = "$1" ] && why=""
	if { [ "$1" = ok ] && [ $rc = 0 ]; } || { [ "${1%%:*}" = FAIL ] && [ $rc != 0 ] && { [ -z "$why" ] || grep -q "$why" <<< "$out"; }; }; then pass=$((pass+1)); echo "ok   $2 — $out"
	else bad=$((bad+1)); echo "BAD  want $1: $2 — rc=$rc $out"; fi
}
echo "$(fpr $RP)" > $T/feed/scripts/release-root.fpr
case_ ok   "wsl, no key"                       "$(root a wsl -)"
case_ ok   "ci, no key"                        "$(root a ci -)"
case_ ok   "no stamp (fast-build), no key"     "$(root a - -)"
case_ FAIL "wsl with a key"                    "$(root a wsl - $TP 1)"
case_ FAIL "wsl with only a serial file"       "$(root a wsl - '' 1)"
case_ FAIL "no stamp with a key"               "$(root a - - $TP 1)"
case_ ok   "bench T"                           "$(root a wsl T $TP 1)"
case_ FAIL "bench T in CI (--ci)"              "$(root a wsl T $TP 1)" --ci
case_ FAIL "bench with a key that is not T"    "$(root a wsl T $RP 1)"
case_ FAIL "bench without its key"             "$(root a wsl T)"
case_ "FAIL:want 1" "bench, serial 2"                   "$(root a wsl T $TP 2)"
case_ FAIL "BATMAN_BENCH_TRUST=X"              "$(root a wsl X $TP 1)"
case_ ok   "rel with the pinned R"             "$(root a rel - $RP 3)"
case_ ok   "rel with the pinned R (--ci)"      "$(root a rel - $RP 3)" --ci
case_ "FAIL:is not R" "rel with T"                        "$(root a rel - $TP 1)"
case_ FAIL "rel with BATMAN_BENCH_TRUST"       "$(root a rel T $RP 1)"
case_ FAIL "rel without a key"                 "$(root a rel -)"
case_ "FAIL:is not a serial" "rel, serial 0"                     "$(root a rel - $RP 0)"
case_ "FAIL:not a hex P-256 point" "rel, key not a point"              "$(root a rel - ${RP:0:100} 1)"
d=$(root a rel - $RP 3); printf '%s\n%s\n' $RP $RP > $d/usr/share/batman/release-root.pub
case_ "FAIL:not one short line" "rel, two-line key file"            "$d"
d=$(root a rel - $RP 3); printf '%s
%s
' ${RP:0:65} ${RP:65} > $d/usr/share/batman/release-root.pub
case_ "FAIL:not one short line" "rel, R split over two lines"      "$d"
d=$(root a rel - '' 3); ln -s /etc/passwd $d/usr/share/batman/release-root.pub
case_ "FAIL:not a regular file" "rel, key file a symlink"           "$d"
d=$(root a wsl -); ln -s /nonexistent $d/usr/share/batman/release-root.pub
case_ FAIL "wsl, a dangling key symlink"       "$d"
case_ FAIL "unknown channel"                   "$(root a beta -)"
mv $T/feed/scripts/release-root.fpr $T/fpr.saved
case_ "FAIL:no pinned R fingerprint" "rel before R (no pinned fingerprint)" "$(root a rel - $RP 3)"
mv $T/fpr.saved $T/feed/scripts/release-root.fpr
case_ FAIL "bad mode"                          "$(root a wsl -)" --bogus

# structural: every path that ships a rootfs runs the key gate
GR=$FW/scripts/gate-rootfs.sh BB=$FW/scripts/build-board.sh BF=$FW/.github/workflows/build-firmware.yml
st(){ if eval "$2"; then pass=$((pass+1)); echo "ok   structure: $1"; else bad=$((bad+1)); echo "BAD  structure: $1"; fi; }
st "gate-rootfs.sh runs check-release-key-gate.sh on its extraction" "grep -q 'check-release-key-gate.sh\" \"\$W/r\"' $GR"
st "build-board.sh step 7 runs it after the --extract" \
	"e=\$(grep -n 'gate-rootfs.sh --extract' $BB | head -1 | cut -d: -f1); k=\$(grep -n 'check-release-key-gate.sh \"\$WR/r\"' $BB | head -1 | cut -d: -f1); [ -n \"\$e\" ] && [ -n \"\$k\" ] && [ \"\$e\" -lt \"\$k\" ]"
st "build-firmware.yml: gate-rootfs.sh --ci before the upload" \
	"g=\$(grep -n 'bash scripts/gate-rootfs.sh \"\$SQ\" --ci' $BF | head -1 | cut -d: -f1); u=\$(grep -n '^      - name: Upload' $BF | head -1 | cut -d: -f1); [ -n \"\$g\" ] && [ -n \"\$u\" ] && [ \"\$g\" -lt \"\$u\" ]"
FB=$FW/.github/workflows/fast-build.yml
st "fast-build.yml: gate-rootfs.sh (runs the key gate) before its upload" \
	"g=\$(grep -n 'bash scripts/gate-rootfs.sh root.squashfs --normal' $FB | head -1 | cut -d: -f1); u=\$(grep -n '^      - name: Upload' $FB | head -1 | cut -d: -f1); [ -n \"\$g\" ] && [ -n \"\$u\" ] && [ \"\$g\" -lt \"\$u\" ]"
st "build-firmware.yml runs the stamp test" "grep -q 'bash scripts/test-stamp-release-key.sh' $BF"
st "build-board.sh passes --bench only as '--bench T' to the stamp" "grep -q 'stamp-batman-build.sh \"\$BOARD\" \${BENCH:+--bench T}' $BB"
echo "release-key-gate tests: $pass ok, $bad bad"
[ $bad = 0 ] && [ $pass -gt 0 ]
