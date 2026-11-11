#!/bin/bash
# test-stamp-release-key.sh — stamp-batman-build.sh's root-key placement (Batman #254 P3 §3.7.2) in a minimal fake
# firmware tree: the real stamp script, the checks it calls stubbed. rel = R from keys/ (none = FAIL), --bench T only
# as an argument (never the environment), rel + bench refused, the key files removed first (bench then plain = no
# key), ".bench" before ".dirty" / ".wbox-", an unknown channel refused. Nothing checked = FAIL.
exec </dev/null
FW=$(cd "$(dirname "$0")/.." && pwd)
STAMP=${STAMP:-$FW/scripts/stamp-batman-build.sh}
TPUB=${TPUB:-$FW/feeds/batman/tests/keys/T.pub}
[ -f "$TPUB" ] || { echo "FAIL: no T.pub at $TPUB (the batman feed installed?)"; exit 1; }
T=$(mktemp -d /tmp/stt.XXXXXX)
trap 'rm -rf "$T"' EXIT
fail=0
ck() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2] want [$3]"; fail=1; fi; }
mk() { # channel
	rm -rf $T/fw; mkdir -p $T/fw/scripts $T/fw/feeds/batman/tests/keys
	cd $T/fw/feeds/batman && git init -q && cp $TPUB tests/keys/T.pub && git add -A && git -c user.email=x@x -c user.name=x commit -qm feed
	PIN=$(git rev-parse HEAD)
	cd $T/fw
	cp "$STAMP" scripts/stamp-batman-build.sh
	for s in check-feed-pins.sh check-board-patches.sh board-patch-digest.sh; do printf '#!/bin/sh\nexit 0\n' > scripts/$s; done
	printf '#!/bin/sh\n[ "$1" = list ] && exit 0\n' > scripts/patch-witness.sh
	printf '#!/bin/sh\necho r1\n' > scripts/getver.sh; chmod +x scripts/*.sh
	printf 'BATMAN_RELEASE=1.5.14\nBATMAN_CHANNEL=%s\nBATMAN_BUILD_N=26\n' "$1" > batman-release.env
	echo 'CONFIG_VERSION_CODE="1.8.0"' > .config
	echo "src-git batman https://example/Batman.git^$PIN" > feeds.conf.default
	printf 'files/etc/batman-build\nfiles/etc/batman-patch-witness\nfiles/usr/share/batman/release-root.pub\nfiles/usr/share/batman/release-min-serial\nfeeds/\n' > .gitignore
	git init -q && git add -A && git -c user.email=x@x -c user.name=x commit -qm fw
}
run() { (cd $T/fw && sh scripts/stamp-batman-build.sh ekh-bcm2711 "$@" > $T/out 2>&1); echo $?; }
key() { [ -f $T/fw/files/usr/share/batman/release-root.pub ] && cat $T/fw/files/usr/share/batman/release-root.pub || echo none; }
ser() { cat $T/fw/files/usr/share/batman/release-min-serial 2>/dev/null || echo none; }
st() { sed -n "s/^$1=//p" $T/fw/files/etc/batman-build; }

mk wsl
ck wsl-rc "$(run)" 0
ck wsl-no-key "$(key)" none
ck wsl-no-bench "$(st BATMAN_BENCH_TRUST)" ""
ck wsl-clean "$(st BATMAN_DIRTY)" 0
ck bench-rc "$(run --bench T)" 0
ck bench-key "$(key)" "$(cat $TPUB)"
ck bench-serial "$(ser)" 1
ck bench-flag "$(st BATMAN_BENCH_TRUST)" T
case "$(st BATMAN_VERSION)" in *.bench) ck bench-version ok ok ;; *) ck bench-version "$(st BATMAN_VERSION)" "*.bench" ;; esac
ck bench-still-clean "$(st BATMAN_DIRTY)" 0
ck bench-then-plain-rc "$(run)" 0
ck bench-then-plain-no-key "$(key)" none
ck bench-then-plain-no-flag "$(st BATMAN_BENCH_TRUST)" ""
ck bench-other-value "$(run --bench R)" 1
ck bench-no-value "$(run --bench)" 1
ck env-does-not-bench "$(BATMAN_BENCH_TRUST=T BENCH=T run)" 0
ck env-no-key "$(key)" none
# .dirty / .wbox- after .bench
echo x > $T/fw/scripts/extra.txt; (cd $T/fw && git add scripts/extra.txt)
run --bench T >/dev/null
case "$(st BATMAN_VERSION)" in *.bench.dirty) ck bench-before-dirty ok ok ;; *) ck bench-before-dirty "$(st BATMAN_VERSION)" "*.bench.dirty" ;; esac
(cd $T/fw && BATMAN_WBOX=x1 sh scripts/stamp-batman-build.sh ekh-bcm2711 --bench T >/dev/null 2>&1)
case "$(st BATMAN_VERSION)" in *.bench.dirty.wbox-x1) ck bench-dirty-wbox-order ok ok ;; *) ck bench-dirty-wbox-order "$(st BATMAN_VERSION)" "*.bench.dirty.wbox-x1" ;; esac
mk ci
ck ci-rc "$(run)" 0
ck ci-no-key "$(key)" none
mk rel
ck rel-without-R "$(run)" 1
grep -q "release root R" $T/out && ck rel-without-R-why ok ok || ck rel-without-R-why "$(cat $T/out)" "names R"
ck rel-bench "$(run --bench T)" 1
mkdir -p $T/fw/keys && echo 04abcd > $T/fw/keys/release-root.pub && echo 3 > $T/fw/keys/release-min-serial
ck rel-rc "$(run)" 0
ck rel-key "$(key)" 04abcd
ck rel-serial "$(ser)" 3
ln -sf /etc/passwd $T/fw/keys/link.pub; rm $T/fw/keys/release-root.pub; ln -s link.pub $T/fw/keys/release-root.pub
ck rel-symlink-key "$(run)" 1
mk beta
ck unknown-channel "$(run)" 1
[ $fail = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "SOME FAIL"; exit 1; }
