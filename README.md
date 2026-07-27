# flipperos-recovery

Buildroot builder for a **minimal, immutable Linux recovery initramfs** for
**Flipper One** (Rockchip **RK3576**, ARM64).

Unlike the general-purpose Debian OS (built in
[flipperone-linux-build-scripts](https://github.com/flipperdevices/flipperone-linux-build-scripts)),
this is a tiny, self-contained recovery system: **glibc + systemd + coreutils +
util-linux**, no BusyBox. It runs entirely from RAM, so once booted it holds
nothing open on storage and can repartition/reflash any device freely.

Everything is built by **Buildroot** from three pinned **git submodules**:
`buildroot`, the kernel ([`src/linux`](https://github.com/flipperdevices/flipper-linux-kernel)),
and [`src/build-scripts`](https://github.com/flipperdevices/flipperone-linux-build-scripts)
(shared kernel-config fragments + the USB-gadget files). The build produces:

- `output/images/rootfs.cpio` / `rootfs.cpio.zst` - the initramfs (kernel needs `CONFIG_RD_ZSTD`)
- `output/images/Image` + `rk3576-…dtb` - the **monolithic** kernel + device tree
- `output/images/recovery.img` / `recovery.img.zst` - a flashable **SD test image** (GPT + ext4 **BLS** boot partition)

The kernel is **monolithic** (no modules at all), so every driver the recovery
needs is built in (`=y`). There is **no bootloader** here: the device boots via
U-Boot SPL **Falcon** (developed elsewhere); this repo produces the initramfs
(and, later, a FIT). The SD image is a **testing convenience**; the production
flash is the device's Falcon path.

## Layout

```
.
├── build.sh                       # thin wrapper: submodule update + make
├── Makefile                       # out-of-tree wrapper around ./buildroot
├── local.mk                       # override-srcdir: build kernel + headers from src/linux
├── external.desc / Config.in / external.mk / package/Config.in
├── configs/
│   └── flipperos_recovery_defconfig
├── scripts/
│   └── regen-defconfig.sh         # occasional: regenerate the monolithic kernel defconfig
├── package/                       # empty; add a recovery-app package here later
├── board/flipperos-recovery/
│   ├── post-build.sh              # brand os-release, install gadget files, trim
│   ├── post-image.sh              # genimage: pack the flashable SD image
│   ├── linux.fragment             # recovery kernel-config delta (input to regen-defconfig.sh)
│   ├── linux-recovery.defconfig   # committed monolithic kernel defconfig (what Buildroot builds)
│   └── rootfs-overlay/            # NetworkManager br0/AP/eth/usb, dnsmasq, umtprd.conf, banner, …
├── buildroot/                     # submodule: Buildroot 2026.05.1
└── src/
    ├── linux/                     # submodule: flipper-linux-kernel (built via override-srcdir)
    └── build-scripts/             # submodule: kernel-config fragments + USB-gadget files
```

## Prerequisites

A normal Buildroot host: `make`, `gcc`, `git`, `cpio`, `bc`, `rsync`, `unzip`,
plus network access (Buildroot downloads package sources). A cross toolchain is
**not** needed - Buildroot builds its own.

## Usage

### Build (`build.sh`)

Clone with submodules, then build:

```sh
git clone --recurse-submodules <this-repo>
./build.sh                                    # check out submodules, then build everything
UBOOT=/path/u-boot-rockchip.bin ./build.sh    # embed U-Boot -> standalone SD-bootable image
./build.sh clean                              # make clean first, then build
./build.sh distclean                          # make distclean (drops output/) first, then build
```

[`build.sh`](build.sh) is a thin wrapper: it runs `git submodule update --init`
(the submodules are pinned by gitlink) and then `make`. Buildroot does the rest -
toolchain, the monolithic kernel from `src/linux` (via override-srcdir), the
initramfs, and the flashable SD image (`post-image.sh` + genimage). Builds are
incremental; the download cache lives in `./dl/`. (Overlay *deletions* need
`./build.sh clean`, since Buildroot's overlay is additive.)

### Just `make`

```sh
git submodule update --init --recursive   # buildroot + src/linux + src/build-scripts
make                                       # auto-loads the defconfig, builds everything
ls output/images/                          # Image  *.dtb  rootfs.cpio.zst  recovery.img[.zst]
```

Any Buildroot target is forwarded through the toplevel `Makefile`:

```sh
make menuconfig                    # tweak the config
make savedefconfig                 # write changes back to configs/
make dropbear-rebuild              # rebuild one package
make clean                         # clean the output/build tree
make distclean                     # remove ./output entirely
make O=/tmp/build                  # override the output directory
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
| linux-firmware (MediaTek MT7921 + BT) | `BR2_PACKAGE_LINUX_FIRMWARE_MEDIATEK_MT7921(_BT)` | MT7961 WiFi + BT firmware blobs |
| e2fsprogs (+resize2fs) / dosfstools / parted / gptfdisk | - | mkfs/repartition/repair/grow (`mkfs.ext4`, `resize2fs`, `mkfs.vfat`, `parted`, `sgdisk`) |
| btrfs-progs + compsize | `BR2_PACKAGE_BTRFS_PROGS` / `BR2_PACKAGE_COMPSIZE` | main-OS root is **btrfs**: check/repair/resize + report on-disk compression |
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
`sed`, `awk` (mawk), `find`/`xargs`/`locate` (findutils), `less`, `nano`, `jq`,
`tar`, `gzip`/`gunzip`/`zcat`, `zstd`/`unzstd`/`zstdcat`/`zstdgrep`, `pcre2grep`.

**Processes / system** (procps-ng + systemd): `ps top pgrep pkill pidof kill pmap
free vmstat uptime watch slabtop`; `systemctl journalctl udevadm dmesg
timedatectl resolvectl busctl systemd-analyze`-family; `run0`.

**Partitioning** (util-linux + gptfdisk + parted): `fdisk sfdisk cfdisk`,
`gdisk sgdisk`, `parted partprobe`, `blkid lsblk findmnt findfs wipefs blockdev
losetup blkdiscard blkzone`, `mount`/`umount`, `swapon`/`mkswap`.

**Filesystems**: ext - `mkfs.ext{2,3,4} e2fsck resize2fs tune2fs dumpe2fs e2label
e4crypt badblocks filefrag` (e2fsprogs); FAT - `mkfs.fat/mkdosfs fsck.fat`
(dosfstools); btrfs - `mkfs.btrfs btrfs btrfsck btrfs-convert fsck.btrfs`
(btrfs-progs) + `compsize` (btrfs on-disk compression report); `fstrim fsfreeze`.
Kernel also mounts exFAT / NTFS3 / HFS+/HFS / ISO9660 (drivers built-in).

**Storage devices**: `nvme` (nvme-cli); sg3-utils (`sg_* rescan-scsi-bus.sh`) for
SCSI/**UFS**; `rtcwake`.

**Networking**: iproute2 (`ip ss bridge tc nstat`), iputils (`ping arping
tracepath clockdiff`); **NetworkManager** (`nmcli nmtui nmtui-edit nm-online`) +
`NetworkManager` daemon; `resolvectl` (systemd-resolved, mDNS); `dnsmasq` (DHCP on
`br0`); `curl`/`wcurl` + CA bundle; SSH via **dropbear** (`dbclient` = ssh client,
`scp`, `dropbearkey`, `dropbearconvert`; `dropbear` server runs by default).

**Wireless**: `iw`, `rfkill`, `wpa_supplicant`/`wpa_cli` (NM's WiFi backend,
MT7921U); `wireless-regdb` (regulatory DB - set country with `iw reg set <CC>`).

**USB gadget** (from the build-scripts submodule): `usb-gadget-setup.sh` (engine) + presets
(`usb-ncm-msc-mtp-gadget.sh`, `usb-ncm-gadget.sh`, `usb-msc-gadget.sh`,
`usb-mtp-gadget.sh`, `usb-acm-gadget.sh`, `usb-gadget-reconnect.sh`); `umtprd`
(MTP responder). Default composite auto-starts; see the gadget section below.

**Audio** (alsa-utils, NAU8822): `aplay arecord amixer alsamixer alsactl
speaker-test`.

**Crypto / TLS**: `openssl`, `sha*sum`/`b2sum`, `ca-certificates` bundle.

**Firmware** (not commands): `linux-firmware` MediaTek **MT7921 WiFi + BT** blobs.

**Recovery-specific**: `recovery-banner` (the login banner script).

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

All boot artifacts use **zstd** (fast decompress, small size):

- **initramfs** - `rootfs.cpio.zst` (this repo) + `CONFIG_RD_ZSTD` in the kernel.
  U-Boot loads the `.cpio.zst` as-is (the BLS `initrd`) and the **kernel** unpacks
  it via `RD_ZSTD` - one compress at build, one decompress at boot.
- **kernel Image** - `CONFIG_KERNEL_ZSTD`, set in the recovery defconfig
  (see `linux.fragment`).

The theoretical fastest-decompress initramfs is *uncompressed* (kernel memcpy,
no decompress), but on this device (fast UFS, 8 GB RAM) it's ~a wash with zstd
and costs ~60 MB more image, so zstd stays the default.

### Kernel

The kernel is built by Buildroot from the `src/linux` submodule (via
`override-srcdir` in [`local.mk`](local.mk), so the pinned checkout is used
verbatim - no re-download) using the committed **monolithic** defconfig
[`board/flipperos-recovery/linux-recovery.defconfig`](board/flipperos-recovery/linux-recovery.defconfig).
Every driver is built **in** (`=y`); the initramfs ships **no modules**.

That defconfig is generated, not hand-edited. [`scripts/regen-defconfig.sh`](scripts/regen-defconfig.sh)
merges the `build-scripts` base config + feature fragments with the recovery
delta in [`board/flipperos-recovery/linux.fragment`](board/flipperos-recovery/linux.fragment)
(`CONFIG_RD_ZSTD`, `devtmpfs`, the **UFS/MMC + ext4/vfat + networking + WiFi**
stacks, legacy-gadget disables, subsystem trims), flips every module to built-in,
and `savedefconfig`-trims the result. It is an **occasional, out-of-band** tool -
run it when you bump the kernel/build-scripts submodule or edit `linux.fragment`,
review the diff, and commit. The normal `make` never runs it; it just consumes the
committed defconfig.

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
`10-flipusb.link` rename, and the `9*-*.rules` udev rules are installed into the
target by [`post-build.sh`](board/flipperos-recovery/post-build.sh) straight from
the **`src/build-scripts` submodule** (not vendored into this repo, so they track
the main OS). Recovery-specific bits stay committed in the overlay: `umtprd.conf`
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
on**. Both the `linux` and the toolchain `linux-headers` packages are pointed at
the **same** `src/linux` submodule via `override-srcdir` ([`local.mk`](local.mk)),
so headers and kernel come from one commit by construction - no fetch, no pinning
step to keep in sync. `BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_7_0` sets the headers
**series gate** (7.x) that Buildroot uses to feature-gate packages; the actual
headers are whatever `src/linux` is (a superset).

## Flashable SD test image

The build already emits `output/images/recovery.img` (+ `.zst`) via
[`board/flipperos-recovery/post-image.sh`](board/flipperos-recovery/post-image.sh),
which stages a **BLS** boot tree (kernel `Image` + DTB + `rootfs.cpio.zst` +
`/boot/loader/entries/recovery.conf`) and hands it to **genimage**: an ext4 boot
partition wrapped in a GPT disk (512-byte sectors, for SD cards). Set `UBOOT=` to
embed the Rockchip loader at sector 64 so the SD boots standalone:

```sh
UBOOT=/path/to/u-boot-rockchip.bin ./build.sh   # u-boot-rockchip.bin from build-scripts build-uboot.sh

# SD is 512-byte sectors - flash the whole card:
zstdcat output/images/recovery.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync
```

Boot flow: RK3576 boot ROM loads the Rockchip loader at sector 64 → U-Boot → its
`bls` bootmeth finds `/boot/loader/entries/recovery.conf` on the ext4 partition →
boots `Image` + `rootfs.cpio.zst` + the DTB from `/boot/dtb`. Without `UBOOT=` the
image has no embedded loader and boots only where U-Boot already scans the SD. The
initramfs is the whole recovery OS (runs from RAM).

This SD image is a **testing convenience**. The production flash is the device's
U-Boot SPL **Falcon** path (built elsewhere), for which this repo will emit a FIT.
Quick validation without flashing at all: **kexec** the cpio from a running system.

## Pinning

All three sources are **git submodules**, pinned by gitlink (the commit each is
checked out at is recorded in this repo). Shallow-cloned per `.gitmodules`.

- **buildroot** - release **2026.05.1**
- **src/linux** - [flipper-linux-kernel](https://github.com/flipperdevices/flipper-linux-kernel) (`flipper-devel`)
- **src/build-scripts** - [flipperone-linux-build-scripts](https://github.com/flipperdevices/flipperone-linux-build-scripts)

Bump one by checking out a new commit inside the submodule and committing the
gitlink here (for the kernel, re-run `scripts/regen-defconfig.sh` and commit the
refreshed defconfig alongside it):

```sh
cd src/linux && git fetch && git checkout <ref> && cd ../..
./scripts/regen-defconfig.sh          # refresh the monolithic defconfig
git add src/linux board/flipperos-recovery/linux-recovery.defconfig && git commit
```
