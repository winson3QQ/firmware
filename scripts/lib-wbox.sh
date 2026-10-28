# lib-wbox.sh — sourced by scripts/build-board.sh (bash): the #254 -wbox steps, one function each, so that
# scripts/test-build-board-wbox.sh can drive the very code the build runs (Batman 254-h23 §4.2, §15.5, §16.7).
# Every function exits the calling shell on a refusal (build-board.sh runs them in its own shell).

# bb_lock FILE — one build-board.sh per tree at a time (two would apply / restore feeds/batman under each other and
# share build_dir). fd 9 stays open, so the lock lives until the script exits.
bb_lock(){
	# root (--card-only, or a build by mistake) never CREATES the lock: a root-owned lock file would stop every later
	# build of the tree owner at "cannot open the build lock" (r4 A-m4 / B-m5)
	if [ ! -e "$1" ] && [ "$(id -u)" = 0 ]; then
		echo "no build lock $1 yet — build this tree as its owner first (root does not create it)" >&2; exit 2
	fi
	exec 9>>"$1" || { echo "cannot open the build lock $1" >&2; exit 2; }
	flock -n 9 || { echo "another build-board.sh holds $1 — one build per tree at a time" >&2; exit 2; }
}

# wbox_env_reset — BATMAN_WBOX / BATMAN_PROV_TEST come from --wbox only, never from the calling shell; GO_PKG_TAGS /
# GOFLAGS from the shell would reach the Go package build too (make takes them from the environment, r3 B-m1).
wbox_env_reset(){ unset BATMAN_WBOX BATMAN_PROV_TEST GO_PKG_TAGS GOFLAGS; }

# wbox_normal_check FEED — a normal build refuses a feed that still carries a wbox mutant (a -wbox build killed with
# SIGKILL never ran its trap; openmanet_setup.sh -i does not reset feeds/batman): any modified, untracked, ignored or
# STAGED file holding a wbox witness (security review F4: `git add` takes a file off -m / -o; NUL-separated names, so a
# non-ASCII or newline name is read as itself, not as a quoted string that names no file). Other uncommitted work is
# allowed (it makes a .dirty build, as before).
wbox_normal_check(){
	local feed=$1 f hits="" lst rc
	lst=$(mktemp) || { echo "cannot make a temp file — refusing the build" >&2; exit 1; }
	# git failing (not a repo, unreadable index) is a refusal, not "nothing found" (r4 B-m3)
	{ git -C "$feed" ls-files -z -m -o && git -C "$feed" diff --cached --name-only --no-renames -z; } > "$lst" \
		|| { rm -f "$lst"; echo "cannot list the changed files of $feed (git failed) — refusing the build" >&2; exit 1; }
	while IFS= read -r -d '' f; do
		[ -f "$feed/$f" ] || continue
		grep -qE 'WBOX-[a-z0-9-]+-[0-9a-f]{8}' "$feed/$f"; rc=$?
		[ $rc -le 1 ] || { rm -f "$lst"; echo "cannot read $feed/$(printf %q "$f") (grep rc $rc) — refusing the build" >&2; exit 1; }
		[ $rc = 0 ] && hits="$hits $(printf %q "$f")"
	done < "$lst"
	rm -f "$lst"
	[ -z "$hits" ] && return 0
	echo "$feed still carries a wbox mutant (files with a wbox witness:$hits) — a -wbox build was killed before" >&2
	echo "  restoring it; restore it first: git -C $feed reset -q && git -C $feed checkout -- . && git -C $feed clean -fdx" >&2
	echo "  (after checking what goes)" >&2
	exit 1
}

# wbox_apply NAME FEED — validate NAME against FEED/tests/wbox/helpers.list, refuse a FEED that is not clean, apply
# NAME's patch (none for `test`), arm the EXIT trap that restores FEED, export BATMAN_WBOX (+ BATMAN_PROV_TEST=1).
# Order matters: the clean check comes before the trap (a trap set first would wipe the developer's work on refusal).
wbox_apply(){
	local name=$1 feed=$2 wl wd wp line tag kind
	case "$name" in ''|*[!a-z0-9-]*) echo "bad --wbox name '$name'" >&2; exit 1 ;; esac
	wl=$feed/tests/wbox/helpers.list
	[ -f "$wl" ] || { echo "no $wl in the pinned Batman feed — cannot build -wbox variants" >&2; exit 1; }
	line=$(awk -v n="$name" '$1 == n { print $2, $3; exit }' "$wl")
	tag=${line% *}; kind=${line#* }
	[ -n "$line" ] || { echo "$name is not in $wl" >&2; exit 1; }
	case "$tag" in prov_test|release) ;; *) echo "$wl: tag '$tag' for $name (want prov_test or release)" >&2; exit 1 ;; esac
	case "$kind" in helper|same) ;; *) echo "$wl: helper column '$kind' for $name (want helper or same)" >&2; exit 1 ;; esac
	# the patch goes onto a CLEAN feed and the trap restores it: a leftover mutant (a build killed with SIGKILL skips
	# the trap) or uncommitted work in the feed would be stacked under / wiped by this variant (r1 B-M1)
	wd=$(git -C "$feed" status --porcelain --ignored) || { echo "cannot read git status of $feed" >&2; exit 1; }
	if [ -n "$wd" ]; then
		echo "$feed is not clean — refusing to apply a wbox patch onto it (commit / stash your work, or" >&2
		echo "  git -C $feed checkout -- . && git -C $feed clean -fdx  after checking what goes):" >&2
		printf '%s\n' "$wd" | head -20 >&2; exit 1
	fi
	trap "git -C '$feed' checkout -q -- . && git -C '$feed' clean -qfdx" EXIT
	if [ "$name" != test ]; then
		wp=tests/wbox/$name.patch
		[ -f "$feed/$wp" ] || { echo "no $feed/$wp" >&2; exit 1; }
		# a mutant may only touch the two packages the stamp step cleans (wbclean) — never tests/wbox (read before the
		# patch by this function, after it by the gate) or anything else the build would reuse unchanged (r3 A-m5)
		# no rename / copy: --numstat lists only a rename's DESTINATION, so a source outside the scope would pass (r4 A-m1)
		grep -qE '^(rename|copy) (from|to) ' "$feed/$wp" && { echo "wbox patch $wp renames / copies a file (not allowed)" >&2; exit 1; }
		local p bad=""
		while read -r _ _ p; do
			case "$p" in feed/batman-prov/*|feed/batman-provision/*) ;; *) bad="$bad $p" ;; esac
		done < <(git -C "$feed" apply --numstat "$wp") || true
		[ -z "$bad" ] || { echo "wbox patch $wp touches files outside feed/batman-prov{,ision}/:$bad" >&2; exit 1; }
		[ -n "$(git -C "$feed" apply --numstat "$wp" 2>/dev/null)" ] || { echo "wbox patch $wp changes nothing (or does not parse)" >&2; exit 1; }
		{ git -C "$feed" apply --check "$wp" && git -C "$feed" apply "$wp"; } || { echo "wbox patch $wp does not apply" >&2; exit 1; }
	fi
	export BATMAN_WBOX=$name
	[ "$tag" = prov_test ] && export BATMAN_PROV_TEST=1
	echo "wbox variant $name (tag $tag): applied; $feed is restored on exit"
}

# wbox_stamp_begin STAMP NOW CLEAN-CMD... — when the variant differs from the last finished build's, run CLEAN-CMD
# (cleans the Go packages: OpenWrt's rebuild hash does not see env, and sees patched files only by mtime) and mark
# the stamp "in-progress:NOW", so an interrupted build of NOW cleans again next time.
wbox_stamp_begin(){
	local st=$1 now=$2 was; shift 2
	was=$(cat "$st" 2>/dev/null || echo unknown)
	[ "$was" = "$now" ] && return 0
	echo "wbox variant changed ($was -> $now): cleaning batman-prov, batman-provision"
	"$@" || exit 1
	echo "in-progress:$now" > "$st"
}

# wbox_stamp_done STAMP NOW — the build of NOW finished: record it.
wbox_stamp_done(){ echo "$2" > "$1"; }
