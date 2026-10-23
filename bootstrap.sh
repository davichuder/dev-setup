#!/usr/bin/env bash
# One-shot machine bootstrap. Run from a checkout of this repository:
#   ./bootstrap.sh          — auto-detects machine type, asks about dotfiles
#   ./bootstrap.sh bazzite  — force a module: desktop | wsl | bazzite | server
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# Trust the project's mise configs (required once per machine)
mise trust . >/dev/null 2>&1 || true

# --- 1) Native Windows must not proceed: use WSL2 ---------------------------
uname_s="$(uname -s 2>/dev/null || true)"
case "$uname_s" in
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    echo "ERROR: native Windows detected ($uname_s). This bootstrap does not run there." >&2
    echo "       The supported Windows path is WSL2:" >&2
    echo "         powershell -c \"wsl --install -d Ubuntu\" then run this script inside the distro" >&2
    exit 1
    ;;
esac

# --- 2) module selection ----------------------------------------------------
MODULE="${1:-}"

# Auto-detect which machine module applies. Prints ONLY the module name to
# stdout; fails (returns 1) on any unsupported OS.
detect_module() {
  # WSL2 first: a WSL distro also reports Ubuntu, but /proc/version has Microsoft
  if grep -qi microsoft /proc/version 2>/dev/null; then
    echo wsl
    return 0
  fi
  # Bazzite (Fedora Atomic image that ships ujust)
  if command -v ujust >/dev/null 2>&1 || grep -qi bazzite /etc/os-release; then
    echo bazzite
    return 0
  fi
  if [ "${ID:-}" = ubuntu ] || [[ "${PRETTY_NAME:-}" == *Ubuntu* ]]; then
    # A graphical session (this shell's XDG type, or graphical.target active)
    # means desktop; anything else (tty, ssh, headless) means server.
    case "${XDG_SESSION_TYPE:-}" in
      x11|wayland) echo desktop; return 0 ;;
    esac
    if [ "$(systemctl is-active graphical.target 2>/dev/null)" = active ]; then
      echo desktop
    else
      echo server
    fi
    return 0
  fi
  return 1
}

if [ -n "$MODULE" ]; then
  case "$MODULE" in
    desktop|wsl|bazzite|server) ;;
    *) echo "Unknown module: $MODULE"; exit 1 ;;
  esac
  echo "==> module forced from argument: $MODULE"
else
  if ! MODULE="$(detect_module)"; then
    echo "ERROR: could not detect a supported system." >&2
    echo "       Supported: WSL2 Ubuntu (wsl), Ubuntu desktop, Ubuntu Server (server), Bazzite (bazzite)." >&2
    echo "       Native Windows is NOT supported here: run this inside WSL2." >&2
    echo "       Nothing was changed." >&2
    exit 1
  fi
  echo "==> detected module: $MODULE"
fi

# --- 3) main bootstrap (packages + tools + fonts, no dotfiles) ---------------
echo "==> mise bootstrap (module: $MODULE, dotfiles skipped)"
mise -E "$MODULE" bootstrap --yes

# --- 4) dotfiles: only if you say yes ---------------------------------------
APPLY_DOTFILES="${2:-}"
if [ "$APPLY_DOTFILES" = "--dotfiles" ]; then
  ANSWER="y"
elif [ -t 0 ]; then
  read -r -p "Apply dotfiles? (y/n): " ANSWER
else
  ANSWER="n"
fi
case "${ANSWER,,}" in
  y|yes)
    echo "==> applying dotfiles"
    echo "    (the URL prompt shows your default repo: press Enter for it, or paste another URL)"
    mise -E "$MODULE,dotfiles" bootstrap --only dotfiles,tools --prompt-vars --yes
    ;;
  *)
    echo "dotfiles skipped (run later: ./bootstrap.sh $MODULE --dotfiles)"
    ;;
esac

# --- 5) WSL2 reminders -------------------------------------------------------
if grep -qi "microsoft" /proc/version 2>/dev/null; then
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    echo
    echo "WSL2: Docker engine is not reachable from this distro."
    echo "      Docker Desktop: Settings > Resources > WSL Integration > enable this distro"
  fi
fi

echo
echo "Done. Open a new shell for mise activation to take effect."
