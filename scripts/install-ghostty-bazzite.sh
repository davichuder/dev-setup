#!/usr/bin/env bash
# Bazzite only: layer Ghostty through the community COPR repository with
# rpm-ostree. Idempotent; activating the layer needs one reboot.
set -euo pipefail

if command -v ghostty >/dev/null 2>&1; then
  echo "ghostty: already installed"
  exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
  exec sudo "$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
fi

. /etc/os-release

cat > "/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:scottames:ghostty.repo" <<EOF
[copr:copr.fedorainfracloud.org:scottames:ghostty]
name=Copr repo for ghostty owned by scottames
baseurl=https://download.copr.fedorainfracloud.org/results/scottames/ghostty/fedora-${VERSION_ID}/x86_64/
type=rpm-md
skip_if_unavailable=False
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/scottames/ghostty/pubkey.gpg
enabled=1
enabled_metadata=1
EOF

rpm-ostree refresh-md
rpm-ostree install -y --allow-inactive ghostty

echo "ghostty: layered ok — reboot to activate the deployment (systemctl reboot)"
