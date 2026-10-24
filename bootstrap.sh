#!/usr/bin/env bash
# One-shot machine bootstrap. Run from a checkout of this repository:
#   ./bootstrap.sh              auto-detect machine type, ask the two questions
#   ./bootstrap.sh <module>     force a module: desktop | wsl | bazzite | server
#   --dotfiles / --no-dotfiles  force the dotfiles step on or off (any order)
#   --zsh / --no-zsh            force the "zsh as login shell" answer
#   --doctor                    verify the installation; changes nothing
#   --prune                     delete tool versions no config uses anymore
#   --uninstall                 remove what this repository installed (asks y/n)
#   --yes                       skip the --uninstall confirmation prompt
#
# Fully automatic example:
#   ./bootstrap.sh --no-dotfiles
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# --- 0) argument parsing -----------------------------------------------------
FORCE_MODULE=""
DOT_MODE=""    # "", "yes", "no"
ZSH_MODE=""    # "", "yes", "no"
DOCTOR=0
PRUNE=0
UNINSTALL=0
YES=0
for arg in "$@"; do
  case "$arg" in
    desktop|wsl|bazzite|server) FORCE_MODULE="$arg" ;;
    --dotfiles) DOT_MODE="yes" ;;
    --no-dotfiles) DOT_MODE="no" ;;
    --zsh) ZSH_MODE="yes" ;;
    --no-zsh) ZSH_MODE="no" ;;
    --doctor) DOCTOR=1 ;;
    --prune) PRUNE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --yes) YES=1 ;;
    *) echo "Unknown argument: $arg (use a module name, --dotfiles/--no-dotfiles, --zsh/--no-zsh, --doctor, --prune, --uninstall [--yes])" >&2 && exit 1 ;;
  esac
done

if [ "$DOCTOR" = 1 ] && { [ "$UNINSTALL" = 1 ] || [ "$PRUNE" = 1 ]; }; then
  echo "ERROR: --doctor is read-only; it cannot be combined with --uninstall or --prune." >&2
  exit 1
fi
if [ "$UNINSTALL" = 1 ] && [ "$PRUNE" = 1 ]; then
  echo "ERROR: pick one: --uninstall removes everything, --prune only deletes unused tool versions." >&2
  exit 1
fi

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

# --- prune: delete tool versions that no config selects anymore -------------
# `mise bootstrap` never removes anything: when a tool leaves [tools] (or a
# "latest" range moves on), its old install stays on disk. `mise prune` is the
# explicit cleanup, and it keeps anything a loaded config still selects.
if [ "$PRUNE" = 1 ]; then
  command -v mise >/dev/null 2>&1 || { echo "ERROR: mise is not installed; nothing to prune." >&2; exit 1; }
  echo "==> tool versions no config uses anymore:"
  mise ls --prunable 2>/dev/null | sed 's/^/    /' || true
  echo "==> pruning"
  mise -q prune --tools --yes
  mise reshim >/dev/null 2>&1 || true
  echo "==> done (tool versions selected by a config are kept)"
  exit 0
fi

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

MODULE="$FORCE_MODULE"
if [ -n "$MODULE" ]; then
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

# --- uninstall: remove what this repository installed ------------------------
# mise bootstrap has no general "undo": `mise bootstrap unapply <ENV>` only
# works for named environments (mise.<env>.toml), and the base config is not
# one. So the removal is explicit here, in reverse order of installation:
# dotfile lines -> shell activation -> login shell -> global fragment -> tools
# -> brew formulae -> fonts. The login shell goes before brew:zsh disappears,
# or the next login would point at a deleted binary. System packages, the
# ~/dotfiles checkout and mise itself are reported, never touched. Every step
# tolerates "already gone", so running it twice ends in the same state.
remove_managed_block() {
  local file="$1" tag="$2" tmp
  [ -f "$file" ] || return 0
  grep -q "^# >>> $tag >>>" "$file" || return 0
  tmp="$(mktemp)"
  awk -v tag="$tag" '
    index($0, "# >>> " tag " >>>") == 1 { inside = 1; next }
    inside && index($0, "# <<< " tag " <<<") == 1 { inside = 0; next }
    !inside { print }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
  echo "    removed shell activation block from $file"
}

run_uninstall() {
  local module="$1" answer tool formula brew_prefix brew_bin out
  local tools apt_pkgs cur_shell removed_fonts=0

  echo "==> uninstall (module: $module)"
  if [ "$YES" != 1 ]; then
    if [ ! -t 0 ]; then
      echo "ERROR: --uninstall asks for confirmation; re-run with --yes for a non-interactive removal." >&2
      exit 1
    fi
    read -r -p "Remove the tools, brew formulae, shell edits, fonts and global fragment this repo installed? (y/n): " answer
    case "${answer,,}" in
      y|yes) ;;
      *) echo "cancelled; nothing was changed."; exit 0 ;;
    esac
  fi

  # 1) PATH and shell-hook lines declared in [dotfiles]
  if command -v mise >/dev/null 2>&1; then
    echo "==> dotfile lines"
    mise dot unapply --force --yes 2>&1 | sed 's/^/    /' || echo "    WARN: could not unapply dotfile lines"
  else
    echo "==> dotfile lines skipped (mise not found)"
  fi

  # 2) mise activation blocks written by mise bootstrap
  echo "==> shell activation"
  remove_managed_block "$HOME/.zshrc" "mise:activate"
  remove_managed_block "$HOME/.zprofile" "mise:activate"

  # 3) login shell FIRST, before brew:zsh is removed: a login shell pointing
  # at a deleted zsh binary breaks the next login. Only touched when asked.
  echo "==> login shell"
  cur_shell="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7 || true)"
  case "$cur_shell" in
    */zsh)
      if [ -t 0 ] && [ "$YES" != 1 ]; then
        read -r -p "Change your login shell back to /bin/bash? (y/n): " answer
      else
        answer="n"
      fi
      case "${answer,,}" in
        y|yes)
          if chsh -s /bin/bash; then
            echo "    login shell set to /bin/bash (applies to new logins)"
          else
            echo "    could not change the login shell; run: chsh -s /bin/bash"
          fi
          ;;
        *) echo "    left as $cur_shell (revert later: chsh -s /bin/bash)" ;;
      esac
      ;;
    "") echo "    could not read the login shell" ;;
    *) echo "    left as $cur_shell (not zsh)" ;;
  esac

  # 4) global tools fragment generated by this script
  echo "==> global tools fragment"
  if [ -f "$HOME/.config/mise/conf.d/dev-setup-tools.toml" ]; then
    rm -f "$HOME/.config/mise/conf.d/dev-setup-tools.toml"
    rmdir "$HOME/.config/mise/conf.d" 2>/dev/null || true
    echo "    removed ~/.config/mise/conf.d/dev-setup-tools.toml"
  fi

  # 5) tool versions declared in [tools]
  echo "==> mise tools"
  if command -v mise >/dev/null 2>&1; then
    tools="$(awk '/^\[tools\]/{f=1; next} f && /^\[/{exit} f && /^[[:space:]]*[^#[:space:]].*=/{print}' mise.toml |
      sed -E 's/^[[:space:]]*"([^"]+)"[[:space:]]*=.*/\1/; s/^[[:space:]]*([A-Za-z0-9_.:-]+)[[:space:]]*=.*/\1/')"
    while IFS= read -r tool; do
      [ -n "$tool" ] || continue
      out="$(mise uninstall --all "$tool" 2>&1)" || true
      case "$out" in
        *"no versions found"*) ;;   # not installed: nothing to report
        *) echo "    removed $tool" ;;
      esac
    done <<< "$tools"
    mise reshim >/dev/null 2>&1 || true
  else
    echo "    skipped (mise not found)"
  fi

  # 6) Homebrew formulae declared in [bootstrap.packages]
  echo "==> brew formulae"
  brew_prefix="${HOMEBREW_PREFIX:-/home/linuxbrew/.linuxbrew}"
  if [ -x "$brew_prefix/bin/brew" ]; then
    brew_bin="$brew_prefix/bin/brew"
  else
    brew_bin="$(command -v brew 2>/dev/null || true)"
  fi
  if [ -n "$brew_bin" ]; then
    case "$cur_shell" in
      *linuxbrew*)
        echo "    WARN: your login shell is $cur_shell and the next step deletes it."
        echo "          Fix it first: chsh -s /bin/bash"
        ;;
    esac
    for formula in $(grep -hoE '"brew:[^"]+"' mise.toml "mise.$module.toml" 2>/dev/null |
      sed -E 's/"brew:(.*)"/\1/' | sort -u); do
      [ "$formula" = mise ] && continue
      if "$brew_bin" uninstall --formula --ignore-dependencies "$formula" >/dev/null 2>&1; then
        echo "    removed brew:$formula"
      fi
    done
  else
    echo "    skipped: no brew binary found in $brew_prefix/bin"
  fi

  # 7) Nerd Fonts and their marker
  echo "==> fonts"
  for font in JetBrainsMono FiraCode Iosevka Hack Meslo CascadiaCode; do
    if [ -d "$HOME/.local/share/fonts/$font" ]; then
      rm -rf "$HOME/.local/share/fonts/$font"
      removed_fonts=$((removed_fonts + 1))
    fi
  done
  rm -rf "$HOME/.local/share/fonts/.nerd-fonts-done"
  command -v fc-cache >/dev/null 2>&1 && fc-cache -f >/dev/null 2>&1 || true
  echo "    removed $removed_fonts of the 6 Nerd Font directories"

  # 8) what stays, and the exact command to remove it
  echo
  echo "==> left in place (outside what this repo owns):"
  apt_pkgs="$(grep -hoE '"apt:[^"]+"' mise.toml "mise.$module.toml" 2>/dev/null |
    sed -E 's/"apt:(.*)"/\1/' | sort -u | paste -sd' ' -)"
  if [ -n "$apt_pkgs" ]; then
    echo "    apt packages: $apt_pkgs"
    echo "      sudo apt-get remove -y -- $apt_pkgs"
  fi
  if grep -q "bootstrap.apt.sources" "mise.$module.toml" 2>/dev/null; then
    echo "    apt sources added by the module:"
    echo "      sudo rm -f /etc/apt/sources.list.d/mise-*.sources"
  fi
  case "$module" in
    desktop|server)
      echo "    services enabled by the module:"
      echo "      sudo systemctl disable --now docker tailscaled"
      ;;
  esac
  if [ "$module" = bazzite ]; then
    echo "    ghostty is layered with rpm-ostree:"
    echo "      sudo rpm-ostree uninstall ghostty && reboot"
  fi
  echo "    ~/dotfiles checkout (your files): delete it yourself if you no longer need it"
  echo "    mise itself and its data:"
  echo "      rm -f \"\$HOME/.local/bin/mise\""
  echo "      rm -rf \"\$HOME/.local/share/mise\" \"\$HOME/.local/state/mise\" \"\$HOME/.cache/mise\""
  echo
  echo "Done. Open a new shell; this checkout can be deleted."
}

if [ "$UNINSTALL" = 1 ]; then
  run_uninstall "$MODULE"
  exit 0
fi

# --- 2) login shell: change it only when you say yes -------------------------
# mise.zshlogin.toml holds [bootstrap.user] login_shell; adding the module to
# the env list is what applies it. Non-interactive runs never change the shell.
case "$ZSH_MODE" in
  "")  [ -t 0 ] && { read -r -p "Make zsh the default login shell? (y/n): " ZSH_ANSWER || ZSH_ANSWER=n; ZSH_MODE="${ZSH_ANSWER,,}"; } || ZSH_MODE="n" ;;
esac

case "$ZSH_MODE" in
  y|yes) SHELL_ENV="$MODULE,zshlogin"; echo "==> zsh will become your login shell" ;;
  *)     SHELL_ENV="$MODULE"; echo "==> keeping your current login shell" ;;
esac

# --- doctor: read-only verification (runs INSTEAD of the bootstrap) ----------
# exit code 0 = everything listed is applied; 1 = something differs.
run_doctor() {
  local env_for_checks="$1"
  local fails=0 cur_shell want got
  local shell_is_zsh=0
  echo "==> doctor (read-only; nothing is changed)"

  cur_shell="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7 || true)"
  case "$cur_shell" in */zsh) shell_is_zsh=1 ;; esac

  if command -v mise >/dev/null 2>&1; then
    echo "PASS mise is installed"
  else
    echo "FAIL mise is not installed (run ./bootstrap.sh without --doctor first)"
    fails=$((fails+1))
  fi

  want="$(awk '/^\[tools\]/{f=1} f{print} f && $0 !~ /^\[tools\]/ && NR>1 && /^\[/{exit}' mise.toml)"
  got="$(cat "$HOME/.config/mise/conf.d/dev-setup-tools.toml" 2>/dev/null || true)"
  if [ -n "$got" ] && [ "$want" = "$got" ]; then
    echo "PASS global tools fragment is fresh"
  else
    echo "FAIL global tools fragment missing or stale (run ./bootstrap.sh once)"
    fails=$((fails+1))
  fi

  if [ "$ZSH_MODE" = "yes" ]; then
    if [ "$shell_is_zsh" = 1 ]; then
      echo "PASS login shell is zsh: $cur_shell"
    else
      echo "FAIL login shell should be zsh but is: ${cur_shell:-unknown}"
      fails=$((fails+1))
    fi
  else
    echo "INFO login shell: ${cur_shell:-unknown} (managed only when you answer yes or pass --zsh)"
  fi

  if command -v mise >/dev/null 2>&1; then
    if mise -E "$env_for_checks" bootstrap status --missing >/dev/null 2>&1; then
      echo "PASS every configured part matches the machine (module: $env_for_checks)"
    else
      echo "FAIL parts that differ from the config (module: $env_for_checks):"
      mise -E "$env_for_checks" bootstrap status --missing 2>&1 | \
        grep -E "missing|drift" | sed 's/^/      /' || true
      fails=$((fails+1))
    fi
  fi

  if grep -qi "microsoft" /proc/version 2>/dev/null; then
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
      echo "PASS WSL2: docker engine reachable"
    else
      echo "WARN WSL2: docker engine unreachable (reminder only; enable it in Docker Desktop > Settings > Resources > WSL Integration)"
    fi
  fi

  echo "doctor: $fails failing check(s)"
  return "$fails"
}

doctor_rc=0
if [ "$DOCTOR" = 1 ]; then
  run_doctor "$SHELL_ENV" || doctor_rc=$?
  exit "$doctor_rc"
fi

# --- 3) prerequisites (skipped by --doctor: these change the machine) --------
command -v git >/dev/null 2>&1 || {
  echo "ERROR: git is missing." >&2
  echo "       Install it first (Ubuntu/WSL: sudo apt install -y git, Bazzite: host image provides it)." >&2
  exit 1
}

if ! command -v mise >/dev/null 2>&1; then
  if ! command -v curl >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update && sudo apt-get install -y curl
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y curl
    else
      echo "ERROR: mise and curl are both missing and no package manager was found for curl." >&2
      echo "       Install mise manually: https://mise.jdx.dev/installing-mise.html" >&2
      exit 1
    fi
  fi
  echo "mise not found — installing..."
  curl -fsSL https://mise.jdx.dev/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

# Trust the project's mise configs (required once per machine)
mise trust . >/dev/null 2>&1 || true

# --- expose the tool set globally --------------------------------------------
# Shell shims (written below by mise bootstrap) resolve tool versions from the
# GLOBAL config chain: the project mise.toml alone applies only inside this
# directory, so outside it every shim would fail with "No version is set for
# shim". ONLY the [tools] table goes to the global config (generated from the
# repo's mise.toml, so a single source of truth): bootstrap parts, tasks and
# dotfiles stay project-scoped, and two config roots never fight over paths.
mkdir -p "$HOME/.config/mise/conf.d"
awk '/^\[tools\]/{f=1} f{print} f && $0 !~ /^\[tools\]/ && NR>1 && /^\[/{exit}' \
  mise.toml > "$HOME/.config/mise/conf.d/dev-setup-tools.toml"

# --- 4) main bootstrap (packages + tools + fonts, no dotfiles) ---------------
echo "==> mise bootstrap (module: $SHELL_ENV, dotfiles skipped)"
mise -E "$SHELL_ENV" bootstrap --yes
mise reshim

# --- 5) dotfiles: only if you say yes ---------------------------------------
# In non-interactive runs the default answer is "no"; with --dotfiles the
# declared default repo URL is used without prompting (no --prompt-vars).
case "$DOT_MODE" in
  no)
    ANSWER="n"
    ;;
  yes)
    ANSWER="y"
    ;;
  "")
    if [ -t 0 ]; then
      read -r -p "Apply dotfiles? (y/n): " ANSWER
    else
      ANSWER="n"
    fi
    ;;
esac

case "${ANSWER,,}" in
  y|yes)
    echo "==> applying dotfiles"
    PROMPT_VARS=()
    if [ -t 0 ]; then
      PROMPT_VARS=(--prompt-vars)
      echo "    (the URL prompt shows your default repo: press Enter for it, or paste another URL)"
    else
      echo "    (non-interactive: using the declared default repo URL; interactive run re-asks)"
    fi
    mise -E "$MODULE,dotfiles" bootstrap --only dotfiles,tools "${PROMPT_VARS[@]+"${PROMPT_VARS[@]}"}" --yes
    ;;
  *)
    echo "dotfiles skipped (run later: ./bootstrap.sh $MODULE --dotfiles)"
    ;;
esac

# --- 6) WSL2 reminders -------------------------------------------------------
if grep -qi "microsoft" /proc/version 2>/dev/null; then
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    echo
    echo "WSL2: Docker engine is not reachable from this distro."
    echo "      Docker Desktop: Settings > Resources > WSL Integration > enable this distro"
  fi
fi

echo
echo "Done. Open a new shell for mise activation to take effect."
