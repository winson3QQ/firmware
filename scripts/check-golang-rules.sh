#!/bin/sh
# check-golang-rules.sh — are the packages feed's golang build rules the OpenMANET (= upstream openwrt-25.12)
# multi-version ones? (Batman #252)
#
#   scripts/check-golang-rules.sh        exit 0 = in sync, 1 = not (prints the differing files)
#
# Why: the installed `golang` is OpenMANET's multi-version meta package (go-$(GO_DEFAULT_VERSION) under
# staging_dir/hostpkg/lib, no unversioned `go`). The packages feed's own (24.10) golang-package.mk never
# puts that go on PATH, so its consumers (runc, containerd, dockerd, docker) silently built with the
# build host's system go (1.22.2, EOL). openmanet_setup.sh -i copies these files over; build-board.sh
# re-runs -i when this check fails, and refuses the build if it still fails after setup.
set -eu
# keep this list in sync with the copy in openmanet_setup.sh
GO_RULE_FILES="golang-package.mk golang-values.mk golang-compiler.mk golang-host-build.mk golang-build.sh go-gcc-helper go-strip-helper"
SRC=feeds/openmanet/lang/golang; DST=feeds/packages/lang/golang
[ -d "$SRC" ] && [ -d "$DST" ] || { echo "check-golang-rules: run from the firmware tree root after feeds update" >&2; exit 2; }
bad=0
for f in $GO_RULE_FILES; do
	cmp -s "$SRC/$f" "$DST/$f" || { echo "$DST/$f differs from $SRC/$f"; bad=1; }
done
exit $bad
