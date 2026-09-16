# flipperos-recovery

Buildroot builder for a **minimal, immutable Linux recovery initramfs** for
**Flipper One** (Rockchip **RK3576**, ARM64).

Unlike the general-purpose Debian OS (built in
[flipperone-linux-build-scripts](https://github.com/flipperdevices/flipperone-linux-build-scripts)),
this is a tiny, self-contained recovery system: **glibc + systemd + coreutils +
util-linux**, no BusyBox. It runs entirely from RAM, so once booted it holds
nothing open on storage and can repartition/reflash any device freely.

Everything is built by **Buildroot**, which is the repository's **only** git
submodule (pinned to a release). Every other source is pinned by commit sha in a
tracked file: the kernel ([flipper-linux-kernel](https://github.com/flipperdevices/flipper-linux-kernel))
in the Buildroot defconfig, and the USB-gadget files
([flipperone-linux-build-scripts](https://github.com/flipperdevices/flipperone-linux-build-scripts))
and btrfs profile/snapshot tooling
([flipperos-btrfs-tools](https://github.com/flipperdevices/flipperos-btrfs-tools))
in their package `.mk` files. The build produces:

- `output/images/rootfs.cpio` / `rootfs.cpio.zst` - the initramfs (kernel needs `CONFIG_RD_ZSTD`)
- `output/images/vmlinuz` - the **monolithic** kernel, a gzip-compressed arm64 `Image`
- `output/images/config` / `System.map` - the effective kernel config and symbol map
- `output/images/dtbs/rockchip/rk3576-*.dtb{,o}` - **every** RK3576 device tree and overlay, so one image boots any Flipper One revision and `add-dtbo` has the overlays to apply
- `output/images/recovery.img` / `recovery.img.zst` - a flashable **SD test image** (GPT + ext4 **BLS** boot partition), unless `SD_IMAGE=0`

The kernel is **monolithic** (no modules at all), so every driver the recovery
needs is built in (`=y`). There is **no bootloader** here: the device boots via
U-Boot SPL **Falcon** (developed elsewhere); this repo produces the initramfs
(and, later, a FIT). The SD image is a **testing convenience**; the production
flash is the device's Falcon path.

## Layout

```
.
├── Makefile                       # out-of-tree wrapper around ./buildroot; checks the submodule out on demand
├── external.desc / Config.in / external.mk / package/Config.in
│                                  # external.mk also stages the kernel artifacts into images/
├── configs/
│   └── flipperos_recovery_defconfig   # pins the kernel sha (both linux and linux-headers)
├── scripts/
│   └── regen-defconfig.sh         # regenerate the monolithic kernel defconfig (out-of-band, not part of the build)
├── package/                       # compsize, duperemove, flipper-btrfs-tools, flipper-usb-gadget
├── board/flipperos-recovery/
│   ├── linux-recovery.defconfig   # the monolithic kernel config - committed, reviewable
│   ├── linux.fragment             # recovery kernel-config delta (input to regen-defconfig.sh)
│   ├── post-build.sh              # brand + version-stamp os-release, trim
│   ├── post-image.sh              # genimage: pack the flashable SD image
│   ├── device_table.txt           # 0600 on the NetworkManager connection profiles
│   ├── users.table
│   └── rootfs-overlay/            # NetworkManager br0/AP/eth/usb, dnsmasq, umtprd.conf, banner, …
└── buildroot/                     # submodule: Buildroot 2026.05.1 (pinned)
```

## Prerequisites

A normal Buildroot host: `make`, `gcc`, `git`, `cpio`, `bc`, `rsync`, `unzip`,
plus network access (Buildroot downloads package sources). A cross toolchain is
**not** needed - Buildroot builds its own.

## Usage

### Build

```sh
git clone <this-repo> && cd flipperos-recovery
make                               # that's it
ls output/images/                  # vmlinuz  config  System.map  dtbs/  rootfs.cpio.zst  recovery.img[.zst]
```

There is no wrapper script and nothing to read first. The toplevel
[`Makefile`](Makefile) checks out the `buildroot` submodule on demand, loads the
defconfig on first use, and hands off to Buildroot for the toolchain, the kernel,
the initramfs and the SD image. Builds are incremental; the download cache lives
in `./dl/`. (Overlay *deletions* need `make clean`, since Buildroot's overlay is
additive.)

Any Buildroot target is forwarded through the same `Makefile`:

```sh
make menuconfig                    # tweak the config
make savedefconfig                 # write changes back to configs/
make dropbear-rebuild              # rebuild one package
make clean                         # clean the output/build tree
make distclean                     # remove ./output entirely
make regen-defconfig               # regenerate the kernel defconfig (see Kernel)
```

Knobs, all settable on the make command line or in the environment:

```sh
make O=/tmp/build                            # output directory       (default ./output)
make BR2_DL_DIR=/srv/dl                      # download cache         (default ./dl)
make SD_IMAGE=0                              # skip the SD test image (default 1)
make UBOOT=/path/u-boot-rockchip.bin         # embed U-Boot -> standalone SD-bootable image
make FLIPPER_BTRFS_TOOLS_VERSION=<sha>       # test another revision of a package
make FLIPPER_USB_GADGET_VERSION=<sha>
```

## What's in the image

| Component | Provided by | Why |
|-----------|-------------|-----|
| systemd (init + udev + resolved + timesyncd) | `BR2_INIT_SYSTEMD` | PID 1, `/dev`, DNS + mDNS, clock (for TLS) |
| bash | `BR2_PACKAGE_BASH` | `/bin/sh` - no BusyBox |
| coreutils | `BR2_PACKAGE_COREUTILS` | `ls`, `cp`, `dd`, `mkdir`, … |
| util-linux | `BR2_PACKAGE_UTIL_LINUX` | `mount`, `agetty`, `login`, `blkid`, `fdisk`/`sfdisk`, `wipefs`, `losetup`, `fsck`, `lsblk`, `dmesg` |
| grep / sed / mawk / findutils / tar / gzip / less / nano / procps-ng | - | the everyday tools BusyBox would provide (no BusyBox here): text processing, `find`/`xargs`, archives, pager, editor, `ps`/`top` |
| dropbear | `BR2_PACKAGE_DROPBEAR` | small SSH server (enabled via overlay) |
| iproute2 / iputils | - | `ip`, `ping` |
| NetworkManager (nmtui + nmcli) | `BR2_PACKAGE_NETWORK_MANAGER` | manages ethernet / WiFi (AP+station) / USB-gadget bridge |
| wpa_supplicant / iw / wireless-regdb | - | NM WiFi backend (MT7921U) + regdom |
| dnsmasq | `BR2_PACKAGE_DNSMASQ` | DHCP on the recovery bridge `br0` (no gateway) |
| umtprd | `BR2_PACKAGE_UMTPRD` (upstream) | MTP responder for the USB gadget (serves `/mnt/mtp`) |
| flipper-usb-gadget | `BR2_PACKAGE_FLIPPER_USB_GADGET` | the configfs gadget engine, its composite unit, the `flipusb0` rename and udev rules - shared with the main OS |
| linux-firmware (MediaTek MT7921 + BT) | `BR2_PACKAGE_LINUX_FIRMWARE_MEDIATEK_MT7921(_BT)` | MT7961 WiFi + BT firmware blobs |
| e2fsprogs (+resize2fs) / dosfstools / parted / gptfdisk | - | mkfs/repartition/repair/grow (`mkfs.ext4`, `resize2fs`, `mkfs.vfat`, `parted`, `sgdisk`) |
| exfatprogs / ntfs-3g (+ntfsprogs) | `BR2_PACKAGE_EXFATPROGS` / `BR2_PACKAGE_NTFS_3G` | create/repair exFAT + NTFS (`mkfs.exfat`, `fsck.exfat`, `mkntfs`, `ntfsfix`, `ntfsresize`) and read-write NTFS via `ntfs-3g` FUSE |
| btrfs-progs + compsize + duperemove | `BR2_PACKAGE_BTRFS_PROGS` / `BR2_PACKAGE_COMPSIZE` / `BR2_PACKAGE_DUPEREMOVE` | main-OS root is **btrfs**: check/repair/resize, on-disk compression report, offline dedup |
| flipper-btrfs-tools | `BR2_PACKAGE_FLIPPER_BTRFS_TOOLS` | btrfs profile/snapshot management (`-d` targets the unmounted OS partition from recovery) |
| rsync + sftp-server | `BR2_PACKAGE_RSYNC` / `BR2_PACKAGE_GESFTPSERVER` | file sync, and `scp`/`sftp` over the dropbear SSH server |
| nvme-cli / sg3-utils | - | NVMe + SCSI/**UFS** device introspection |
| zstd (CLI) | `BR2_PACKAGE_ZSTD` | de/compress images (the recovery cpio + kernel are zstd) |
| jq | `BR2_PACKAGE_JQ` | parse/emit JSON in recovery scripts |
| alsa-utils (`aplay`/`amixer`/`alsamixer`/`alsactl`/`speaker-test`) | `BR2_PACKAGE_ALSA_UTILS` | Flipper One audio (NAU8822 on SAI2) - test/adjust sound |
| curl + ca-certificates (OpenSSL) | - | fetch recovery images over HTTPS |

### Full tool reference

Everything callable in the recovery shell, grouped by job (package in parens).
No BusyBox - these are the full GNU/util-linux/etc. implementations.

**Shell & core** - `bash` (`/bin/sh`); coreutils (`ls cp mv rm dd cat head tail
sort uniq cut tr wc split tee stat du df ln mkdir chmod chown chroot truncate
shred base64 sha256sum …`); `login sulogin agetty su-less env` (util-linux).

**Text / search / archive** (no BusyBox applets - real tools): `grep`/`egrep`/`fgrep`,
`sed`, `awk` (mawk), `find`/`xargs`/`locate` (findutils), `cmp`/`diff` (diffutils),
`less`, `nano`, `jq`, `tar`, `gzip`/`gunzip`/`zcat`, `zstd`/`unzstd`/`zstdcat`/`zstdgrep`,
`pcre2grep`, `git` (also migrate-profile's merge engine).

**Processes / system** (procps-ng + systemd): `ps top pgrep pkill pidof kill pmap
free vmstat uptime watch slabtop`; `systemctl journalctl udevadm dmesg
timedatectl resolvectl busctl systemd-analyze`-family; `run0`.

**Partitioning** (util-linux + gptfdisk + parted): `fdisk sfdisk cfdisk`,
`gdisk sgdisk`, `parted partprobe`, `blkid lsblk findmnt findfs wipefs blockdev
losetup blkdiscard blkzone`, `mount`/`umount`, `swapon`/`mkswap`.

**Filesystems**: ext - `mkfs.ext{2,3,4} e2fsck resize2fs tune2fs dumpe2fs e2label
e4crypt badblocks filefrag` (e2fsprogs); FAT - `mkfs.fat/mkdosfs fsck.fat`
(dosfstools); exFAT - `mkfs.exfat fsck.exfat exfatlabel tune.exfat` (exfatprogs);
NTFS - `mkntfs/mkfs.ntfs ntfsfix ntfsresize ntfsclone ntfslabel ntfsinfo` plus the
read-write `ntfs-3g` FUSE mount (ntfs-3g); btrfs - `mkfs.btrfs btrfs btrfsck
btrfs-convert fsck.btrfs` (btrfs-progs) + `compsize` (on-disk compression report) +
`duperemove` (offline dedup); `fstrim fsfreeze`.
Kernel mounts exFAT + NTFS (legacy read-only driver; `ntfs-3g` adds read-write) +
HFS+/HFS + ISO9660 (all built-in).

**Storage devices**: `nvme` (nvme-cli); sg3-utils (`sg_* rescan-scsi-bus.sh`) for
SCSI/**UFS**; `rtcwake`.

**Networking**: iproute2 (`ip ss bridge tc nstat`), iputils (`ping arping
tracepath clockdiff`); **NetworkManager** (`nmcli nmtui nmtui-edit nm-online`) +
`NetworkManager` daemon; `resolvectl` (systemd-resolved, mDNS); `dnsmasq` (DHCP on
`br0`); `curl`/`wcurl` + CA bundle; `rsync`; SSH via **dropbear** (`dbclient` = ssh
client, `scp`/`sftp` via the `gesftpserver` subsystem, `dropbearkey`,
`dropbearconvert`; `dropbear` server runs by default).

**Wireless**: `iw`, `rfkill`, `wpa_supplicant`/`wpa_cli` (NM's WiFi backend,
MT7921U); `wireless-regdb` (regulatory DB - set country with `iw reg set <CC>`).

**USB gadget** (`flipper-usb-gadget` package): `usb-gadget-setup.sh` (engine) + presets
(`usb-ncm-msc-mtp-gadget.sh`, `usb-ncm-gadget.sh`, `usb-msc-gadget.sh`,
`usb-mtp-gadget.sh`, `usb-acm-gadget.sh`, `usb-gadget-reconnect.sh`); `umtprd`
(MTP responder). Default composite auto-starts; see the gadget section below.

**Audio** (alsa-utils, NAU8822): `aplay arecord amixer alsamixer alsactl
speaker-test`.

**Crypto / TLS**: `openssl`, `sha*sum`/`b2sum`, `ca-certificates` bundle.

**Firmware** (not commands): `linux-firmware` MediaTek **MT7921 WiFi + BT** blobs.

**Recovery-specific**: `recovery-banner` (the login banner script). **btrfs
profile/snapshot tooling** (`flipper-btrfs-tools` package, in `/usr/local/sbin`):
`list-profiles list-snapshots create-profile delete-profile rename-profile
create-snapshot send-snapshot receive-snapshot delete-snapshot migrate-profile
btrfs-maintenance btrfs-show-space add-dtbo`. In recovery `/` is a RAM rootfs, so
pass **`-d <device>`** to target the unmounted OS partition, e.g. `list-profiles -d
/dev/sda3`. `migrate-profile -d` carries a profile's user changes onto a newer base:
it merges files 3-way with `git merge-file` (hence **git**) using `cmp` (hence
**diffutils**), copies with `rsync -aHAX` (so rsync is built with **acl**), and
replays packages with the profile's own `apt` inside a chroot, so recovery itself
needs no apt/dpkg.

### Boot flow

The cpio has no `/etc/initrd-release`, so **systemd runs as the real PID 1**
(not a transient initrd). For an initramfs Buildroot installs a pre-init `/init`
that mounts `devtmpfs` and execs `/sbin/init`. systemd then mounts the API
filesystems, brings up NetworkManager + dropbear, and `systemd-getty-generator`
spawns a login on the kernel `console=` (agetty `--keep-baud`, so any serial
baud works - including RK3576's 1500000).

The **serial console auto-logs-in as root** (drop-in
`serial-getty@ttyS0.service.d/autologin.conf` adds `agetty --autologin root`), so
attaching a cable drops you straight into a root shell - no password at 1.5 Mbaud.

Root has a **fixed password** (`flipperone`, from
`BR2_TARGET_GENERIC_ROOT_PASSWD`), used for SSH and `login` elsewhere - the banner
advertises `root / flipperone` (matching the main OS's credential style).

### Boot-path compression

Both boot artifacts are compressed:

- **initramfs** - `rootfs.cpio.zst` (this repo) + `CONFIG_RD_ZSTD` in the kernel.
  U-Boot loads the `.cpio.zst` as-is (the BLS `initrd`) and the **kernel** unpacks
  it via `RD_ZSTD` - one compress at build, one decompress at boot.
- **kernel** - `vmlinuz` is the arm64 `Image` **gzipped**
  (`BR2_LINUX_KERNEL_IMAGEGZ`), decompressed by U-Boot. Note there is no
  `CONFIG_KERNEL_*` compressor involved: arm64 has no self-extracting kernel and
  selects no `HAVE_KERNEL_*` symbol, so those options do not exist there.

The theoretical fastest-decompress initramfs is *uncompressed* (kernel memcpy,
no decompress), but on this device (fast UFS, 8 GB RAM) it's ~a wash with zstd
and costs ~60 MB more image, so zstd stays the default.

### Kernel

Buildroot fetches [flipper-linux-kernel](https://github.com/flipperdevices/flipper-linux-kernel)
at the sha pinned in
[`configs/flipperos_recovery_defconfig`](configs/flipperos_recovery_defconfig) and
builds it with a **monolithic** config. Every driver is built **in** (`=y`); the
initramfs ships **no modules**.

That config is a **committed artifact**,
[`board/flipperos-recovery/linux-recovery.defconfig`](board/flipperos-recovery/linux-recovery.defconfig),
and a build only ever consumes it. Regenerating is a deliberate, out-of-band step:

```sh
make regen-defconfig     # then review the diff and commit it
```

[`scripts/regen-defconfig.sh`](scripts/regen-defconfig.sh) fetches the kernel at
that pinned sha and the config fragments at the sha
[`package/flipper-usb-gadget`](package/flipper-usb-gadget) pins, merges the
`build-scripts` base config + feature fragments with the recovery delta in
[`board/flipperos-recovery/linux.fragment`](board/flipperos-recovery/linux.fragment)
(`CONFIG_RD_ZSTD`, `devtmpfs`, the **UFS/MMC + ext4/vfat + networking + WiFi**
stacks, legacy-gadget disables, subsystem trims), flips every module to built-in
(**failing loudly** if a driver refuses `=y`), and `savedefconfig`-trims the
result. It works entirely in a scratch directory under `./dl/`, so no source tree
is ever written to. Edit `linux.fragment` to change what the recovery kernel
enables; run it again after bumping the kernel sha.

Because the config is committed, a kernel bump shows up in review as a config
diff rather than changing silently underneath a build.

### Networking (NetworkManager)

All interfaces are managed by **NetworkManager** - use `nmtui` (interactive) or
`nmcli`. `systemd-resolved` provides DNS + **mDNS**, so the device answers as
**`flipper-recovery.local`**. Connection profiles ship in the overlay
(`/etc/NetworkManager/system-connections/`):

- **`end0`** - DHCP **uplink** (management / internet), not bridged.
- **`br0`** - recovery LAN **bridge**, static **`10.0.0.1/24`** (+ `169.254.0.1/16`
  link-local), with slaves **WiFi-AP + `end1` + `flipusb0`**. `10.0.0.1` is the
  **same address the main OS serves on `flipusb0`**, so a connected PC reaches the
  Flipper at `10.0.0.1` on either OS. It is deliberately **not** `ipv4.method=shared`:
  recovery must never become a client's default gateway. **dnsmasq** serves DHCP
  on `br0` **without** a gateway/DNS option (`/etc/dnsmasq.d/recovery-br0.conf`),
  so a phone/laptop on the AP or USB-C gets `10.0.0.x` to reach the device
  (`ssh root@10.0.0.1`) while keeping its own internet route.

**WiFi AP** (`br0-wifi-ap`, `autoconnect=false`): an AP needs a regulatory
country and we ship **no default region** (world domain `00` forbids beaconing),
so bring it up with:

```sh
iw reg set <CC>            # e.g. DE US GB JP etc
nmcli con up br0-wifi-ap   # SSID FlipperOne-Recovery, WPA2 pass flipperone
```

Kernel side (`linux.fragment`, all built **in**, since the initramfs ships no
modules): `mt76`/`mt7921u`, `RFKILL`, `cfg80211`/`mac80211`, USB host,
**`USB_ONBOARD_DEV`** (powers the onboard hubs the NIC sits behind), and the
MediaTek **WiFi + BT** firmware (`MT7921` + `MT7921_BT`) - the combo device
reset-loops without the BT blob. NM/wpa_supplicant handle rfkill.

### USB gadget (NCM + MTP + mass-storage)

The gadget scripts (`usr/local/bin/usb-*.sh`), the two units used, the
`10-flipusb.link` rename, and the `9*-*.rules` udev rules come from the
**`flipper-usb-gadget` package** ([`package/flipper-usb-gadget`](package/flipper-usb-gadget)),
git-fetched from the main OS's build-scripts repo at a pinned sha - not vendored
here, so they stay the same files the main OS uses.
Recovery-specific bits stay committed in the overlay: `umtprd.conf`
(the `RAM-Disk` MTP label), `mnt-mtp.mount`, the gadget enable symlink, and the banner.
The default `usb-ncm-msc-mtp-gadget.service` builds a configfs composite:

- **NCM** - USB-C networking; `flipusb0` (renamed by `10-flipusb.link`) is a
  `br0` slave, so a plugged-in computer joins the recovery LAN.
- **MTP** - served by **`umtprd`** from a **tmpfs `/mnt/mtp`** (`mnt-mtp.mount`,
  up to 50% of RAM) - a drag-and-drop scratch area.
- **mass-storage** - the LUN is present but starts **empty** (no medium), so real
  media can be attached **without reconnecting the gadget**. `start` is idempotent:
  with the MSC function already in the composite, it swaps the backing device into
  the live LUN (`load_medium` → `lun.0/file`) and only unbinds the UDC when a *new*
  function must be added - so NCM and the MTP session stay up:
  ```sh
  usb-gadget-setup.sh start --sdcard   # attach the SD card to the running gadget
  usb-gadget-setup.sh start --sda      # ...or the internal UFS
  usb-gadget-setup.sh eject            # detach the medium (LUN stays, still no reconnect)
  ```

`linux.fragment` disables the **legacy gadget drivers** (`g_ether`, etc.) so
configfs owns the UDC.

### Kernel headers

The recovery userland is compiled against the **exact uapi of the kernel it runs
on**. The `linux` and the toolchain `linux-headers` packages declare the **same
commit sha**, so headers and kernel come from one tree by construction and
Buildroot downloads it once (both share `dl/linux/`). Bump the two
`..._REPO_VERSION` lines in the defconfig together.

`BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_7_0` sets the headers **series gate** that
Buildroot uses to feature-gate packages. It reads "7.0.x **or later**" and is the
only entry that selects `BR2_TOOLCHAIN_HEADERS_LATEST`, which is what keeps
Buildroot's headers version check in *loose* mode - so it stays correct as the
kernel moves through the 7.x series and must **not** be narrowed to match a
specific one, which would force a strict `major.minor` match and fail the build.

## Flashable SD test image

The build already emits `output/images/recovery.img` (+ `.zst`) via
[`board/flipperos-recovery/post-image.sh`](board/flipperos-recovery/post-image.sh),
which stages a **BLS** boot tree (`vmlinuz` + DTB + `rootfs.cpio.zst` +
`/boot/loader/entries/recovery.conf`) and hands it to **genimage**: an ext4 boot
partition wrapped in a GPT disk (512-byte sectors, for SD cards). Set `UBOOT=` to
embed the Rockchip loader at sector 64 so the SD boots standalone:

```sh
make UBOOT=/path/to/u-boot-rockchip.bin   # u-boot-rockchip.bin from build-scripts build-uboot.sh

# SD is 512-byte sectors - flash the whole card:
zstdcat output/images/recovery.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync
```

Boot flow: RK3576 boot ROM loads the Rockchip loader at sector 64 → U-Boot → its
`bls` bootmeth finds `/boot/loader/entries/recovery.conf` on the ext4 partition →
boots `/boot/vmlinuz` + `rootfs.cpio.zst` + the DTB from `/boot/dtbs`. Without
`UBOOT=` the image has no embedded loader and boots only where U-Boot already
scans the SD. The initramfs is the whole recovery OS (runs from RAM).

This SD image is a **testing convenience**, and `make SD_IMAGE=0` skips building
it. The production flash is the device's U-Boot SPL **Falcon** path (built
elsewhere), for which this repo will emit a FIT. Quick validation without flashing
at all: **kexec** the cpio from a running system.

## Sources & versioning

**Every source is pinned in a tracked file**, so one commit of this repo describes
exactly one build. There is no follow-latest mode: two builds of the same sha
produce the same image.

| Source | Pinned in | What it gives |
|--------|-----------|---------------|
| [buildroot](https://github.com/buildroot/buildroot) | the `buildroot` submodule gitlink (release **2026.05.1**) | the build system |
| [flipper-linux-kernel](https://github.com/flipperdevices/flipper-linux-kernel) | `BR2_{LINUX_KERNEL,KERNEL_HEADERS}_CUSTOM_REPO_VERSION` in [`configs/flipperos_recovery_defconfig`](configs/flipperos_recovery_defconfig) | the kernel **and** the uapi headers |
| [flipperone-linux-build-scripts](https://github.com/flipperdevices/flipperone-linux-build-scripts) | `FLIPPER_USB_GADGET_VERSION` in [`package/flipper-usb-gadget`](package/flipper-usb-gadget) | USB-gadget files + the kernel-config fragments |
| [flipperos-btrfs-tools](https://github.com/flipperdevices/flipperos-btrfs-tools) | `FLIPPER_BTRFS_TOOLS_VERSION` in [`package/flipper-btrfs-tools`](package/flipper-btrfs-tools) | btrfs profile/snapshot tooling |

A **branch name would not work** for the three package-style sources: Buildroot
keys both the download cache entry and the build directory on `VERSION`, and its
downloader returns early once the tarball exists - so a moving branch is fetched
once and then pinned forever to whatever it happened to be. Buildroot's own manual
says as much. Bump a sha instead:

```sh
# 1. edit the sha (defconfig for the kernel, the package .mk otherwise)
# 2. for a kernel bump, refresh the config it implies:
make regen-defconfig
# 3. review both diffs and commit
```

To test a revision without committing it, override on the command line:

```sh
make FLIPPER_BTRFS_TOOLS_VERSION=<sha>
make FLIPPER_USB_GADGET_VERSION=<sha>
```

Tag a commit and a plain `git clone` of that tag reproduces the build - the
`buildroot` submodule is checked out by `make` itself.

### Build provenance

Each image records exactly what it was built from, so an override on the command
line is still visible in the shipped artifact.
[`post-build.sh`](board/flipperos-recovery/post-build.sh) stamps
`/usr/lib/os-release` (also `/etc/os-release`) with `BUILD_GIT` (this repo's
`git describe`), `KERNEL_GIT` (read from the config Buildroot is building from)
and `BUILD_SCRIPTS_GIT` / `BTRFS_TOOLS_GIT` (read from Buildroot's version-keyed
build directories, so they name the shas actually built). `BUILD_GIT` gains a
`-dirty` suffix for any edit to this tree, the `buildroot` gitlink included -
every source is pinned here now, so an edit anywhere genuinely changes what the
image is.
