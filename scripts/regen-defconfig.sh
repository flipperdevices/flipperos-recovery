#!/bin/sh
# Regenerate the committed recovery kernel defconfig.
#
# Occasional, out-of-band tool (NOT part of the build): run it when you bump the
# kernel or build-scripts submodule, or edit linux.fragment. It merges the
# build-scripts base config + feature fragments + our linux.fragment, flips every
# module to built-in (the recovery kernel is monolithic, the initramfs ships no
# modules), then `savedefconfig`-trims the result and writes it to
# board/flipperos-recovery/linux-recovery.defconfig. Review the diff and commit.
#
# The normal build (make) just consumes that committed defconfig; it never runs this.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
K="$ROOT/src/linux"
BS="$ROOT/src/build-scripts"
FRAG="$ROOT/board/flipperos-recovery/linux.fragment"
OUT="$ROOT/board/flipperos-recovery/linux-recovery.defconfig"

[ -f "$K/Makefile" ]  || { echo "error: kernel submodule missing (git submodule update --init src/linux)" >&2; exit 1; }
[ -d "$BS/configs" ]  || { echo "error: build-scripts submodule missing (git submodule update --init src/build-scripts)" >&2; exit 1; }

# base = build-scripts minconfig + its feature fragments (skip 'logo': needs a
# generated .ppm we do not build) + our recovery fragment (last, wins).
frags="$BS/configs/minconfig-mainline"
for f in bluetooth cameras nft rpmb wifi; do
	[ -f "$BS/configs/linux/$f" ] && frags="$frags $BS/configs/linux/$f"
done

cd "$K"
./scripts/kconfig/merge_config.sh -m $frags "$FRAG" >/dev/null
make ARCH=arm64 olddefconfig >/dev/null
# monolithic: flip every module to built-in. olddefconfig can pull in NEW =m
# symbols as dependencies resolve, so iterate the flip to a fixpoint.
i=0
while grep -q '=m$' .config && [ "$i" -lt 8 ]; do
	sed -i 's/=m$/=y/' .config
	make ARCH=arm64 olddefconfig >/dev/null
	i=$((i + 1))
done
# anything still =m cannot be built in (a dependency forbids =y). Do NOT silently
# drop it: stop and report so a human decides. Encode the resolution explicitly in
# linux.fragment (set =y with the needed deps, or "# CONFIG_X is not set"), re-run.
if grep -q '=m$' .config; then
	echo "ERROR: these refuse to build in - resolve in linux.fragment, then re-run:" >&2
	grep '=m$' .config | sed 's/=m$//; s/^/  /' >&2
	exit 1
fi
make ARCH=arm64 savedefconfig >/dev/null
cp defconfig "$OUT"
echo "wrote $OUT ($(grep -c '=y' "$OUT") builtin, 0 modules, $(wc -l < "$OUT") lines)"
