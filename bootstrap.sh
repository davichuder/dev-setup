#!/usr/bin/env bash
# One-shot machine bootstrap. Run from a checkout of this repository:
#   ./bootstrap.sh              auto-detect machine type, ask the two questions
#   ./bootstrap.sh <module>     force a module: desktop | wsl | bazzite | server
#   --dotfiles / --no-dotfiles  force the dotfiles step on or off (any order)
#   --zsh / --no-zsh            force the "zsh as login shell" answer
#   --doctor                    verify the installation; changes nothing
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
for arg in "$@"; do
  case "$arg" in
    desktop|wsl|bazzite|server) FORCE_MODULE="$arg" ;;
    --dotfiles) DOT_MODE="yes" ;;
    --no-dotfiles) DOT_MODE="no" ;;
    --zsh) ZSH_MODE="yes" ;;
    --no-zsh) ZSH_MODE="no" ;;
    --doctor) DOCTOR=1 ;;
    *) echo "Unknown argument: $arg (use a module name, --dotfiles/--no-dotfiles, --zsh/--no-zsh, --doctor)" >&2 && exit 1 ;;
  esac
done

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
  local fails=0 row cur_shell want got
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
