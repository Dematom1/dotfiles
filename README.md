# Dotfiles

macOS development environment managed with Determinate Nix, nix-darwin, Home
Manager, an existing Homebrew installation, and `just` recipes for agent tools
and skills. The same flake also builds a headless Linux AI sandbox server - see
[Linux sandbox server](#linux-sandbox-server).

## Supported machines

The flake owns the machine-to-account mapping:

| Profile | Platform | Account | Home directory | Host module | Flake output |
|---|---|---|---|---|---|
| `personal` | aarch64-darwin | `laszlohoranszky` | `/Users/laszlohoranszky` | `hosts/personal.nix` | `darwinConfigurations.personal` |
| `work` | aarch64-darwin | `laszlo` | `/Users/laszlo` | `hosts/work.nix` | `darwinConfigurations.work` |
| `sandbox` | x86_64-linux | `captain` | `/home/captain` | `hosts/sandbox.nix` | `nixosConfigurations.sandbox` |

`flake.nix` is the username source of truth. It passes the selected username to
nix-darwin, which sets `system.primaryUser` and `users.users`, and Home Manager
is attached to that same user. `home.nix` derives its username, home directory,
and `~/Code/dotfiles` links from that configuration.

`rebuild.sh` defaults to `personal` for backward compatibility. Before running
`darwin-rebuild`, it evaluates the selected profile's primary user and compares
it with `id -un`. An unknown profile, an empty profile marker, or a profile for
a different account fails without activating anything. In particular, running
without the work marker as `laszlo` cannot silently target the personal home.

## Included configuration

| Tool | Purpose |
|---|---|
| **nvim** | Neovim with LSP, DAP, and Treesitter |
| **tmux** | Terminal multiplexer |
| **zsh** | Home Manager shell, Powerlevel10k, and live `zsh/init.zsh` extras |
| **ghostty** / **wezterm** | Terminal emulators |
| **atuin** | Shell history search |
| **direnv** | Per-project environments |
| **git** | Git configuration with delta |
| **Automic Vault** | Local macOS Keychain and command-approval boundary |
| **yazi** | Terminal file manager |
| **bat** | Syntax-highlighted output |
| **aerospace** | macOS window manager |
| **sketchybar** | macOS status bar |

## Prerequisites

- An Apple Silicon Mac with the matching account name from the table above
- [Determinate Nix](https://determinate.systems/)
- Homebrew already installed and available to nix-darwin
- Git, or the Xcode Command Line Tools needed to clone this repository
- A 1Password account for the private values referenced by `zsh/secrets.tpl`

`nix-homebrew` is imported, but intentionally not enabled. nix-darwin manages
the existing Homebrew installation through its Homebrew activation. Activation
uses cleanup mode `zap`, so applications or formulae not declared in the shared
or selected host configuration can be removed.

## Fresh-machine bootstrap

```bash
# 1. Install Determinate Nix (provides `nix`). Skip if `nix --version` already
#    works. Open a new shell afterwards so nix is on PATH.
curl -fsSL https://install.determinate.systems/nix | sh -s -- install

# 2. Clone to the canonical location.
git clone https://github.com/Dematom1/dotfiles.git "$HOME/Code/dotfiles"
cd "$HOME/Code/dotfiles"

# 3. Pick this machine's profile and activate the config (needs sudo). `just`
#    isn't installed yet, so run it once through nix. Work Macs pass `work`;
#    personal Macs can omit the argument (personal is the default).
nix run nixpkgs#just -- setup work

# 4. Authenticate 1Password, render ~/.secrets, and install agent tooling/skills.
op signin
just bootstrap
```

`just setup` installs Nix if it is missing, then rebuilds; `just rebuild` skips
the install and just activates. Both take the profile as an argument -
`just setup work` or `just rebuild personal` - which writes
`~/.config/dotfiles-profile` before rebuilding. Omit it to keep the current
marker (personal is the default). `rebuild.sh` refuses to activate a profile
whose primary user doesn't match the current macOS account, so the wrong
profile fails fast. Supported values are only `personal` and `work`.

A clone outside `~/Code/dotfiles` is also supported: `rebuild.sh` creates the
canonical `~/Code/dotfiles` symlink to the checkout. It refuses to replace an
existing non-symlink at that path.

### What each layer owns

1. **`flake.nix`** selects the host profile and its account name, then composes
   the per-platform modules. `mkDarwinHost` builds the Macs (shared Darwin
   module + host module + Home Manager + Homebrew); `mkNixosHost` builds the
   Linux sandbox (host module + Home Manager); `mkLinuxHome` exposes standalone
   Home Manager for non-NixOS Linux. All three share one Home Manager wiring
   (`hmModule`).
2. **`configuration.nix`** owns macOS system defaults, the selected macOS user,
   shared Homebrew packages, and shared system configuration. Darwin only.
3. **`hosts/personal.nix` and `hosts/work.nix`** append machine-specific
   Homebrew packages. **`hosts/sandbox.nix`** is the standalone NixOS module for
   the Linux sandbox (SSH, `captain`, Docker + gVisor, firewall). Profile-specific
   Nix packages are selected in `home.nix`.
4. **`home.nix`** owns user packages, zsh structure and aliases, and selected
   out-of-store links into this repository. It is shared across all platforms;
   macOS-only modules are gated behind `pkgs.stdenv.isDarwin`. The shared
   `kubernetes-axi` CLI comes from the pinned Nix package in
   `packages/kubernetes-axi.nix`, not the npm-global bootstrap.
5. **`just bootstrap`** renders secrets, installs the FirstMate/Pi/Herdr and AXI
   tool stack, installs Ponytail for Pi and for Claude Code where available,
   refreshes skills, and wires the generated skill directories.

Home Manager uses `mkOutOfStoreSymlink`, so edits to linked files apply without
copying them into the Nix store or rebuilding. On first activation, an existing
file in the way is renamed with a `.bak` suffix.

Linking is intentionally selective. Home Manager links the listed application
configurations, top-level shell files, shared agent instructions, and the
Claude skill source. It links only `karabiner.json`, leaving Karabiner assets and
backups tool-owned. It also leaves `~/.claude/settings.json` tool-owned because
AXI setup hooks and Claude's plugin manager mutate it. Ponytail is persisted by
the idempotent `just _setup-ponytail` recipe through Pi's package manager and
Claude's user-scoped marketplace/plugin commands instead of Home Manager.

OpenCode skill wiring is generated by `just update-skills`. It removes only
links that point to this repository's `.agents/skills` tree, preserves
tool-managed links and existing destinations, and creates only missing shared
skill links. Generated and authenticated skill content remains gitignored.

## Linux sandbox server

The flake builds a headless Linux AI sandbox server that `captain` SSHes into.
It is provider-agnostic: no cloud-vendor assumptions, so it applies to any
provisioned x86_64-linux box (bare metal, a droplet, an EC2/GCE instance, a
local VM). The single `nixpkgs` pin carries the full Linux/NixOS package set, so
no second input tracks alongside the Darwin one.

Several Linux outputs, so it works on NixOS and on any other distro:

| Output | Use when | Apply / build |
|---|---|---|
| `nixosConfigurations.sandbox` | The box is (or will be) NixOS | `nixos-rebuild switch --flake .#sandbox` |
| `homeConfigurations."captain@x86_64-linux"` | Any non-NixOS Linux with Nix + Home Manager (also an `aarch64-linux` variant) | `home-manager switch --flake '.#captain@x86_64-linux'` |
| `homeConfigurations."root@x86_64-linux"` | A box only SSH-reachable as root, with no `captain` account (also an `aarch64-linux` variant) | `home-manager switch --flake '.#root@x86_64-linux'` |

The `root@` outputs apply the identical environment to `/root` instead of
creating a system user; `mkLinuxHome` in `flake.nix` takes the username and
home directory as overridable arguments (defaulting to `captain`).

`hosts/sandbox.nix` is the NixOS host module:

- **SSH** via `services.openssh` with key-based auth only - password and
  keyboard-interactive auth disabled and root login refused. Add `captain`'s
  public key to `users.users.captain.openssh.authorizedKeys.keys` before
  applying, or manage keys out-of-band.
- **`captain`** is a normal `wheel` user with password-less sudo (login is
  key-only) and `zsh` as the login shell. Home Manager provides the portable
  shell/CLI environment - see the platform gating note below.
- **Container runtime: Docker + gVisor.** Isolation for AI-authored workloads
  comes from a gVisor-sandboxed plane rather than the container runtime, so a
  standard rootful Docker daemon is used. gVisor's `runsc` is registered as an
  available runtime but not the default (runc stays default); the sandbox plane
  selects it per workload with `docker run --runtime=runsc`. `captain` is in the
  `docker` group to reach the daemon socket without sudo.
- **Boot + filesystem** are `lib.mkDefault` placeholders (grub on `/dev/sda`, an
  ext4 root) plus the `qemu-guest` profile for broad virtualized-provider
  drivers. On a real host, import the machine's generated
  `hardware-configuration.nix` (`nixos-generate-config`); its definitions win
  over the defaults. The placeholders exist only so the toplevel builds without
  a machine attached.
- **Firewall** allows only inbound SSH.

Home Manager (`home.nix`) is shared with the Macs. macOS-only modules - the
`aerospace` window manager, `wezterm`, the `chrome-devtools` browser MCP,
desktop fonts, and the GUI-app config links (ghostty, sketchybar, karabiner) -
are gated behind `pkgs.stdenv.isDarwin`, so the sandbox gets only the portable
tools (zsh, git, atuin, direnv, bat, neovim, kubernetes CLIs, language
toolchains, and the shared agent instructions). The shared `zsh/init.zsh`
likewise gates its macOS-only blocks (the 1Password agent socket and the
SketchyBar cwd hook) behind `$OSTYPE`, so it loads cleanly on Linux. Like the
Macs, the sandbox links live files from a `~/Code/dotfiles` checkout via
`mkOutOfStoreSymlink`, so clone the repo there.

`kubernetes-axi` is built from the exact upstream commit pinned by `flake.nix`
and `flake.lock`. It is in the shared Home Manager package list, so the
applicable local Mac profiles and every Linux sandbox profile get the same
executable on `PATH`. The package build runs upstream's unit suite. The flake
also exposes `packages.<system>.kubernetes-axi` and a bounded
`checks.<system>.kubernetes-axi-doctor` smoke test. That smoke test removes
`kubectl` from `PATH` before running `kubernetes-axi doctor`, which proves the
installed executable starts without contacting or mutating a cluster.

### Validation

`nix flake check` passes and every Linux output evaluates to a derivation, but
this repo is maintained on Apple Silicon, which cannot *realize* Linux
derivations without a remote Linux builder. To actually build on the Mac,
configure one and run:

```bash
nix build '.#packages.x86_64-linux.kubernetes-axi'
nix build '.#packages.x86_64-linux.default'
nix build '.#checks.x86_64-linux.kubernetes-axi-doctor'
nix build '.#packages.aarch64-linux.kubernetes-axi'
nix build '.#packages.aarch64-linux.default'
nix build '.#checks.aarch64-linux.kubernetes-axi-doctor'
nix build '.#nixosConfigurations.sandbox.config.system.build.toplevel'
nix build '.#homeConfigurations."captain@x86_64-linux".activationPackage'
nix build '.#homeConfigurations."root@x86_64-linux".activationPackage'
nix build '.#homeConfigurations."captain@aarch64-linux".activationPackage'
nix build '.#homeConfigurations."root@aarch64-linux".activationPackage'
```

Without a Linux builder, these `nix build` commands fail fast with a platform
mismatch; the real build happens on the Linux host during `nixos-rebuild` /
`home-manager switch`.

## Credentials and authenticated skills

`zsh/secrets.tpl` contains only 1Password references. Real values are rendered
to `~/.secrets`, which is outside the repository and sourced by the Home
Manager zsh setup:

```bash
op signin
just refresh-secrets
```

The ui.sh installer is deliberately interactive. During `just bootstrap`,
`just update-skills`, or `just update-ui-skill`, enter its token only in the
installer's masked prompt. The recipes remove any inherited `UIDOTSH_TOKEN` and
do not pass a token through argv. Do not put the token in a command, environment
file, repository file, chat, logs, or agent pane. The setup does not inspect the
clipboard.

### Automic Vault GitHub CLI pilot

Automic Vault is declared as the official
`automic-vault/isotopes/automic-vault` Homebrew cask in `configuration.nix`, so
both Mac profiles install it during a rebuild. Home Manager also places the
vendor's `/usr/local/bin` CLI location on `PATH`. The third-party cask follows
this repository's existing rolling Homebrew convention and is not pinned by
`flake.lock`; its cask metadata pins each release artifact by SHA-256. At pilot
start the captain observed `av 3.3.0`.

The [official CLI manual](https://www.automicvault.com/docs/) and
[source repository](https://github.com/automic-vault/automic-vault) are the
authoritative product references.

This is a bounded, manual pilot for `GH_TOKEN`. It does not harden or replace
the Nix-provided `gh`, migrate credentials, or remove any existing GitHub CLI
authentication.

1. Apply the selected Mac profile with `just rebuild personal` or
   `just rebuild work`.
2. Open the app once so its approval service is running and its signed CLI stub
   is installed, then verify the command is the expected stub:

   ```bash
   open /Applications/Automic\ Vault.app
   command -v av
   av --version
   ```

   `command -v av` should print `/usr/local/bin/av`.
3. Audit all reported exposure without changing it:

   ```bash
   av scan --show-all
   ```

   Review the report. Do not treat exit status `0` as a clean audit, and do not
   apply unrelated hardeners as part of this pilot.
4. Keep the current GitHub CLI authentication intact. In a private interactive
   terminal, save the token through Automic Vault's hidden `/dev/tty` prompt:

   ```bash
   av save GH_TOKEN
   ```

   Never pipe, echo, log, or pass the token on the command line. This step needs
   the captain's direct entry and approval and must not be automated.
5. With the app open, request approval and test the injected path:

   ```bash
   av inject +GH_TOKEN gh auth status
   ```

   An existing `GH_TOKEN` environment value wins by default. If `av` reports
   that conflict, prove Keychain injection in a temporary clean environment
   without changing the durable fallback:

   ```bash
   env -u GH_TOKEN av inject +GH_TOKEN gh auth status
   ```

6. Inspect the current GitHub CLI integration:

   ```bash
   av doctor gh
   ```

   The pilot baseline reports that `/opt/homebrew/opt/gh-cli/bin/gh` is missing
   and the Nix `gh` at `/etc/profiles/per-user/$USER/bin/gh` is not the signed
   Automic Vault isotope. That result is expected for this injection-only
   pilot. Do not run `av harden gh` within this pilot, because it would replace
   the current command path and migrate authentication.
7. Only after the injected command succeeds may the captain separately decide
   whether to remove an old plaintext or exported credential. No rebuild or
   repository automation removes it.

Rollback is to stop using `av inject` and continue with the preserved GitHub CLI
authentication. To uninstall the application declaratively, remove its cask
entry from `configuration.nix` and rebuild the selected profile. That does not
delete the `GH_TOKEN` Keychain item. If desired, the captain can remove that
item interactively in Automic Vault after confirming the fallback works.

The security boundary is local to this Mac. Keychain storage plus per-target
and launcher authorization reduce ambient secret exposure to local agents, but
an approved target controls a secret after receiving it, including in process
memory and its environment. This does not contain same-user malware or a root
compromise, and it does not replace CI, Kubernetes, production, or centralized
secret management.

## Agent wrappers

Home Manager persists the Headroom wrappers as zsh aliases, so rebuilds retain
them:

- `claude` runs `headroom wrap claude --` with Claude Code's standard 200K
  context window.
- `claude1m` runs `headroom wrap claude --1m --`, providing the opt-in 1M
  context window for tasks that truly need it.
- `codex` runs Headroom on local port `8787` with `--no-proxy`,
  `--no-context-tool`, `--no-mcp`, `--no-tokensave`, and `--no-serena`.

The Codex wrapper therefore keeps its current no-proxy and no-TokenSave posture
while preserving the existing Headroom invocation and port.

## AI runtime hygiene

The runtime uses a selective diagnostics policy:

- Claude Code operational usage metrics and redacted error diagnostics remain at
  their enabled vendor defaults.
- Determinate Nix crash and installer diagnostics remain enabled.
- `chrome-devtools-axi` remains the browser launcher. Home Manager points its
  supported `CHROME_DEVTOOLS_AXI_MCP_PATH` override at a Nix-managed copy of
  `scripts/chrome-devtools-mcp.js` in the profile closure, independent of the
  dotfiles checkout location. That JavaScript entrypoint passes
  `--no-usage-statistics` to the MCP server. The vendor opt-out environment
  variable is also exported for direct invocations.
- Clawdbot is intentionally retired. It is not a package, bootstrap dependency,
  or launch service in this repository and must not be added back without an
  explicit decision.

`just check-regressions` verifies the browser opt-out for both host profiles,
keeps Claude and Determinate Nix diagnostics opt-outs absent, and rejects
Clawdbot across tracked configuration, script, and launch-service surfaces.

## Updating and checks

```bash
cd "$HOME/Code/dotfiles"
git pull
just rebuild          # system, Homebrew, Home Manager, and profile packages
just update           # skills, the FirstMate agent stack, and Ponytail
just check-regressions
```

`just check-regressions` evaluates both flake profiles and verifies their
Darwin and Home Manager homes, including Terraform in each Home Manager package
set and the activated operator path when safe local evidence is available. It
also checks profile validation, selective OpenCode links, masked ui.sh
installation, SketchyBar state-file safety (on macOS; on Linux it instead
asserts the hook stays undefined), AXI hook failures, and shell regressions.

## Key bindings

### Neovim

See [nvim/CHEATSHEET.md](nvim/CHEATSHEET.md) for the authoritative reference.

### Tmux

- `Ctrl-Space` - Prefix
- `prefix + |` / `prefix + -` - Split vertical / horizontal
- `prefix + r` - Reload config
- `Alt+1-5` - Switch windows
- `prefix + C-j` - Session switcher

### Shell

- `Ctrl-R` - Atuin history search
- `Ctrl-T` - FZF repository selector and tmux
- `z <dir>` - Zoxide smart cd
- `y` - Yazi file manager

## Repository map

```text
dotfiles/
├── flake.nix            # host/profile/account mapping and module composition
├── configuration.nix    # shared nix-darwin system and Homebrew configuration
├── home.nix             # Home Manager packages, links, zsh (macOS-gated where needed)
├── hosts/               # personal.nix, work.nix (Mac deltas), sandbox.nix (Linux NixOS)
├── packages/            # custom Nix package definitions
├── rebuild.sh           # validated profile selection and darwin-rebuild
├── justfile             # bootstrap, update, skills, and checks
├── tests/               # account-selection and shell regressions
├── .agents/             # shared skill source and provenance
├── nvim/ zsh/ ghostty/ atuin/ direnv/ git/ yazi/ bat/
├── aerospace/ sketchybar/ karabiner/
├── .wezterm.lua
└── .tmux.conf
```
