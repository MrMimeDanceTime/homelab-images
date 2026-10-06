#!/usr/bin/env bash
# Bake a Proxmox-ready Debian 13 image from the official genericcloud build.
#
# Source:  newest dated build under cloud.debian.org/images/cloud/trixie/
# Changes: apt upgrade, qemu-guest-agent installed, per-instance identity
#          (machine-id, SSH host keys) wiped so every clone generates its own.
# Output:  $OUT_DIR/<name>.qcow2, <name>.qcow2.sha512, build-info.json
#
# Debian publishes SHA512SUMS for cloud images but does not sign it, so the
# checksum proves the download is intact, not who made it. Authenticity rests
# on HTTPS to cloud.debian.org; the exact source URL and digest are recorded
# in build-info.json so every release can be traced back to its input.
set -euo pipefail

BASE=https://cloud.debian.org/images/cloud/trixie
UPSTREAM=debian-13-genericcloud-amd64
OUT_DIR=${OUT_DIR:-out}

build_id=$(curl -fsSL "$BASE/" \
  | grep -oE 'href="[0-9]{8}-[0-9]+/"' \
  | sed -E 's/href="([^/]+)\/"/\1/' \
  | sort -u | tail -1)
[ -n "$build_id" ] || { echo "could not find a dated build under $BASE" >&2; exit 1; }
src="$BASE/$build_id"
# Dated directories carry the build id in the file name; only latest/ does not.
file="$UPSTREAM-$build_id.qcow2"
name="debian-13-pve-$build_id-$(date -u +%Y%m%d)"

mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

echo "Source: $src/$file"
curl -fsSLO "$src/$file"
curl -fsSLO "$src/SHA512SUMS"
grep " $file\$" SHA512SUMS | sha512sum -c -
upstream_sha512=$(grep " $file\$" SHA512SUMS | cut -d' ' -f1)

cp "$file" work.qcow2

virt-customize -a work.qcow2 \
  --update \
  --install qemu-guest-agent \
  --run-command 'apt-get clean' \
  --run-command 'rm -f /etc/ssh/ssh_host_*' \
  --truncate /etc/machine-id

# virt-customize --install has been seen to fail quietly. Check the package
# really landed, and that no host keys or machine-id survived.
status=$(virt-cat -a work.qcow2 /var/lib/dpkg/status \
  | awk '/^Package: qemu-guest-agent$/ {found=1} found && /^Status:/ {print; exit}')
[ "$status" = "Status: install ok installed" ] \
  || { echo "qemu-guest-agent is not installed in the image (got: '$status')" >&2; exit 1; }
agent_version=$(virt-cat -a work.qcow2 /var/lib/dpkg/status \
  | awk '/^Package: qemu-guest-agent$/ {found=1} found && /^Version:/ {print $2; exit}')
if virt-ls -a work.qcow2 /etc/ssh | grep -q '^ssh_host_'; then
  echo "SSH host keys present in the image" >&2; exit 1
fi
[ "$(virt-cat -a work.qcow2 /etc/machine-id | wc -c)" -eq 0 ] \
  || { echo "/etc/machine-id is not empty" >&2; exit 1; }

virt-sparsify --quiet --in-place work.qcow2
qemu-img convert -c -O qcow2 work.qcow2 "$name.qcow2"
rm -f work.qcow2 "$file" SHA512SUMS

sha512sum "$name.qcow2" > "$name.qcow2.sha512"

cat > build-info.json <<EOF
{
  "name": "$name",
  "image": "$name.qcow2",
  "sha512": "$(cut -d' ' -f1 "$name.qcow2.sha512")",
  "upstream": {
    "url": "$src/$file",
    "build": "$build_id",
    "sha512": "$upstream_sha512"
  },
  "qemu_guest_agent": "$agent_version",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

cat build-info.json
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "name=$name" >> "$GITHUB_OUTPUT"
fi
