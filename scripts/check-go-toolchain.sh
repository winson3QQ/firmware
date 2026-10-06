#!/bin/sh
# check-go-toolchain.sh — every Go program in the image must be built by the tree's own Go (Batman #252)
#
#   scripts/check-go-toolchain.sh <rootfs-dir>      e.g. build_dir/target-aarch64_cortex-a72_musl/root-bcm27xx
#
# Reads the buildinfo each Go binary embeds (`go version <dir>` walks the tree, skips non-Go files, works
# on arm64 binaries from an amd64 host go, survives OpenWrt's strip) and refuses the image when:
#   - any Go binary was built by a Go other than staging_dir/hostpkg/lib/go-<GO_DEFAULT_VERSION>/VERSION
#     (1.5.2 and earlier: docker/dockerd/containerd/runc were silently built by the host's go 1.22.2), or
#   - an expected Go program is missing from the scan (so a broken scan can never "pass").
# The expected Go version comes from the tree (OpenMANET golang-values.mk + the staged go), never typed.
set -eu
ROOT=${1:?usage: check-go-toolchain.sh <rootfs-dir>}
[ -d "$ROOT" ] || { echo "check-go-toolchain: $ROOT is not a directory" >&2; exit 2; }
# the Go programs every Batman image carries (both boards); add here when a new one is baked in
REQUIRED="usr/bin/dockerd usr/bin/docker usr/bin/containerd usr/sbin/runc usr/bin/openmanetd usr/sbin/tailscaled usr/bin/openvlm"

V=$(sed -n 's/^GO_DEFAULT_VERSION:=//p' feeds/openmanet/lang/golang/golang-values.mk | head -1)
GO=staging_dir/hostpkg/lib/go-$V/bin/go
[ -n "$V" ] && [ -x "$GO" ] || { echo "check-go-toolchain: no staged go for GO_DEFAULT_VERSION='$V' ($GO)" >&2; exit 1; }
WANT=$(head -1 "staging_dir/hostpkg/lib/go-$V/VERSION")
case "$WANT" in go1.*) ;; *) echo "check-go-toolchain: cannot read the staged go version ($WANT)" >&2; exit 1 ;; esac

OUT=$("$GO" version "$ROOT" 2>/dev/null || true)     # "<path>: go1.x.y" per Go binary
bad=0; n=0
while IFS= read -r line; do
	[ -n "$line" ] || continue
	n=$((n + 1)); f=${line%%: *}; v=${line##*: }
	[ "$v" = "$WANT" ] || { echo "check-go-toolchain: ${f#$ROOT/} built by $v, want $WANT" >&2; bad=1; }
done <<EOF
$OUT
EOF
for r in $REQUIRED; do
	printf '%s\n' "$OUT" | grep -q "^$ROOT/$r: " || { echo "check-go-toolchain: expected Go program $r not found in $ROOT" >&2; bad=1; }
done
[ "$bad" = 0 ] || { echo "check-go-toolchain: REFUSING — $n Go binaries scanned" >&2; exit 1; }
echo "check-go-toolchain: OK — $n Go binaries, all $WANT (staged go-$V), required present: $(echo $REQUIRED | wc -w)"
