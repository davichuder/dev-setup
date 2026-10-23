#!/usr/bin/env bash
# WSL2 imports a UTC clock from the Windows host, so a guest with the default
# UTC zone makes every timestamp look three hours ahead to a Buenos Aires user.
# Generic version: it reads the Windows timezone of the host and applies a
# matching IANA zone inside the guest; only if there is no mapping does it fall
# back to a fixed-offset Etc/GMT zone that keeps the clock accurate right now.
# It never hardcodes a city and leaves the guest untouched when interop fails.
set -euo pipefail

# Read the Windows timezone id via interop (works on every WSL2 build tested).
WIN_TZ="$(/mnt/c/Windows/System32/tzutil.exe /g 2>/dev/null || true)"
WIN_TZ="${WIN_TZ%$'\r'}"
WIN_TZ="${WIN_TZ## }"
WIN_TZ="${WIN_TZ%% }"

# Map the Windows time zone id to an IANA zone. Extend this list as needed.
declare -A WIN_TO_IANA=(
  ["UTC"]="Etc/UTC"
  ["UTC-02"]="Etc/GMT+2"
  ["UTC-03"]="Etc/GMT+3"
  ["UTC-04"]="Etc/GMT+4"
  ["UTC-05"]="Etc/GMT+5"
  ["UTC-06"]="Etc/GMT+6"
  ["UTC-07"]="Etc/GMT+7"
  ["UTC-08"]="Etc/GMT+8"
  ["UTC-09"]="Etc/GMT+9"
  ["UTC-10"]="Etc/GMT+10"
  ["UTC-11"]="Etc/GMT+11"
  ["UTC-12"]="Etc/GMT+12"
  ["Argentina Standard Time"]="America/Argentina/Buenos_Aires"
  ["Bahia Standard Time"]="America/Bahia"
  ["Central Brazilian Standard Time"]="America/Cuiaba"
  ["E. South America Standard Time"]="America/Sao_Paulo"
  ["Pacific SA Standard Time"]="America/Santiago"
  ["Atlantic Standard Time"]="America/Halifax"
  ["Eastern Standard Time"]="America/New_York"
  ["Central Standard Time"]="America/Chicago"
  ["Mountain Standard Time"]="America/Denver"
  ["Pacific Standard Time"]="America/Los_Angeles"
  ["Alaskan Standard Time"]="America/Anchorage"
  ["Hawaiian Standard Time"]="Pacific/Honolulu"
  ["Newfoundland Standard Time"]="America/St_Johns"
  ["W. Europe Standard Time"]="Europe/Berlin"
  ["Central European Standard Time"]="Europe/Paris"
  ["Romance Standard Time"]="Europe/Paris"
  ["FLE Standard Time"]="Europe/Helsinki"
  ["GTB Standard Time"]="Europe/Istanbul"
  ["Russian Standard Time"]="Europe/Moscow"
  ["China Standard Time"]="Asia/Shanghai"
  ["India Standard Time"]="Asia/Kolkata"
  ["Singapore Standard Time"]="Asia/Singapore"
  ["Japan Standard Time"]="Asia/Tokyo"
  ["Korea Standard Time"]="Asia/Seoul"
  ["Nepal Standard Time"]="Asia/Kathmandu"
  ["New Zealand Standard Time"]="Pacific/Auckland"
  ["AUS Eastern Standard Time"]="Australia/Sydney"
  ["W. Australia Standard Time"]="Australia/Perth"
  ["Egypt Standard Time"]="Africa/Cairo"
  ["South Africa Standard Time"]="Africa/Johannesburg"
  ["GMT Standard Time"]="Europe/London"
)

TARGET_TZ="${WIN_TO_IANA[$WIN_TZ]:-}"

# If there is no direct mapping, derive a fixed-offset fallback so at least
# the displayed wall clock is correct right now. Puts IANA Etc/GMT±N of the
# Windows host's current offset.
if [ -z "$TARGET_TZ" ] && [ -n "$WIN_TZ" ]; then
    WIN_OFFSET_MINUTES="$(powershell.exe -NoProfile -Command '[System.TimeZoneInfo]::Local.GetUtcOffset([DateTime]::UtcNow).TotalMinutes' 2>/dev/null | tr -d '\r' | head -1)"
    if [[ "$WIN_OFFSET_MINUTES" =~ ^-?[0-9]+$ ]]; then
        QTY=$(( ${WIN_OFFSET_MINUTES#-} / 60 ))
        if (( WIN_OFFSET_MINUTES <= 0 )); then
            TARGET_TZ="Etc/GMT+$QTY"
        else
            TARGET_TZ="Etc/GMT-$QTY"
        fi
    fi
fi

if [ -z "$WIN_TZ" ]; then
    echo "timezone: Windows interop unavailable, leaving /etc/localtime untouched"
    exit 0
fi

if [ -z "$TARGET_TZ" ]; then
    echo "timezone: warned: Windows zone \"$WIN_TZ\" not mapped and no fallback available; leaving current zone"
    exit 0
fi

CURRENT_TZ="$(cat /etc/timezone 2>/dev/null || true)"
if [ "$CURRENT_TZ" = "$TARGET_TZ" ] && [ -L /etc/localtime ]; then
    echo "timezone: already set to $TARGET_TZ"
    exit 0
fi

echo "timezone: $WIN_TZ (Windows) -> $TARGET_TZ"
sudo rm -f /etc/localtime
sudo ln -s "/usr/share/zoneinfo/$TARGET_TZ" /etc/localtime
printf '%s\n' "$TARGET_TZ" | sudo tee /etc/timezone >/dev/null

if command -v timedatectl >/dev/null 2>&1; then
    sudo timedatectl set-timezone "$TARGET_TZ" 2>/dev/null || true
fi
