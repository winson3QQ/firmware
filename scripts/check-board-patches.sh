#!/bin/sh
# check-board-patches.sh <board> — prove every patches/<board>/*.patch is APPLIED in feeds/ (Batman #275).
# Each patch must reverse-apply cleanly (dry run): new-file patch = file present with exactly that content
# (absent, or appended twice, fails), deletion = file gone, modification = changed lines present. -f: never
# ask (an interactive "Unreversed patch detected! Ignore -R?" answered y would let a MISSING patch pass);
# -F0: no fuzz, so changed context fails (a pure line offset still passes — the content is there).
# Rule: patches in one board dir must not edit overlapping lines (each is checked alone against the final
# tree); none do today. Run from the firmware tree root after openmanet_setup.sh -i -b <board>.
B=${1:?usage: check-board-patches.sh <board>}
cd "$(dirname "$0")/.." || exit 2
[ -d "patches/$B" ] || { echo "check-board-patches: no patches/$B — nothing to check"; exit 0; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bad=0; n=0
for p in patches/"$B"/*.patch; do
	[ -e "$p" ] || continue; n=$((n+1))
	if ! patch -p1 -R --dry-run -f -F0 -s -i "$p" >/dev/null 2>&1; then
		echo "MISSING  $p — not (exactly) applied in feeds/"; bad=1; continue
	fi
	# A reverse dry run accepts a NEW file that carries extra content after the patch's lines (e.g. the patch
	# applied twice = appended twice; measured 2026-10-07). So for every file the patch CREATES (@@ -0,0 +1,N),
	# rebuild the expected content from its '+' lines and require the file to be byte-identical.
	rm -f "$T"/exp.* "$T"/path.* "$T/nonl"
	awk -v d="$T" '
		/^\+\+\+ / { path = $2; sub(/^b\//, "", path); newf = 0; next }
		/^@@ -0,0 \+1(,[0-9]+)? @@/ { newf = 1; k++; out = d "/exp." k; printf "" > out; print path > (d "/path." k); next }
		/^@@ / { newf = 0; next }
		newf && /^\+/ { print substr($0, 2) > out; next }
		newf && /^\\ No newline/ { nonl[k] = 1 }
		END { for (i in nonl) print i > (d "/nonl") }' "$p"
	ok=1
	for e in "$T"/exp.*; do
		[ -e "$e" ] || continue; k=${e##*.}; f=$(cat "$T/path.$k")
		if grep -qx "$k" "$T/nonl" 2>/dev/null; then head -c -1 "$e" > "$e.t" && mv "$e.t" "$e"; fi
		cmp -s "$e" "$f" || { echo "MISSING  $p — $f is not exactly the file the patch creates"; ok=0; }
	done
	[ "$ok" = 1 ] && echo "applied  $p" || bad=1
done
[ "$bad" = 0 ] && echo "check-board-patches: all $n patch(es) of $B are applied" || echo "check-board-patches: FAIL — re-run openmanet_setup.sh -i -b $B"
exit $bad
