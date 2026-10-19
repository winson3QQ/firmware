#!/bin/bash
# check-pvs-shim.sh ROOTFS_DIR — #254 build gate: the assembled rootfs must carry Batman's
# /sbin/persistent_vars_storage.sh shim (files/ overlay), not the Morse EEPROM reader, and nothing else
# in the image may read the Pi EEPROM config directly.
# Reads the extracted rootfs itself: check-image-manifest.sh only sees package manifests, not files/.
# Discriminating: a stub vcgencmd that "has" every persistent var is first in PATH, so the Morse original
# would print the values and exit 0; the shim must exit 1 with nothing on stdout for every key.
# Any missing input (rootfs not extracted, shim absent) is a FAIL, never a pass.
set -u
R=${1:?usage: check-pvs-shim.sh ROOTFS_DIR}
HERE=$(cd "$(dirname "$0")/.." && pwd)
WANT=$HERE/files/sbin/persistent_vars_storage.sh
GOT=$R/sbin/persistent_vars_storage.sh
# every key a reader in the image asks for (design 254-stage1-impl F21), not only the original's READALL list
KEYS="device_password default_wifi_key dpp_priv_key mm_region mm_region_unlocked mm_sku mm_virtual_wire mm_mode dropbear_authorized_keys dropbear_ed25519_host_key dropbear_rsa_host_key"
# the only files allowed to mention bootloader_config: the shim (comment) and 95's BOOT_ORDER log line
ALLOW="./etc/uci-defaults/95-batman-storage ./sbin/persistent_vars_storage.sh"
fail(){ echo "check-pvs-shim: FAIL: $*" >&2; exit 1; }
[ -d "$R/etc" ] || fail "rootfs '$R' not extracted (no etc/)"
[ -f "$WANT" ] || fail "tree has no $WANT"
[ -f "$GOT" ] || fail "rootfs has no /sbin/persistent_vars_storage.sh"
[ -x "$GOT" ] || fail "rootfs /sbin/persistent_vars_storage.sh not executable"
a=$(sha256sum < "$WANT" | cut -d' ' -f1); b=$(sha256sum < "$GOT" | cut -d' ' -f1)
[ "$a" = "$b" ] || fail "rootfs shim sha256 $b != files/ $a (Morse original or stale build)"
# exactly one file of that name (a second copy earlier in PATH would win)
n=$(cd "$R" && find . -name 'persistent_vars_storage*' | wc -l)
[ "$n" = 1 ] || fail "rootfs has $n files named persistent_vars_storage* (want 1): $(cd "$R" && find . -name 'persistent_vars_storage*' | tr '\n' ' ')"
# no new direct EEPROM-config reader
extra=$(cd "$R" && grep -rIl 'bootloader_config' . 2>/dev/null | while read -r f; do case " $ALLOW " in *" $f "*) ;; *) echo "$f";; esac; done)
[ -z "$extra" ] || fail "direct bootloader_config readers outside the allow list: $(echo $extra)"
S=$(mktemp -d); trap 'rm -rf "$S"' EXIT
{ echo '#!/bin/sh'; echo 'echo "BOOT_ORDER=0xf41"'; for k in $KEYS; do echo "echo \"$k=LEAK\""; done; } > "$S/vcgencmd"
printf '#!/bin/sh\nexit 0\n' > "$S/logger"
chmod 755 "$S/vcgencmd" "$S/logger"
SHELLS="sh"; command -v busybox >/dev/null 2>&1 && SHELLS="sh busybox_ash"
for shl in $SHELLS; do
	case $shl in busybox_ash) run(){ PATH="$S:/usr/bin:/bin" busybox ash "$GOT" "$@"; } ;; *) run(){ PATH="$S:/usr/bin:/bin" sh "$GOT" "$@"; } ;; esac
	for k in $KEYS; do
		out=$(run READ "$k" 2>/dev/null); rc=$?
		[ "$rc" = 1 ] || fail "[$shl] READ $k rc=$rc (want 1)"
		[ -z "$out" ] || fail "[$shl] READ $k printed '$out' (want nothing)"
	done
	out=$(run READALL 2>/dev/null); rc=$?
	[ "$rc" = 0 ] || fail "[$shl] READALL rc=$rc (want 0)"
	echo "$out" | grep -q LEAK && fail "[$shl] READALL leaked a value"
	echo "$out" | grep -qx 'default_wifi_key=' || fail "[$shl] READALL lacks 'default_wifi_key='"
	[ "$(echo "$out" | grep -vc '^[a-z_0-9]*=$')" = 0 ] || fail "[$shl] READALL has a non-empty line"
	run WRITE default_wifi_key x >/dev/null 2>&1 && fail "[$shl] WRITE succeeded"
done
echo "check-pvs-shim: OK (sha256 $a; $(echo $KEYS | wc -w) keys READ rc 1 silent under: $SHELLS; READALL empty; WRITE refused; 1 shim; direct readers only: $ALLOW)"
