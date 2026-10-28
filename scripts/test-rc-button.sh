#!/bin/bash
# scripts/test-rc-button.sh [<rootfs dir>] — #254 prov-unit-button (Batman docs/design/254-p1-impl.md §5.1, F11;
# 254-stage1-impl F22 / U8): the reset button never wipes the overlay (that only re-applies p5 and is not a factory
# reset; transfer = reflash). Runs the shipped etc/rc.button/{reset,reset_override} (default: this tree's files/ overlay;
# CI: the built rootfs) with jffs2reset / reboot / logger / ubus / diag.sh stubbed, per ACTION / SEEN:
#   reset           released 1 s -> reboot; released 6 s with an overlay -> reboot + a log line, NEVER jffs2reset
#   reset_override  released 1 s -> `ubus call dpp push_button`, no reboot; 3 s -> nothing; 6 s -> log + reboot, no jffs2reset
#   both            pressed -> return 5 (the hold timer)
# Negative control (always run): upstream package/base-files/files/etc/rc.button/reset on the 6 s press calls jffs2reset
# and must FAIL the same judge. Zero cases = FAIL.
set -u
TREE=$(cd "$(dirname "$0")/.." && pwd); ROOT=${1:-$TREE/files}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; n=0; f=0
mkdir -p "$T/bin"
for b in jffs2reset reboot logger ubus; do printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\n' "$b" "$T" > "$T/bin/$b"; chmod 755 "$T/bin/$b"; done
printf 'set_state() { echo "set_state $*" >> "%s/calls"; }\n' "$T" > "$T/diag.sh"
: > "$T/functions.sh"; echo "overlayfs:/overlay / overlay rw 0 0" > "$T/mounts"; echo "/dev/loop0 /overlay f2fs rw 0 0" >> "$T/mounts"
# press <script> <ACTION> <SEEN> -> calls in $T/calls, the script's rc in RC. The node paths it reads are pointed at stubs:
# /etc/diag.sh, /lib/functions.sh, /proc/mounts (an overlay is mounted, as on a node), /dev/console
press(){
	sed -e "s#/etc/diag.sh#$T/diag.sh#g" -e "s#/lib/functions.sh#$T/functions.sh#g" -e "s#/proc/mounts#$T/mounts#g" \
		-e "s#/dev/console#$T/console#g" "$1" > "$T/btn"; : > "$T/calls"
	ACTION=$2 SEEN=$3 OVERLAY=/overlay PATH="$T/bin:$PATH" sh -c ". '$T/btn'" > /dev/null 2>&1; RC=$?
	sleep 0.5   # upstream runs `jffs2reset -y && reboot &` in the background
}
has(){ grep -q "^$1" "$T/calls"; }
chk(){ n=$((n + 1)); if eval "$2"; then echo "ok   $1"; else echo "FAIL $1 :: calls=[$(tr '\n' '|' < "$T/calls")] rc=$RC"; f=$((f + 1)); fi; }
R=$ROOT/etc/rc.button/reset; O=$ROOT/etc/rc.button/reset_override
[ -f "$R" ] && [ -f "$O" ] || { echo "FAIL no etc/rc.button/reset or reset_override under $ROOT"; exit 1; }
press "$R" pressed 0;  chk "reset: pressed -> return 5 (hold timer)" '[ "$RC" = 5 ]'
press "$R" released 1; chk "reset: short press -> reboot, no wipe" 'has "reboot" && ! has "jffs2reset"'
press "$R" released 6; chk "reset: 6 s press -> reboot + log line, NEVER jffs2reset" 'has "reboot" && has "logger" && ! has "jffs2reset"'
press "$O" pressed 0;  chk "reset_override: pressed -> return 5" '[ "$RC" = 5 ]'
press "$O" released 1; chk "reset_override: short press -> dpp push_button, no reboot" 'has "ubus call dpp push_button" && ! has "reboot"'
press "$O" released 3; chk "reset_override: 3 s -> nothing" '[ ! -s "$T/calls" ]'
press "$O" released 6; chk "reset_override: 6 s -> log + reboot, NEVER jffs2reset" 'has "reboot" && has "logger" && ! has "jffs2reset"'
# negative control: upstream reset wipes on the long press -> the judge must catch it
U=$TREE/package/base-files/files/etc/rc.button/reset
if [ -f "$U" ]; then
	press "$U" released 6; n=$((n + 1))
	if has "reboot" && ! has "jffs2reset"; then echo "FAIL negative control: upstream reset passed the no-wipe judge"; f=$((f + 1))
	else echo "ok   negative control: upstream reset (jffs2reset on a 6 s press) fails the judge"; fi
else echo "FAIL negative control: no upstream $U"; f=$((f + 1)); fi
echo "TEST-RC-BUTTON root=$ROOT cases=$n fails=$f"; [ "$n" -gt 0 ] && [ "$f" = 0 ]
