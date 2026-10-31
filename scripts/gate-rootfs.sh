#!/bin/bash
# gate-rootfs.sh — #254 test-seam gate on a root.squashfs, for every path that ships one (security review F2;
# review A-M3: one implementation, so one regression test covers local-ab-tar.sh, fast-build.yml and build-board.sh).
#   gate-rootfs.sh <root.squashfs> [--normal]
#       extract the squashfs, refuse an incomplete extraction, run scripts/check-prov-test-gate.sh on it. The variant
#       name comes from the image's own stamp (no BATMAN_WBOX = a normal build: every seam rule applies; a -wbox image
#       is held to its variant's rules). --normal: CI builds only normal images — a BATMAN_WBOX stamp is then a FAIL.
#   gate-rootfs.sh --extract <root.squashfs> <dir>
#       only the extraction + completeness check (build-board.sh step 7 runs its other checks on the same tree)
# unsquashfs: the host's `unsquashfs` if on PATH, else the tree's staging_dir/host/bin/unsquashfs4. As a non-root user
# unsquashfs cannot make device nodes and says so (rc != 0): the rc is not trusted either way — the count of regular
# files extracted must equal the count the squashfs lists. An extraction that missed one is a FAIL, never a pass.
set -u
fail(){ echo "gate-rootfs: FAIL: $*" >&2; exit 1; }
TOP=$(cd "$(dirname "$0")/.." && pwd)
US=$TOP/staging_dir/host/bin/unsquashfs4; command -v unsquashfs >/dev/null && US=unsquashfs
extract(){	# <squashfs> <dir>
	[ -f "$1" ] || fail "no squashfs $1"
	[ ! -e "$2" ] || fail "$2 already exists"
	"$US" -q -no-xattrs -f -d "$2" "$1" >/dev/null 2>&1 || true
	local nl nf
	nl=$("$US" -lls "$1" 2>/dev/null | grep -c '^-') || true
	nf=$(find "$2" -type f 2>/dev/null | wc -l)
	[ "$nl" -gt 0 ] 2>/dev/null || fail "cannot list $1 (no regular files listed)"
	[ "$nf" = "$nl" ] || fail "rootfs extraction incomplete ($nf of $nl regular files)"
}
case "${1:-}" in
	--extract) [ $# = 3 ] || fail "usage: gate-rootfs.sh --extract <root.squashfs> <dir>"; extract "$2" "$3"; exit 0 ;;
	''|-*) fail "usage: gate-rootfs.sh <root.squashfs> [--normal] | --extract <root.squashfs> <dir>" ;;
esac
SQ=$1; NORMAL=0
case "${2:-}" in '') ;; --normal) NORMAL=1 ;; *) fail "unknown argument $2" ;; esac
[ $# -le 2 ] || fail "too many arguments"
W=$(mktemp -d) || fail "mktemp"; trap 'rm -rf "$W"' EXIT
extract "$SQ" "$W/r"
WB=""; [ $NORMAL = 1 ] || WB=$(sed -n 's/^BATMAN_WBOX=//p' "$W/r/etc/batman-build" 2>/dev/null | head -1)
bash "$TOP/scripts/check-prov-test-gate.sh" "$W/r" ${WB:+"$WB"}
