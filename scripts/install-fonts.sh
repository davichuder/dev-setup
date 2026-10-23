#!/usr/bin/env bash
# Install the 6 core Nerd Fonts into ~/.local/share/fonts. Idempotent:
# a marker file short-circuits the download on later bootstrap runs.
set -euo pipefail

DEST="$HOME/.local/share/fonts"
MARKER="$DEST/.nerd-fonts-done"

# Headless machines (no fontconfig) don't need fonts
if ! command -v fc-cache >/dev/null 2>&1; then
  echo "fonts: fc-cache not found, skipping font install"
  exit 0
fi
[ -f "$MARKER" ] && { echo "fonts: already installed"; exit 0; }

# --- extraction: tar preferred; install it if missing; unzip as fallback ----
if ! command -v tar >/dev/null 2>&1; then
  echo "fonts: tar not found — trying to install it"
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -q && sudo apt-get install -y -q tar
  elif command -v rpm-ostree >/dev/null 2>&1; then
    sudo rpm-ostree install tar
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y tar
  fi
fi

if command -v tar >/dev/null 2>&1; then
  ASSET_EXT="tar.xz"
  EXTRACT_MODE="tar"
elif command -v unzip >/dev/null 2>&1; then
  echo "fonts: falling back to unzip (tar is unavailable until the next reboot on rpm-ostree systems)"
  ASSET_EXT="zip"
  EXTRACT_MODE="unzip"
else
  echo "ERROR: neither tar nor unzip is available, and tar could not be installed." >&2
  echo "       Install tar (Ubuntu/WSL: sudo apt install -y tar) and run bootstrap again." >&2
  exit 1
fi

mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for FONT in JetBrainsMono FiraCode Iosevka Hack Meslo CascadiaCode; do
  echo "fonts: downloading $FONT"
  curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${FONT}.${ASSET_EXT}" \
    -o "$TMP/${FONT}.${ASSET_EXT}"
  mkdir -p "$DEST/$FONT"
  case "$EXTRACT_MODE" in
    tar)
      tar -xJf "$TMP/${FONT}.${ASSET_EXT}" -C "$DEST/$FONT"
      ;;
    unzip)
      unzip -q -o "$TMP/${FONT}.${ASSET_EXT}" -d "$DEST/$FONT"
      ;;
  esac
done

fc-cache -f >/dev/null 2>&1
touch "$MARKER"
echo "fonts: installed 6 Nerd Fonts into $DEST"
