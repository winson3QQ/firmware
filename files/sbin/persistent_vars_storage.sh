#!/bin/sh
# persistent_vars_storage.sh — Batman #254 shim (replaces the Morse script of the same name).
#
# The Morse original reads "persistent vars" from the Raspberry Pi EEPROM (vcgencmd bootloader_config):
# dropbear_authorized_keys, device_password, default_wifi_key, mm_region(_unlocked), mm_sku, mm_mode,
# mm_virtual_wire, ... Nine readers in the image turn them into an SSH key, the root password, the
# onboarding AP key and a region lock. The EEPROM is not on the SD card: whatever a previous owner (or a
# root shell) wrote there survives re-flashing the card, so a resold node would come up with the previous
# owner's way in. Batman never reads them: READ always answers "absent", exactly as the original does for a
# key that is not set (rc 1, nothing on stdout) — which is what every Batman node's EEPROM holds today.
# Design: Batman docs/design/254-stage1-impl.md §4.5 (F21, F24). Gate: scripts/check-pvs-shim.sh.
#
#   READ <key>      rc 1, no stdout; one warning per key per boot (marker in the root-only run dir)
#   READALL         every known key as "key=" (empty), rc 0 — the original's output for an empty EEPROM
#   WRITE | ERASE   rc 1 (the original does not implement them on bcm2711 either)
op=${1:-}; key=${2:-}

# same list and order as the Morse original (READALL output must not change shape)
all_keys="device_password default_wifi_key dpp_priv_key mm_region mm_virtual_wire mm_mode dropbear_authorized_keys dropbear_ed25519_host_key dropbear_rsa_host_key"

usage(){ echo "persistent_vars_storage.sh OPERATION(READ|READALL|WRITE|ERASE) KEY [VALUE]" >&2; }

# warn once per key per boot; the marker lives in the root-only run dir (#280), never in world-writable /tmp
warn_once(){
	k=$(printf '%s' "$1" | tr -c 'A-Za-z0-9_' '_' | cut -c1-48)
	if [ -r /usr/lib/batman/rundir.sh ] && . /usr/lib/batman/rundir.sh && batman_rundir 2>/dev/null; then
		m="$RUNDIR/pvs-warned.$k"
		[ -e "$m" ] && return 0
		: > "$m" 2>/dev/null
	fi
	msg="persistent_vars_storage: EEPROM persistent vars are disabled in Batman (#254) — '$k' not read"
	logger -t persistent_vars_storage -p daemon.warn "$msg" 2>/dev/null
	{ echo "$msg" > /dev/kmsg; } 2>/dev/null
	return 0
}

case "$op" in
	READ)
		[ -n "$key" ] || { usage; exit 1; }
		warn_once "$key"
		echo "The key \"$key\" doesn't exist in bootloader config." >&2
		exit 1 ;;
	READALL)
		for k in $all_keys; do printf '%s=\n' "$k"; done
		exit 0 ;;
	WRITE|ERASE)
		echo "Writing to persistent memory is disabled in Batman (#254)." >&2
		exit 1 ;;
	*)
		usage; exit 1 ;;
esac
