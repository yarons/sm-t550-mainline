# Building

The image is produced by `pmos-gt510.sh`, a driver around pmbootstrap that runs inside a privileged container.

## Builder

- `build-host/Dockerfile`: debian:trixie-slim + pmbootstrap. Build it as `gt510-pmos`.
- A docker volume for pmbootstrap's work dir (`gt510-pmos-vol` below), the repository mounted read-only at
  `/src`, an output directory at `/dist`.
- x86_64 hosts work (cross-builds via pmbootstrap); `install` needs the host's `loop` kernel module.
- `build-host/gt510-queue.sh "<name>:<target> [args]" …` runs jobs one after another (logs in `logs/<name>.log`)
  and waits while other heavy containers run; wrap it in `systemd-inhibit` if the host suspends when idle.

```bash
docker run --rm --privileged -v /dev:/dev -v "$PWD:/src:ro" -v gt510-pmos-vol:/work -v "$PWD/dist:/dist" \
  -e PMOS_PASSWORD=<password> gt510-pmos /src/pmos-gt510.sh <target>
```

## Targets

| Target | What it does | Time (12-thread x86_64) |
|---|---|---|
| `kernel73` | applies `kernel/apply-7.3.sh` (retargets pmaports' linux-postmarketos-qcom-msm8916 to msm8916-mainline 7.3-rc2 @717e5e2 + `kernel/0*.patch` + `kernel/gt510.config`) and builds it | ~50 min cold, ~2 min with warm ccache |
| `localpkgs-only <pkg>` | builds one local package from `packages/` against the binary repos (use this; one Rust/crossdirect package per job) | 30 s (tweaks) - 30 min (snapshot) |
| `install` | personal image: SSH keys from `pubkeys/`, password from `PMOS_PASSWORD` | ~5.5 min |
| `install-public` | release image: no SSH keys, sshd disabled, UTC, password `PUBLIC_PASSWORD` (default 147147) | ~5.5 min |
| `release` | from the `install-public` rootfs: xz'd sparse userdata image, lk2nd, `MANIFEST.txt`, `SHA256SUMS` in `/dist/release` | ~5 min |
| `simg` | sparse image of the last install (for `fastboot` on macOS) | seconds |
| `lk2nd` | extracts the prebuilt lk2nd-msm8916 boot image | seconds |

Bump `pkgrel` in a package's APKBUILD (and in `kernel/apply-7.3.sh` + the APK name in `pmos-gt510.sh` for the
kernel) for every rebuild that should be installable over the previous one.

## Signing

pmbootstrap signs local packages with its own key. To install locally built APKs on a running tablet with `apk add`,
the tablet must trust that key (`/etc/apk/keys`); images built by `install` trust it automatically.

## Kernel module fast path

`kernel/kdev73.sh` (alpine:edge aarch64 container, a `gt510-kdev` volume) keeps a configured 7.3-rc2 tree with all
patches applied and the tablet's own config (`/proc/config.gz`): `setup` (~6 min), `msm` (~3 min, rebuilds
drivers/gpu/drm/msm), `module <dir>`. Test modules go to `/lib/modules/$(uname -r)/updates/` + `depmod` +
`mkinitfs` (msm and the panel driver are in the initramfs). Remove them before installing a kernel package.
