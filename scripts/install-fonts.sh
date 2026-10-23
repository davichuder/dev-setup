#!/usr/bin/env bash
# Install the 6 core Nerd Fonts into ~/.local/share/fonts. Idempotent:
# a marker file short-circuits the download on later bootstrap runs.
#
# Extraction dependency: unzip is guaranteed by the apt packages step on
# every Ubuntu module; Bazzite ships tar in its image (no rpm-ostree
# layering, no reboot). This script never installs packages itself.
set -euo pipefail

DEST="$HOME/.local/share/fonts"
MARKER="$DEST/.nerd-fonts-done"

# Headless machines (no fontconfig) don't need fonts
if ! command -v fc-cache >/dev/null 2>&1; then
  echo "fonts: fc-cache not found, skipping font install"
  exit 0
fi
[ -f "$MARKER" ] && { echo "fonts: already installed"; exit 0; }

# Ubuntu modules get unzip via apt before any task runs; Bazzite ships tar.
# tar.xz has the same assets, so either extractor works - pick what exists.
if command -v unzip >/dev/null 2>&1; then
  ASSET_EXT="zip"
elif command -v tar >/dev/null 2>&1; then
  ASSET_EXT="tar.xz"
else
  echo "ERROR: fonts need unzip (installed by the apt packages step) or tar." >&2
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
  case "$ASSET_EXT" in
    zip)
      unzip -q -o "$TMP/${FONT}.zip" -d "$DEST/$FONT"
      ;;
    tar.xz)
      tar -xJf "$TMP/${FONT}.tar.xz" -C "$DEST/$FONT"
      ;;
  esac
done

fc-cache -f >/dev/null 2>&1
touch "$MARKER"
echo "fonts: installed 6 Nerd Fonts into $DEST"
