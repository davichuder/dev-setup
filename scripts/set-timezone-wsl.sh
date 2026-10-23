#!/usr/bin/env bash
# WSL2 imports a UTC clock from the Windows host, so without this the guest
# shows the time in UTC and every file looks -3 hours to a Buenos Aires user.
# Idempotent: nothing happens if the zone is already set correctly.
set -euo pipefail

TARGET_TZ="America/Argentina/Buenos_Aires"
CURRENT_TZ="$(cat /etc/timezone 2>/dev/null || true)"

if [ "$CURRENT_TZ" = "$TARGET_TZ" ] && [ -L /etc/localtime ] && [ "$(readlink -f /usr/share/zoneinfo/Argentina/Buenos_Aires 2>/dev/null)" = "$(readlink -f /etc/localtime 2>/dev/null)" ]; then
    echo "timezone: already set to $TARGET_TZ"
    exit 0
fi

echo "timezone: setting $TARGET_TZ"
if command -v timedatectl >/dev/null 2>&1; then
    sudo timedatectl set-timezone "$TARGET_TZ" 2>/dev/null || true
fi
# Fallback that does not depend on systemd being PID 1 (WSL2 default):
sudo rm -f /etc/localtime
sudo ln -s "/usr/share/zoneinfo/$TARGET_TZ" /etc/localtime
printf '%s\n' "$TARGET_TZ" | sudo tee /etc/timezone >/dev/null
