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

mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for FONT in JetBrainsMono FiraCode Iosevka Hack Meslo CascadiaCode; do
  echo "fonts: downloading $FONT"
  curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${FONT}.zip" \
    -o "$TMP/${FONT}.zip"
  unzip -q -o "$TMP/${FONT}.zip" -d "$DEST/$FONT"
done

fc-cache -f >/dev/null 2>&1
touch "$MARKER"
echo "fonts: installed 6 Nerd Fonts into $DEST"
