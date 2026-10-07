#!/bin/sh
# patch-witness.sh — per-patch witness (Batman #275): proof IN THE BUILT IMAGE that every board patch took effect.
# The gate (check-board-patches.sh) proves a patch is applied in feeds/; only a witness proves the image carries it
# (1.5.5-wsl.2 was caught by a node probe, rc3 accepted by hand-checking the ipk — this automates both).
#
#   patch-witness.sh list  <board>                        TSV "<patch>\t<kind>\t<arg>\t<rest>" on stdout;
#                                                         stamp-batman-build.sh bakes it into /etc/batman-patch-witness
#   patch-witness.sh check <board> <rootdir> <manifest>   verify every witness against an extracted rootfs + the
#                                                         image manifest (build-board.sh step 7, CI)
#
# Rule: every patches/<board>/*.patch of a Batman board (boards/<board>/batman-recipe exists) carries exactly ONE
# header line before its first diff:
#   Batman-Witness: file <rootfs-path-glob> <fixed string>   a file of the image contains the string
#   Batman-Witness: pkg <package> <version-prefix>           the image manifest has "<package> - <version-prefix>..."
#   Batman-Witness: none <reason>                            nothing observable (say why, e.g. package not in image)
# The node side (Batman daily-validation board-patches-275) re-checks file/pkg on /rom of the running image.
set -eu
CMD=${1:-}; B=${2:-}
[ -n "$CMD" ] && [ -n "$B" ] || { echo "usage: patch-witness.sh list <board> | check <board> <rootdir> <manifest>" >&2; exit 2; }
cd "$(dirname "$0")/.." || exit 2
TAB=$(printf '\t')

list() {
	[ -d "patches/$B" ] || return 0
	bad=0
	for p in patches/"$B"/*.patch; do
		[ -e "$p" ] || continue
		w=$(awk '/^(---|diff |\+\+\+ |@@ )/ { exit } /^Batman-Witness: / { sub(/^Batman-Witness: /, ""); print }' "$p")
		n=$(printf '%s' "$w" | grep -c . || true)
		if [ "$n" != 1 ]; then echo "patch-witness: $p has $n Batman-Witness lines (need exactly 1)" >&2; bad=1; continue; fi
		k=${w%% *}; r=${w#* }; a=${r%% *}; rest=${r#* }
		case "$k" in
			file|pkg) [ -n "$a" ] && [ "$rest" != "$r" ] && [ -n "$rest" ] || { echo "patch-witness: $p: '$k' needs <arg> <value>" >&2; bad=1; continue; }
				printf '%s\t%s\t%s\t%s\n' "${p##*/}" "$k" "$a" "$rest" ;;
			none) [ "$r" != "$w" ] && [ -n "$r" ] || { echo "patch-witness: $p: 'none' needs a reason" >&2; bad=1; continue; }
				printf '%s\tnone\t-\t%s\n' "${p##*/}" "$r" ;;
			*) echo "patch-witness: $p: unknown kind '$k'" >&2; bad=1 ;;
		esac
	done
	return $bad
}

case "$CMD" in
	list) list ;;
	check)
		ROOT=${3:?check needs <rootdir>}; MAN=${4:?check needs <manifest>}
		[ -d "$ROOT/etc" ] && [ -f "$MAN" ] || { echo "patch-witness: no rootfs at $ROOT or manifest $MAN" >&2; exit 2; }
		L=$(list) || exit 1
		fail=0; n=0
		while IFS="$TAB" read -r p k a v; do
			[ -n "$p" ] || continue; n=$((n+1))
			case "$k" in
				file) ok=0
					for f in "$ROOT"/$a; do [ -f "$f" ] && grep -aqF -- "$v" "$f" && ok=1; done
					[ "$ok" = 1 ] && echo "  ok    $p: $a has '$v'" || { echo "  FAIL  $p: no $a in the image contains '$v'"; fail=1; } ;;
				pkg) if grep -q "^$a - $v" "$MAN"; then echo "  ok    $p: $(grep "^$a - " "$MAN")"
					else echo "  FAIL  $p: manifest has '$(grep "^$a - " "$MAN" || echo "no $a")', want '$a - $v*'"; fail=1; fi ;;
				none) echo "  none  $p: $v" ;;
			esac
		done <<W
$L
W
		[ "$fail" = 0 ] && echo "patch-witness: all $n patch(es) of $B witnessed in the image" || echo "patch-witness: FAIL — the image lacks a board patch (#275)"
		exit $fail ;;
	*) echo "usage: patch-witness.sh list <board> | check <board> <rootdir> <manifest>" >&2; exit 2 ;;
esac
