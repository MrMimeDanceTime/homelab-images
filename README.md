# homelab-images

Golden VM images for my Proxmox homelab, built from official upstream cloud
images and published as GitHub releases. The Proxmox side lives in my
infrastructure-as-code repo
([public mirror](https://github.com/MrMimeDanceTime/homelab-terraform)),
which downloads a pinned release and turns it into a template on Ceph.

## Images

| Image | Built from | Adds |
|---|---|---|
| `debian-13-pve-<build>-<date>` | Newest dated Debian 13 `genericcloud` build | `qemu-guest-agent` |

Official cloud images target public clouds, which do not use the QEMU guest
agent, so none of them ship it. Proxmox needs it to report IP addresses and to
shut guests down cleanly.

## What the build does

1. Finds the newest dated build under `cloud.debian.org/images/cloud/trixie/`
   and checks the download against its `SHA512SUMS`.
2. Downloads `qemu-guest-agent` and its dependencies from Debian 13 in a
   throwaway container, then runs `virt-customize` with networking off:
   installs them with `dpkg`, deletes SSH host keys and empties `/etc/machine-id` so every clone
   generates its own identity on first boot.
3. Verifies the result instead of trusting the tool: the agent package must
   be installed, and no host keys or machine ID may remain.
4. Sparsifies and compresses the image, then publishes it with its SHA-512,
   a `build-info.json` recording the exact upstream URL and digest, and a
   signed build provenance attestation.

Pull requests run the full build and verification but never publish. A
scheduled run every Monday picks up new upstream builds, which Debian
publishes with updates applied. `unattended-upgrades` ships in the image and
patches on first boot.

## Verifying a release

```bash
gh release download <tag> --repo MrMimeDanceTime/homelab-images
sha512sum -c <tag>.qcow2.sha512
gh attestation verify <tag>.qcow2 --repo MrMimeDanceTime/homelab-images
```

## Trust model

Debian publishes `SHA512SUMS` for its cloud images but does not sign it. The
checksum proves the download is intact; authenticity rests on HTTPS to
`cloud.debian.org`. Every release records its exact input, so any image can
be traced back to the upstream build it came from.

## Building locally

Needs a Linux host with `libguestfs-tools` and `qemu-utils`:

```bash
OUT_DIR=out bash debian-13/build.sh
```
