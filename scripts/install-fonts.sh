#!/usr/bin/env bash
# Install the 6 core Nerd Fonts (+ the Symbols Nerd Font as sidecar) into
# ~/.local/share/fonts. Idempotent: base and symbols markers are independent.
#
# - Unzip is guaranteed by the apt packages on Ubuntu modules; Bazzite ships
#   tar. Tar.xz has the same assets, so either extractor works — pick what exists.
set -euo pipefail

DEST="$HOME/.local/share/fonts"
MARKER="$DEST/.nerd-fonts-done"          # the six core fonts
SYMBOLS_MARKER="$DEST/.nerd-symbols-done" # only the glyphs font (for fallbacks)

# Headless machines: no fontconfig → no need.
if ! command -v fc-cache >/dev/null 2>&1; then
    echo "fonts: fc-cache not found, skipping font install"
    exit 0
fi

# Pick the extractor once.
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

# Base six. Only download if an old run has not already produced the marker.
if [ ! -f "$MARKER" ]; then
    for FONT in JetBrainsMono FiraCode Iosevka Hack Meslo CascadiaCode; do
        echo "fonts: downloading $FONT"
        curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${FONT}.${ASSET_EXT}" \
            -o "$TMP/${FONT}.${ASSET_EXT}"
        mkdir -p "$DEST/$FONT"
        case "$ASSET_EXT" in
            zip)     unzip -q -o "$TMP/${FONT}.zip"     -d "$DEST/$FONT" ;;
            tar.xz)  tar -xJf           "$TMP/${FONT}.tar.xz" -C "$DEST/$FONT" ;;
        esac
    done
    touch "$MARKER"
fi

# Symbols Nerd Font: tiny font of just the glyph set. Terminals that fall back
# on any primary only show the icons if a font carrying these code points exists.
if [ ! -f "$SYMBOLS_MARKER" ]; then
    echo "fonts: downloading Symbols Nerd Font"
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.${ASSET_EXT}" \
        -o "$TMP/Symbols.${ASSET_EXT}"
    mkdir -p "$DEST/SymbolsNerdFont"
    case "$ASSET_EXT" in
        zip)     unzip -q -o "$TMP/Symbols.zip"   -d "$DEST/SymbolsNerdFont" ;;
        tar.xz)  tar -xJf           "$TMP/Symbols.${ASSET_EXT}" -C "$DEST/SymbolsNerdFont" ;;
    esac
    touch "$SYMBOLS_MARKER"
fi

if [ -f "$MARKER" ] && [ -f "$SYMBOLS_MARKER" ]; then
    echo "fonts: installed 6 core + Symbols Nerd Font into $DEST"
fi
command -v fc-cache >/dev/null 2>&1 && fc-cache -f >/dev/null 2>&1
