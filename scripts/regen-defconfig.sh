#!/bin/sh
# Regenerate the committed recovery kernel defconfig.
#
# Occasional, out-of-band tool (NOT part of the build): run it when you bump the
# kernel or the config fragments, or edit linux.fragment. It fetches its own
# inputs at the revisions this tree pins, merges the build-scripts base config +
# feature fragments + our linux.fragment, flips every module to built-in (the
# recovery kernel is monolithic, the initramfs ships no modules), then
# `savedefconfig`-trims the result and writes it to
# board/flipperos-recovery/linux-recovery.defconfig. Review the diff and commit.
#
# Everything happens in a scratch directory; no source tree is written to.
#
# The normal build (make) just consumes that committed defconfig; it never runs this.
set -eu

# Start from a known environment. make copies command-line assignments into
# MAKEFLAGS, and an inherited O= is promoted to "command line" origin by the
# kernel's own Makefile - so `make regen-defconfig O=<dir>` would otherwise
# redirect the kernel build somewhere unintended. Unset them so this tool
# behaves identically however it was invoked.
unset MAKEFLAGS MFLAGS O KBUILD_OUTPUT 2>/dev/null || true

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEFCONFIG="$ROOT/configs/flipperos_recovery_defconfig"
FRAG="$ROOT/board/flipperos-recovery/linux.fragment"
OUT="$ROOT/board/flipperos-recovery/linux-recovery.defconfig"

# Scratch checkouts of the pinned sources. They live in the (gitignored) download
# cache, so they survive `make distclean` and cost one fetch per bump.
WORK="${REGEN_WORKDIR:-$ROOT/dl/regen}"

# $1 = destination, $2 = url, $3 = commit
fetch() {
	[ -n "$3" ] || { echo "error: no pinned version found for $2" >&2; exit 1; }
	if [ ! -d "$1/.git" ]; then
		mkdir -p "$1"
		git init -q "$1"
		git -C "$1" remote add origin "$2"
	fi
	git -C "$1" rev-parse -q --verify "$3^{commit}" >/dev/null 2>&1 \
		|| git -C "$1" fetch -q --depth 1 origin "$3"
	git -C "$1" checkout -q --detach "$3"
}

# $1 = option name; reads a quoted string out of the Buildroot defconfig
br2_opt() {
	sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p" "$DEFCONFIG"
}

# The kernel is whatever the defconfig pins, so the config this writes always
# belongs to the kernel the build will use.
K="$WORK/linux"
fetch "$K" "$(br2_opt BR2_LINUX_KERNEL_CUSTOM_REPO_URL)" \
	"$(br2_opt BR2_LINUX_KERNEL_CUSTOM_REPO_VERSION)"

# The config fragments come from the same build-scripts revision the USB-gadget
# package installs from, so the kernel config and the gadget files that drive it
# never describe different commits.
BS="$WORK/build-scripts"
fetch "$BS" \
	https://github.com/flipperdevices/flipperone-linux-build-scripts.git \
	"$(sed -n 's/^FLIPPER_USB_GADGET_VERSION ?= *//p' "$ROOT/package/flipper-usb-gadget/flipper-usb-gadget.mk")"

# base = build-scripts minconfig + its feature fragments (skip 'logo': needs a
# generated .ppm we do not build) + our recovery fragment (last, wins).
frags="$BS/configs/minconfig-mainline"
for f in bluetooth cameras nft rpmb wifi; do
	[ -f "$BS/configs/linux/$f" ] && frags="$frags $BS/configs/linux/$f"
done

# Build out-of-tree: every artifact of this run lands in $B and the checkouts stay
# pristine, so nothing here can leak into a later build. merge_config.sh needs the
# -O directory to exist already.
B="$WORK/kbuild"
rm -rf "$B"
mkdir -p "$B"

# -y makes built-in win over module while merging, which is the direction we want
# anyway - the recovery kernel is monolithic.
cd "$K"
./scripts/kconfig/merge_config.sh -y -O "$B" -m $frags "$FRAG" >/dev/null
make -C "$K" O="$B" ARCH=arm64 olddefconfig >/dev/null
# -y only settles the merge; olddefconfig can still pull in NEW =m symbols as
# dependencies resolve, so iterate the flip to a fixpoint.
i=0
while grep -q '=m$' "$B/.config" && [ "$i" -lt 8 ]; do
	sed -i 's/=m$/=y/' "$B/.config"
	make -C "$K" O="$B" ARCH=arm64 olddefconfig >/dev/null
	i=$((i + 1))
done
# anything still =m cannot be built in (a dependency forbids =y). Do NOT silently
# drop it: stop and report so a human decides. Encode the resolution explicitly in
# linux.fragment (set =y with the needed deps, or "# CONFIG_X is not set"), re-run.
if grep -q '=m$' "$B/.config"; then
	echo "ERROR: these refuse to build in - resolve in linux.fragment, then re-run:" >&2
	grep '=m$' "$B/.config" | sed 's/=m$//; s/^/  /' >&2
	exit 1
fi
make -C "$K" O="$B" ARCH=arm64 savedefconfig >/dev/null
cp "$B/defconfig" "$OUT"
echo "wrote $OUT ($(grep -c '=y' "$OUT") builtin, 0 modules, $(wc -l < "$OUT") lines)"
