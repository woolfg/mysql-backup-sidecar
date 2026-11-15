#!/bin/bash
set -euo pipefail

# Keep the version and verified release checksums shared by all maintained images.
rclone_version=1.76.0
architecture=$(dpkg --print-architecture)
case "${architecture}" in
    amd64) checksum=b00f00b3266c3764413afe599d3ec316f6f43b3e0ea8a0bc1d186d2133e46df7 ;;
    arm64) checksum=ee169016675e23a69d77240565133ff7dbc9b33d16fa8f7053d4af39f1eaeb78 ;;
    *) echo "Unsupported rclone architecture: ${architecture}" >&2; exit 1 ;;
esac

apt-get update
apt-get install -y --no-install-recommends zip unzip
work_dir=$(mktemp -d)
trap 'rm -rf "${work_dir}"' EXIT
archive="rclone-v${rclone_version}-linux-${architecture}"
curl -fsSLo "${work_dir}/rclone.zip" "https://downloads.rclone.org/v${rclone_version}/${archive}.zip"
printf '%s  %s\n' "${checksum}" "${work_dir}/rclone.zip" | sha256sum --check -
unzip -q "${work_dir}/rclone.zip" -d "${work_dir}"
install -m 0755 "${work_dir}/${archive}/rclone" /usr/local/bin/rclone
rclone version
rm -rf /var/lib/apt/lists/*
