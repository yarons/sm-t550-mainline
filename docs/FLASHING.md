# Flashing the SM-T550 (gt510wifi)

**This erases the tablet.** Android and all data on the internal storage are replaced. Back up first. Flashing a
non-Samsung boot image may also set the Knox warranty bit, which cannot be undone. You can return to Android at
any time by flashing a stock firmware with Odin, heimdall or samloader.

Boot chain after installation: Samsung bootloader → **lk2nd** (on the BOOT partition) → Linux from the
**userdata** partition. lk2nd is installed once; later updates only rewrite userdata.

## What you need

- Release files: `lk2nd-msm8916.img`, `gt510-unofficial-pmos-<date>-userdata.simg.xz`, `SHA256SUMS`
  (`sha256sum -c SHA256SUMS`, or `shasum -a 256 -c SHA256SUMS` on macOS).
- A tool that speaks Samsung's download protocol: [heimdall](https://git.sr.ht/~grimler/Heimdall) (Linux/macOS),
  samloader, or Odin (Windows).
- `fastboot` (Android platform tools) and `xz`.
- A micro-USB data cable. On macOS, use `fastboot -S 64M` (large transfers have been seen to fail without it).

## 1. Prepare Android (stock firmware)

1. Remove the Google account from the tablet (avoids Factory Reset Protection).
2. If *Settings → Developer options* shows **OEM unlocking**, turn it on. (On the 7.1.1 firmware this toggle is
   often hidden; flashing still worked here.)

## 2. Install lk2nd to BOOT (once)

1. Enter download mode: power off, then hold **Home + Volume Down + Power**, confirm with **Volume Up**
   (or `adb reboot download` from Android).
2. Flash lk2nd to the BOOT partition, for example with heimdall:

   ```bash
   heimdall flash --BOOT lk2nd-msm8916.img
   ```

   (samloader: `-p BOOT lk2nd-msm8916.img`; Odin: pack it as `boot.img` in a tar and flash it as AP.)
3. The tablet reboots into lk2nd. lk2nd identifies the device as `samsung,gt510wifi`.

## 3. Flash the system to userdata

1. Enter lk2nd's fastboot: power on holding **Volume Down** (keep holding until the fastboot screen appears).
   Check with `fastboot devices`.
2. Decompress and flash:

   ```bash
   xz -dk gt510-unofficial-pmos-<date>-userdata.simg.xz
   fastboot -S 64M flash userdata gt510-unofficial-pmos-<date>-userdata.simg
   fastboot reboot
   ```

   Flashing takes about 6-7 minutes over USB 2.0.

## 4. First boot

- The first boot takes about 70 s; the root filesystem grows to fill userdata (~10 GB).
- Phosh starts logged in as `user`. Password: **147147** — change it right away with `passwd` in the terminal.
- Wi-Fi: Settings → Wi-Fi. Time zone: Settings → Date & Time (the image ships with UTC).
- SSH is installed but disabled. Enable it with `sudo systemctl enable --now sshd` only after changing the
  password: the nftables firewall is active, but its default rule (`/etc/nftables.d/50_sshd.nft`) accepts SSH on
  every interface, Wi-Fi included.
- USB networking: connecting to a computer gives the tablet 172.16.42.1 (postmarketOS default).

## Updating later

Only userdata needs flashing: boot into lk2nd fastboot (Volume Down at power on) and repeat step 3.
Your data lives on userdata too, so copy it off first (or keep it on a microSD card).

## Troubleshooting

- `fastboot` hangs or fails mid-transfer: re-enter lk2nd fastboot (hold Power + Volume Down until it restarts,
  keep Volume Down held) and retry with `-S 64M`.
- No picture after flashing: make sure `lk2nd-msm8916.img` went to **BOOT**, not RECOVERY.
- Several Android/fastboot devices attached: address this one with `fastboot -s <serial>`.
