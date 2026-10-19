#!/bin/bash
# check-pvs-shim.sh ROOTFS_DIR — #254 build gate: the assembled rootfs must carry Batman's
# /sbin/persistent_vars_storage.sh shim (files/ overlay), not the Morse EEPROM reader.
# Reads the extracted rootfs itself: check-image-manifest.sh only sees package manifests, not files/.
# Discriminating: a stub vcgencmd that "has" default_wifi_key=LEAK is first in PATH, so the Morse
# original would print LEAK and exit 0; the shim must exit 1 with nothing on stdout.
# Any missing input (rootfs not extracted, shim absent) is a FAIL, never a pass.
set -u
R=${1:?usage: check-pvs-shim.sh ROOTFS_DIR}
HERE=$(cd "$(dirname "$0")/.." && pwd)
WANT=$HERE/files/sbin/persistent_vars_storage.sh
GOT=$R/sbin/persistent_vars_storage.sh
fail(){ echo "check-pvs-shim: FAIL: $*" >&2; exit 1; }
[ -d "$R/etc" ] || fail "rootfs '$R' not extracted (no etc/)"
[ -f "$WANT" ] || fail "tree has no $WANT"
[ -f "$GOT" ] || fail "rootfs has no /sbin/persistent_vars_storage.sh"
[ -x "$GOT" ] || fail "rootfs /sbin/persistent_vars_storage.sh not executable"
a=$(sha256sum < "$WANT" | cut -d' ' -f1); b=$(sha256sum < "$GOT" | cut -d' ' -f1)
[ "$a" = "$b" ] || fail "rootfs shim sha256 $b != files/ $a (Morse original or stale build)"
S=$(mktemp -d); trap 'rm -rf "$S"' EXIT
printf '#!/bin/sh\necho "BOOT_ORDER=0xf41"\necho "default_wifi_key=LEAK"\necho "dropbear_authorized_keys=LEAK"\n' > "$S/vcgencmd"
printf '#!/bin/sh\nexit 0\n' > "$S/logger"
chmod 755 "$S/vcgencmd" "$S/logger"
for k in default_wifi_key dropbear_authorized_keys; do
	out=$(PATH="$S:/usr/bin:/bin" sh "$GOT" READ "$k" 2>/dev/null); rc=$?
	[ "$rc" = 1 ] || fail "READ $k rc=$rc (want 1)"
	[ -z "$out" ] || fail "READ $k printed '$out' (want nothing)"
done
out=$(PATH="$S:/usr/bin:/bin" sh "$GOT" READALL 2>/dev/null); rc=$?
[ "$rc" = 0 ] || fail "READALL rc=$rc (want 0)"
echo "$out" | grep -q LEAK && fail "READALL leaked a value"
echo "$out" | grep -qx 'default_wifi_key=' || fail "READALL lacks 'default_wifi_key='"
[ "$(echo "$out" | grep -vc '^[a-z_0-9]*=$')" = 0 ] || fail "READALL has a non-empty line"
PATH="$S:/usr/bin:/bin" sh "$GOT" WRITE default_wifi_key x >/dev/null 2>&1 && fail "WRITE succeeded"
echo "check-pvs-shim: OK (sha256 $a; READ rc 1 silent; READALL empty; WRITE refused)"
