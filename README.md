# dev-setup

Portable developer-machine bootstrap for **WSL2 Ubuntu, Ubuntu desktop, Ubuntu Server and Bazzite**, on one primitive: [`mise bootstrap`](https://mise.jdx.dev/bootstrap.html). One command per machine, everything declarative, everything versioned here.

## Usage

One line — clone, enter, run (interactive; it auto-detects your machine and asks y/n about dotfiles):

```sh
git clone https://github.com/davichuder/dev-setup.git ~/dev-setup && cd ~/dev-setup && ./bootstrap.sh
```

The other two modes only change what their flags do; everything else is identical:

```sh
./bootstrap.sh --no-dotfiles   # fully automatic: zero prompts (ideal for a clean WSL distro);
                               # also leaves your login shell untouched
./bootstrap.sh wsl --dotfiles  # force module + apply dotfiles; flags go in any order:
                               # desktop | wsl | bazzite | server, --dotfiles, --no-dotfiles,
                               # --zsh, --no-zsh (make brew zsh the login shell)
./bootstrap.sh --doctor        # verify only: PASS/FAIL per check, changes nothing (exit 1 on FAIL)
./bootstrap.sh --prune         # delete tool versions no config selects anymore (see below)
./bootstrap.sh --uninstall     # remove what this repo installed (asks y/n; see below)
```

Interactive runs ask two questions: **dotfiles now? (y/n)** — "y" opens a URL prompt, Enter keeps your default repo — and **make zsh the default login shell? (y/n)**; answering n keeps your current shell, and non-interactive runs never change it.

**Idempotent by design** — run it 10 times in a row and the final state is the same: mise skips packages and tools that already match, dotfile edits add only missing lines, and the font task short-circuits on its marker. The one variation over long periods is the "latest" version policy picking up upstream releases. Use `--doctor` to confirm the state any time; with `--zsh` it also verifies that the login shell really is zsh (and nothing else changed shell-related).

The module is auto-detected, in this order:

1. `/proc/version` mentions Microsoft → **wsl**
2. a Fedora Atomic image with `ujust` (`ujust` in PATH or "bazzite" in os-release) → **bazzite**
3. Ubuntu with a graphical session (`$XDG_SESSION_TYPE` x11/wayland, or `graphical.target` active) → **desktop**
4. Ubuntu headless (tty/ssh session) → **server**

Anything else prints a warning and cancels without changing anything.

After it finishes: open a new shell (mise activation block is written into your shell startup files). Tools then resolve in any directory too — the script writes the base `[tools]` table into a global mise fragment (`~/.config/mise/conf.d/dev-setup-tools.toml`), because the project config alone only applies inside the checkout.

## Removing it later (prune and uninstall)

`mise bootstrap` is additive: it installs and edits, it never deletes. Two commands cover cleanup.

**`./bootstrap.sh --prune`** — removes stale tool versions only. When a tool leaves `[tools]` or a `"latest"` range moves on, the old install stays on disk; `mise prune` deletes exactly the versions no config selects anymore (`mise ls --prunable` shows the list first) and keeps everything a config still uses. Nothing else on the machine is touched.

**`./bootstrap.sh --uninstall`** — reverses the whole setup, in a safe order, asking for confirmation first:

1. the `[dotfiles]` lines and PATH exports (`mise dot unapply --force`)
2. the `mise:activate` blocks in `~/.zshrc` / `~/.zprofile`
3. the login shell (asks before reverting to `/bin/bash`, and only when the current one is zsh — this runs *before* `brew:zsh` is removed, so no login is left pointing at a deleted shell)
4. the global tools fragment (`~/.config/mise/conf.d/dev-setup-tools.toml`)
5. every tool declared in `[tools]`
6. every `brew:` formula declared in `[bootstrap.packages]` (`mise` itself is kept, it is the manager)
7. the core Nerd Fonts + Symbols sidecar and both markers

It then lists what it deliberately leaves alone, with the exact command for each: apt packages (`sudo apt-get remove …`), Bazzite's rpm-ostree Ghostty layer, your `~/dotfiles` checkout, and mise plus its data directory. Every step tolerates "already gone", so running it twice is safe. `--uninstall --yes` skips the confirmation, and in that mode the login shell is left unchanged (the revert command is printed instead), matching how non-interactive installs never change it.

## Requirements

- **Supported targets only**: WSL2 Ubuntu, Ubuntu desktop, Ubuntu Server 24.04+, or any Bazzite image. **Native Windows is not supported** — bootstrap.sh refuses there; the Windows path is WSL2 (`wsl --install -d Ubuntu`, then run the script inside the distro).
- **`curl` and `git`** on the machine (needed to fetch this repo and run the script; mise installs itself and everything else).
- **`sudo` rights**: apt sources/packages, rpm-ostree layering and system services run with sudo when a change needs root.
- **apt ≥ 2.4** (Ubuntu 22.04+/Debian 12+): mise writes inline-signed apt repository keys.
- **A few GB free disk**: runtimes (node, python, go, rust, java) plus ~40 CLIs land in `~/.local/share/mise` and the brew prefix.
- **Fonts**: installs the 6 core Nerd Fonts *plus* **Symbols Nerd Font** as a fallback.
  Headless servers skip the font task automatically when `fc-cache` is missing.
- **WSL2 + Docker**: install Docker Desktop on Windows and enable *Settings > Resources > WSL Integration > this distro* — the script reminds you at the end only when the Docker engine is not reachable from the distro.
- **Network**: required on first run (bottles, runtimes, apt sources, fonts).

## Installation flow

```mermaid
flowchart TD
    A["git clone https://github.com/davichuder/dev-setup"] --> B["./bootstrap.sh"]
    B --> C{"native Windows?<br>(MINGW / MSYS / CYGWIN)"}
    C -- "yes" --> X["refuse:<br>wsl --install -d Ubuntu<br>nothing changed"]
    C -- "no" --> D{"module passed as arg?"}
    D -- "yes" --> F
    D -- "no" --> E{"auto-detect"}
    E -- "WSL2 marker in /proc/version" --> F["module = wsl"]
    E -- "ujust present / bazzite" --> F
    E -- "Ubuntu + graphical session" --> F
    E -- "Ubuntu headless" --> F
    E -- "anything else" --> X2["warn + cancel,<br>nothing changed"]
    F --> G["mise trust ."] --> H["mise -E <module> bootstrap<br>brew bottles · apt sources/packages<br>system services · all tools · fonts"]
    H --> I{"apply dotfiles? (y/n)"}
    I -- "y" --> J["mise -E <module>,dotfiles bootstrap<br>--only dotfiles,tools --prompt-vars<br>URL prompt: Enter = your default repo,<br>or paste another URL"]
    I -- "n" --> K["skipped — run later with<br>./bootstrap.sh <module> --dotfiles"]
    J --> L
    K --> L{"WSL2 and docker engine unreachable?"}
    L -- "yes" --> M["remind:<br>Docker Desktop → Resources → WSL Integration"]
    L -- "no" --> N["open a new shell — done"]
    M --> N
```

## How it is divised

| File | Contains |
|---|---|
| `mise.toml` | Base for every machine: 5 runtimes + 40 CLIs (`[tools]`), Homebrew formulae (`brew:` — mise installs bottles, no Homebrew needed; includes llama.cpp and the zsh autosuggestions/syntax-highlighting plugins), bash and zsh shell activation, idempotent font task |
| `mise.desktop.toml` | Ubuntu desktop: Ghostty (PPA), Docker Engine, Tailscale + services |
| `mise.wsl.toml` | WSL2: Ghostty (PPA, WSLg); Docker comes from Docker Desktop on Windows; time zone set to America/Argentina/Buenos Aires (UTC-3) |
| `mise.bazzite.toml` | Bazzite: Ghostty via COPR + `rpm-ostree`; Docker/SSH already in the image |
| `mise.server.toml` | Ubuntu Server: Docker Engine, Tailscale, `openssh-server` + services |
| `mise.dotfiles.toml` | Optional module: clones `github.com/davichuder/dotfiles` into `~/dotfiles` and links files; only applied when you accept |
| `bootstrap.sh` | Installs mise if missing, picks the module, runs `mise bootstrap`, optional dotfiles step, WSL2 Docker Desktop reminder |
| `scripts/install-fonts.sh` | 6 core Nerd Fonts + Symbols sidecar → `~/.local/share/fonts` (idempotent) |
| `scripts/install-ghostty-bazzite.sh` | COPR + `rpm-ostree` layering for Ghostty (idempotent) |

## Dotfiles — example structure and sync

### How the dotfiles flow works inside mise

```mermaid
flowchart TD
    subgraph CFG["mise.dotfiles.toml (machine module, OFF by default)"]
        V["[vars.dotfiles_url]<br>default = davichuder/dotfiles.git<br>prompt = URL question"]
        R["[bootstrap.repos]<br>'~/dotfiles' = url = '{{vars.dotfiles_url}}'<br>ref = main"]
        E["[dotfiles]<br>~/.zshrc = ~/dotfiles/zsh/zshrc<br>~/.config/ghostty/config = ~/dotfiles/ghostty/config<br>(one entry per file)"]
        V -. "the url renders this var" .-> R
        R -. "the checkout supplies the link sources" .-> E
    end
    B["mise -E <module>,dotfiles bootstrap --only dotfiles,tools --prompt-vars"]
    B --> P{"dotfiles_url already answered?"}
    P -- "no" --> Q["URL prompt: Enter keeps the<br>default, paste another URL"]
    Q --> S["answer saved in mise state dir<br>(vars.toml), outside every config,<br>never committed"]
    P -- "yes (saved answer or default)" --> C1
    S --> C1["part: repos<br>git clone --branch main <url> ~/dotfiles"]
    C1 --> C2["part: dotfiles<br>link each entry into $HOME,<br>state that already matches is skipped"]
    C2 --> C3["re-sync any machine later:<br>mise -E <module>,dotfiles bootstrap --update<br>(fast-forward the checkout, re-apply the rest)"]
```

The dotfiles repository (`davichuder/dotfiles` by default; any URL at the prompt) is just a Git checkout: `mise` clones it into `~/dotfiles` and links individual files with `[dotfiles]` entries. Example layout — one directory per app, plain files, nothing else needed:

```text
dotfiles/
├── zsh/
│   └── zshrc                # → ~/.zshrc
├── ghostty/
│   └── config               # → ~/.config/ghostty/config
├── gitignore-global         # → ~/.config/git/ignore
└── powerlevel10k/
    └── p10k.zsh             # → ~/.p10k.zsh
```

Each arrow is one entry in `mise.dotfiles.toml`:

```toml
[dotfiles]
"~/.zshrc" = "~/dotfiles/zsh/zshrc"
"~/.config/ghostty/config" = "~/dotfiles/ghostty/config"
```

Keep it in sync with the upstream repo (after bootstrap, on any machine):

```sh
mise -E <module>,dotfiles bootstrap --update   # pulls declared repos + re-applies state (idempotent)
mise -E wsl,dotfiles bootstrap --update        # example: this is what it looks like on WSL2
```

Use a different repository than the default (yours instead of `davichuder/dotfiles`, or a fork):

```sh
mise vars prompt dotfiles_url      # re-ask: Enter keeps the default, paste another URL
mise vars unset dotfiles_url       # forget the saved answer, asked again next time
mise -E <module>,dotfiles bootstrap --update
```

Saved answers live in mise's state directory, outside every config file — never committed here.

## Key facts baked into the design

- **mise, not brew, runs the installs.** Formulae land in the standard Homebrew prefix (`/home/linuxbrew/.linuxbrew`) with Homebrew-compatible receipts — Homebrew stays compatible without being required to drive the setup.
- **Ghostty** is not in Homebrew for Linux: it comes from the `mkasberg/ghostty-ubuntu` PPA (Ubuntu/WSL2) or the `scottames` COPR layered with `rpm-ostree` (Bazzite). Verified docs: ghostty.org/docs/install/binary.
- **Per-OS divergence is a module, not an if/else**: undeclared managers are skipped on other platforms, so base + module never fight.
- **Idempotent everywhere**: `mise bootstrap` skips already-matching state; fonts and random scripts guard themselves; safe to re-run.
- **Secrets never in git**: if a template ever needs one, use `[bootstrap.secrets]` (env-backed), never literal values.
- **Multiplexed work is herdr, not tmux/zellij**: one workspace per directory, tabs for editor / agent / terminal and remote SSH — no second multiplexer is installed; the build toolchain (gcc, pkg-config, openssl headers) comes from the apt packages rather than adding a separate toolchain image.

## Neovim / LazyVim (optional, already ready)

No separate toolchain to install later — the setup lands the [LazyVim requirements](https://www.lazyvim.org/) up front:

- `neovim >= 0.11.2` (with LuaJIT) and `lazygit` from Homebrew, `git >= 2.19` and `curl` from the apt/brew steps
- `ripgrep`, `fd`, `fzf` as tools `[tools]`
- `tree-sitter` CLI as a tool, plus a C compiler (`build-essential` on Ubuntu/Bazzite: `gcc`/`pkgconf` via rpm-ostree or toolbx) for `nvim-treesitter` parser builds
- the 6 core Nerd Fonts + Symbols sidecar installed by `scripts/install-fonts.sh` (v3+) and Ghostty as the terminal on Ubuntu (documented on the Bazzite module as a manual step with `rpm-ostree`)

You only need to drop your LazyVim config (`~/.config/nvim`) on top of it; `:LazyHealth` should then pass without installing anything extra.

## Everyday commands

```sh
mise bootstrap --yes                 # bring this machine to the declared state
mise -E bazzite bootstrap --dry-run  # preview what would change
mise bootstrap packages upgrade      # upgrade brew/apt formulae to latest
mise bootstrap --update              # refresh metadata + declared repos
mise bootstrap unapply dotfiles      # remove what the dotfiles module deployed
mise run lint                        # syntax (bash -n) + shellcheck on every shell file
./bootstrap.sh --prune               # delete tool versions no config selects anymore
./bootstrap.sh --uninstall           # remove the whole setup (asks y/n)
```

## First run notes

- WSL2 + Docker Desktop: enable **Settings > Resources > WSL Integration** for the distro (bootstrap.sh prints the reminder).
- Bazzite: after the Ghostty layer, one reboot applies it.
- `mise bootstrap` runs with `sudo` only where a change requires root (apt sources/packages, rpm-ostree); it never runs privileged work without a declared change.
- WSL2 clock: the setup runs a `final` hook setting the distro timezone to `America/Argentina/Buenos_Aires` (UTC-3). WSL2 inherits a UTC clock from the Windows host, so this only converts display; if you want the host to follow it instead, set Windows' own timezone too. On a native Ubuntu install the zone stays untouched.
- Icons missing in the terminal: fonts are installed — `fc-list | grep -i nerd` shows them — but the **terminal font-family must be a Nerd Font** (`MesloLGS Nerd Font`, `JetBrainsMono Nerd Font`, `CascadiaCode Nerd Font`). Ghostty: `font-family = MesloLGS Nerd Font`; WezTerm: `config.font = wezterm.font("MesloLGS Nerd Font")`; Alacritty: `font.family = "MesloLGSNerdFont"`. The extra `Symbols Nerd Font` helps editors/terminals that fall back to a symbols-only font.
