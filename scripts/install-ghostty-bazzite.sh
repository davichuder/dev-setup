#!/usr/bin/env bash
# Bazzite only: layer Ghostty through the community COPR repository with
# rpm-ostree. Idempotent; activating the layer needs one reboot.
set -euo pipefail

if command -v ghostty >/dev/null 2>&1; then
    echo "ghostty: already installed"
    exit 0
fi

# Re-run as root. Copied bootstrap.sh only obtains sudo if a TTY is
# available; with --yes and no TTY this runs as the calling user.
if [ "$(id -u)" -ne 0 ]; then
    exec sudo "$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
fi

# rpm-ostree can already be busy (system upgrade, another install, or a stuck
# transaction). Refusing to layer Ghostty should not kill the whole bootstrap:
# the rest of the machine is already set up at that point. Warn and defer.
if ! command -v rpm-ostree >/dev/null 2>&1; then
    echo "ghostty: rpm-ostree not found — layer it manually later:" >&2
    echo "         sudo rpm-ostree install -y --allow-inactive ghostty" >&2
    exit 0
fi

. /etc/os-release

cat > "/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:scottames:ghostty.repo" <<REPOEOF
[copr:copr.fedorainfracloud.org:scottames:ghostty]
name=Copr repo for ghostty owned by scottames
baseurl=https://download.copr.fedorainfracloud.org/results/scottames/ghostty/fedora-${VERSION_ID}/x86_64/
type=rpm-md
skip_if_unavailable=False
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/scottames/ghostty/pubkey.gpg
enabled=1
enabled_metadata=1
REPOEOF

if ! rpm-ostree refresh-md; then
    echo "ghostty: failed to refresh DNF metadata — fix the RPM error above, then rerun this script"
    exit 0
fi

install_out="$(rpm-ostree install -y --allow-inactive ghostty 2>&1)" || {
    echo "ghostty: layering deferred (rpm-ostree not ready):"
    echo "$install_out" | sed 's/^/  /'
    echo
    if echo "$install_out" | grep -qi "transaction in progress"; then
        echo "  A transaction is already running. Either wait for it, or cancel it:"
        echo "    rpm-ostree cancel && sudo systemctl reboot (if KILL is needed)"
        echo "  Then rerun: sudo bash scripts/install-ghostty-bazzite.sh"
    else
        echo "  If this is a COPR/copr issue, see the error above. Retry with:"
        echo "    sudo bash scripts/install-ghostty-bazzite.sh"
    fi
    exit 0
}

echo "ghostty: layered ok — reboot to activate the deployment (systemctl reboot)"
