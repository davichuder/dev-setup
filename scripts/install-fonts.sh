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
[ -f "$MARKER" ] && [ -f "$DEST/.nerd-symbols-done" ] && { echo "fonts: already installed"; exit 0; }

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

touch "$MARKER"

# Symbols Nerd Font is a small font carrying only the Nerd-Font glyph set.
# Terminals that fall back on any primary font (Ghostty, Kitty) render only
# the icons if the active font lacks the code points and a fallback exists,
# so install it as a sidecar to avoid "missing icons" with mixed fonts.
SYMBOLS_EXTRA="$DEST/.nerd-symbols-done"
if [ ! -f "$SYMBOLS_EXTRA" ]; then
  echo "fonts: downloading Symbols Nerd Font"
  curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.${ASSET_EXT}" \
    -o "$TMP/Symbols.${ASSET_EXT}"
  mkdir -p "$DEST/SymbolsNerdFont"
  case "$ASSET_EXT" in
    zip) unzip -q -o "$TMP/Symbols.zip" -d "$DEST/SymbolsNerdFont" ;;
    tar.xz) tar -xJf "$TMP/Symbols.${ASSET_EXT}" -C "$DEST/SymbolsNerdFont" ;;
  esac
  touch "$SYMBOLS_EXTRA"
fi

command -v fc-cache >/dev/null 2>&1 && fc-cache -f >/dev/null 2>&1
echo "fonts: installed 6 core + Symbols Nerd Font into $DEST"
