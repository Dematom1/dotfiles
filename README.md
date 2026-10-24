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

### Apply and verify gcloud

Nix owns the gcloud binary on macOS. The rebuild does not manage or modify
`~/.config/gcloud`, so existing credentials, authentication state, and
configuration remain owned by gcloud. Apply the selected macOS profile with:

```bash
./rebuild.sh
```

After the rebuild, verify the binary owner, SDK version, and existing auth state
with these read-only commands:

```bash
type -a gcloud
gcloud --version
gcloud auth list
```

### Tailscale CLI

On macOS, Home Manager exposes `tailscale` on `PATH` through
`~/.local/bin/tailscale`, which forwards arguments to
`/Applications/Tailscale.app/Contents/MacOS/Tailscale`. This keeps the CLI
version aligned with the installed app instead of using the nixpkgs CLI.
The app must already be installed; its installation method is unchanged.
Apply the wrapper with `just rebuild`, then use `type -a tailscale` to check
command resolution. Non-Darwin profiles continue to use the nixpkgs package.

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
| **Pi Launcher** | Credentialed signed Pi route for supervised Firstmate sessions |
| **M87** | Local-first GitHub review queue with pinned Nix packaging |
| **Agent skills / Pi extensions** | Declared cross-agent skills and pinned Pi-native FFF search extension |
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

On macOS, `home.nix` adds `/opt/homebrew/bin` to the Home Manager session path
and to interactive and non-interactive zsh shells, including terminals launched
from Rex. The ordering policy in [zsh/path-order.zsh](zsh/path-order.zsh) still
puts protected directories, including protected Nix profiles and `/usr/bin`,
ahead of user-writable Homebrew directories. Apply with `just rebuild` (which
runs `darwin-rebuild switch`), then open a new shell.

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
   Homebrew packages; `hosts/personal.nix` also enables
   [Local signoff](#local-signoff). **`hosts/sandbox.nix`** is the standalone NixOS module for
   the Linux sandbox (SSH, `captain`, Docker + gVisor, firewall). Profile-specific
   Nix packages are selected in `home.nix`.
4. **`home.nix`** owns user packages, zsh structure and aliases, and selected
   out-of-store links into this repository. It is shared across all platforms;
   macOS-only modules are gated behind `pkgs.stdenv.isDarwin`. Treehouse, every
   AXI tool, M87, backpass, acpx and the pi-fff extension come from the pinned
   Nix packages described under [Automated tool updates](#automated-tool-updates).
   Its `agentTooling` activation reconciles agent plugins, MCP servers, hooks,
   Pi packages, and skills to [agent-tooling.json](agent-tooling.json) (see
   [Declarative agent tooling](#declarative-agent-tooling)).
5. **`just bootstrap`** renders secrets, installs the self-updating
   FirstMate/Pi/Herdr/No Mistakes/Claude Code stack, registers AXI session
   hooks, installs Ponytail for Pi and for Claude Code where available,
   refreshes skills, and wires the generated skill directories.

The AXI hook policy lives in [justfile](justfile) (`axi-tools`,
`axi-tools-no-hooks`, and the work-only list); `just setup-firstmate` and
`just update-firstmate` remove superseded npm-global copies of the
Nix-installed tools. `just rebuild` registers the session hooks of every
installed hook-enabled tool and removes any hook a no-hook tool left behind
(see [Declarative agent tooling](#declarative-agent-tooling)). Claude Code has
one install, the native self-updating one in `~/.local/bin`; it is deliberately
not a Homebrew cask.
On macOS, attended `just rebuild` activation installs it when missing, skips
installation during dry runs, and fails clearly if installation fails.
`just setup-firstmate` uses the same installer.

Home Manager uses `mkOutOfStoreSymlink`, so edits to linked files apply without
copying them into the Nix store or rebuilding. On first activation, an existing
file in the way is renamed with a `.bak` suffix.

Linking is intentionally selective. Home Manager links the listed application
configurations, top-level shell files, shared agent instructions, and the
Claude skill source. It links only `karabiner.json`, leaving Karabiner assets and
backups tool-owned. It also leaves `~/.claude/settings.json` unlinked because
AXI setup hooks and Claude's plugin manager mutate it. The reconciler directly
edits its hooks; activation also invokes installers that manage their own
settings, including plugin enablement.

Shared-skill content is generated by `just update-skills` for the maintained
agent surfaces documented in [.agents/SKILLS.md](.agents/SKILLS.md). The skills
CLI uses copy mode so Claude's linked skill root cannot produce self-referential
leaf links. OpenCode wiring removes only links that point to this repository's
`.agents/skills` tree, preserves tool-managed links and existing destinations,
and creates only missing links. Generated skill content and Claude/Pi
registries remain gitignored.

## Nix-managed agent tools

### Automated tool updates

Each npm CLI is one directory, `packages/npm/<name>`, whose `package.json`
pins one dependency and whose `package-lock.json` pins its whole tree.
`packages/npm-tool.nix` builds it with `importNpmLock`, which fetches every
tarball by the lockfile's own integrity hash, so no `npmDepsHash` exists to
drift. Adding a directory adds the package (`flake.nix` reads the directory).
Treehouse is a flake input pinned to an upstream release tag, and
`kubernetes-axi`/`docker-axi` (no releases, no npm) track their default
branch through `flake.lock`.

Updates arrive as pull requests:

- Renovate (`renovate.json`) checks `packages/npm` daily, after a one-day
  release soak, and merges its PRs through Renovate after all checks pass.
  Native platform auto-merge is disabled while the main ruleset is pending.
- `.github/workflows/flake-update.yml` runs `scripts/flake-update.sh` daily:
  it moves tag-pinned inputs to upstream's latest stable release once it is a
  day old, refreshes the branch-tracked inputs, opens or refreshes one PR, and
  enables GitHub auto-merge only when main requires `darwin-build`.
- `.github/workflows/darwin-build.yml` builds both Macs' systems and runs
  `nix flake check` on `macos-15` (Apple silicon) for every PR. The main
  ruleset requiring its `darwin-build` check is pending in infrastructure
  Terraform; flake update PRs remain unmerged automatically until it exists.

Merged updates are not activated automatically: run `just rebuild`. Roll back
with a revert PR, or locally with `sudo darwin-rebuild --rollback`. Do not use
the tools' own updaters (`treehouse update`, `lavish-axi update`, ...) on these
installs; they would fight the pins.

### M87 GitHub discovery

M87 is installed from the exact `@kunchenguid/m87` npm identity,
whose authoritative upstream is <https://github.com/kunchenguid/m87>, with
integrity hashes pinned in `packages/npm/m87/package-lock.json`. Upstream
requires Node 22.13 or newer and publishes no license declaration, so the Nix
package uses Node 24 and is marked unfree. On the managed Mac profiles, Home
Manager puts the executable at `/etc/profiles/per-user/$USER/bin/m87`; the
standalone Linux Home Manager outputs expose it through their normal profile
path. It does not replace or delete `~/.m87`, so the existing queue, audit
history, and operator state remain in place.

For fresh state, Home Manager uses M87's native headless initializer,
`m87 init --yes --plugin github --github-repo ... --no-install-service`, with
the declarative six-repository list. Upstream has no organization-discovery
flag, so none is invented. For existing state, Home Manager preserves the queue
and reapplies M87's official full-replacement plugin configuration with all
intended selectors:

- `owned_repos=true` preserves Dematom1-owned repository discovery;
- `authored_external=true` adds Dematom1-authored issues and PRs in other repos
  within M87's upstream lookback window;
- `explicit_repos` adds only the six declared Dematom Labs repositories:
  `agent-sandbox-runtime`, `alteran`,
  `conference-directory`, `infrastructure`, `seo-scout`, and `truediyer`.

The configuration deliberately omits `username=dematom-labs`: M87 must continue
to derive the viewer as Dematom1. It also adds no credential. M87 continues to
use the existing `gh` authentication selected by its upstream plugin.

This change does not activate or restart the live installation. After merging,
the personal-machine operator runs `just rebuild personal`; if
`m87 daemon status` still reports a service whose executable is outside
`/etc/profiles/per-user/$USER/bin`, run
`m87 daemon install` once to repoint the managed service without replacing
`~/.m87`. Then run `m87 plugin doctor` and `m87 plugin sync github`; do not
approve any recommendation merely to test discovery. Review/merge actions,
credentials, and repository action policy are separate operator concerns and
are not changed by this discovery configuration.

### Declarative agent tooling

[agent-tooling.json](agent-tooling.json) declares the kept agent tooling. On
every `just rebuild`, the Home Manager `agentTooling` activation runs
[scripts/agent-tooling-reconcile.py](scripts/agent-tooling-reconcile.py), which
brings each tool's own state to exactly that set:

| Manifest key | Tool state | Reconciliation |
|---|---|---|
| `claude.plugins`, `claude.marketplaces` | Claude's plugin registry | The `claude plugin` CLI uninstalls undeclared user-scope plugins and retired project plugins, removes undeclared marketplaces, and adds and installs missing ones. |
| `claude.mcpServers` | `~/.claude.json` `mcpServers` | Declared fields are set and undeclared servers are removed; see the credential preservation rules below. `retiredProjectMcpServers` are removed from every project scope; other project servers stay. |
| `claude.hooks` | `~/.claude/settings.json` and `settings.local.json` hooks | Each installed AXI tool in the justfile's `axi-tools` and (on the work profile) work lists first registers its own hooks with `just _setup-axi-hooks`. Then `ensure` entries are written (replacing any hook that matches them), hooks matching a `keep` substring or a hook-enabled AXI tool name are left to their installers (rtk, herdr, rex, AXI), and every other hook is removed, including those of `axi-tools-no-hooks`. `settings.local.json` only loses hooks. If the justfile lists cannot be read, hooks are left untouched with a warning. |
| `codex.mcpServers` | `~/.codex/config.toml` `[mcp_servers.*]` | As for Claude. Every other table is preserved byte for byte. |
| `codex.hooks` | `~/.codex/hooks.json` | As for Claude. |
| `pi.packages` | `~/.pi/agent/settings.json` `packages` | Only declared package sources remain; existing per-package options and ordering are preserved. Pi installs a missing package on its next start. pi-fff and terminal-status-title are Nix-linked extensions, so they are not packages. |
| `pi.skills` | `~/.pi/agent/skills` | Pi-root skills allowed to stay; everything else there is removed. None are declared: the pstack skills come with the kept `pstack-claude` Pi package and Claude plugin. |
| `skills.sources`, `skills.keep` | `~/.claude/skills`, `~/.agents/skills`, `~/.codex/skills`, `~/.pi/agent/skills` | Non-hidden undeclared entries and broken links are removed, stale skill-lock entries are dropped, and missing declared skills are installed with the skills CLI. See [the skill reference](.agents/SKILLS.md). |

Activation invokes `rtk init -g --hook-only --auto-patch` and
`herdr integration install claude`, `codex`, and `pi` when their CLIs are
available. Missing tools warn without failing activation. The 16 legacy
Impeccable command skills are replaced by the consolidated upstream `impeccable`
skill. Home Manager links the vendored `pi/extensions/terminal-status-title.js`.

AXI binary installation belongs to the separate Nix packaging PR. Missing AXI
tools report that their hooks register on the next rebuild once installed.
Rex is an explicit exception: the app owns its skill and hook, and this
repository preserves them. If a Rex CLI advertises `setup hooks`, activation
invokes it; otherwise the app remains responsible for installation.

The run is idempotent: a second run changes nothing. Before its first mutation,
it snapshots tool configurations, plugin registries, skill locks, existing
skill directories, and known project settings to
`$XDG_STATE_HOME/dotfiles/agent-tooling-backups/<UTC timestamp>/` (default:
`~/.local/state/dotfiles/agent-tooling-backups/<UTC timestamp>/`). Paths inside
`~` retain their home-relative location; external project paths retain their
absolute path without the leading slash. The timestamped directory and every
directory beneath it are created with mode `0700` to protect private
configuration. Originals are retained once per run, including before external
installers run. An unchanged run discards its snapshot.
Absent configuration files receive declared initial state. A file it cannot
parse is left untouched with a warning. Network and CLI failures also only
warn, so they never fail a rebuild.
Preview the plan without changing anything:

```bash
python3 scripts/agent-tooling-reconcile.py --manifest agent-tooling.json --dry-run
```

The manifest holds no secrets. A declared field replaces the live value;
existing fields omitted from the declaration, including `headers` and `env`,
survive. A server that lists `requiredHeaders` (uidotsh) is never created without them: when it is absent or
lacks its header, the run warns, and you add it once through ui.sh's own setup.
Never put the token in this repository.

To add a tool, declare it in `agent-tooling.json` and run `just rebuild`. To
remove one, delete its entry and rebuild.

- **Claude plugin:** add its marketplace to `claude.marketplaces` (name to
  GitHub `owner/repo`) and `plugin@marketplace` to `claude.plugins`.
- **MCP server:** add the non-secret fields under `claude.mcpServers` or
  `codex.mcpServers`. A leading `~/` expands to the home directory.
- **Hook:** add an `ensure` entry for a hook dotfiles defines, or a `keep`
  substring for one an installer writes. An AXI tool's hooks follow the
  justfile: list it in `axi-tools` to register them, or in
  `axi-tools-no-hooks` to remove them.
- **Pi package:** add its source string to `pi.packages`.
- **Skill:** follow [the skill reference](.agents/SKILLS.md#adding-or-removing-a-skill).

Use `/reload-plugins` or a new session in Claude Code, and `/reload` in Pi,
after a rebuild. Quit running Claude Code sessions before rebuilding: a running
session can write its own copy of `~/.claude.json` back over the result. A
second rebuild converges either way.

Activation removes `playground@claude-plugins-official` at existing project
paths reported by Claude's plugin registry. It also removes only retired
headroom hooks from `.claude/settings.local.json` in projects recorded in
`~/.claude.json` and the manifest's `projectPaths`. Unrelated project settings
are preserved, and missing project directories are skipped.

The only manual removal is in **claude.ai, Settings > Connectors**: disconnect
**Gmail**, **Google Calendar**, **Google Drive**, and **Notion**. Keep **Claude
Docs** and the synced account skills. Malformed local JSON remains untouched
with a warning until repaired. Codex may ask to trust changed hooks. Removed
Pi package caches remain on disk but are no longer loaded.

The Xirp app may re-add its hooks when it updates; the next rebuild removes
them again.

### Agent skills and Pi packages

`just rebuild` installs any missing declared skill and removes undeclared ones.
`just update-skills` reinstalls every declared source to pick up new upstream
content. See [the skill reference](.agents/SKILLS.md) for the sources,
discovery paths, and why installation uses physical copies. Invoke a skill such
as Vision with `/skill:vision` in Pi or `/vision` in Claude Code. The copies and
tool registries are never committed.

`just update` still refreshes Ponytail through its native package managers
(`just _update-ponytail`). Its presence is declared in `agent-tooling.json` like
every other plugin and Pi package. Do not edit Claude's generated plugin
registry by hand.

The exact npm package `@ff-labs/pi-fff` is pinned with npm integrity
hashes in `packages/npm/pi-fff/package-lock.json` and linked at Pi's native extension path
`~/.pi/agent/extensions/pi-fff/index.ts`. This registers the `fffind`,
`ffgrep`, and `fff-multi-grep` tools. It is not a declared Pi package, so the
`agentTooling` activation removes a duplicate `npm:@ff-labs/pi-fff`
registration. Existing Pi sessions use `/reload` after
`just rebuild personal`.

The personal Home Manager profile also supplies GnuPG's `gpg` command for the
Terraform secret workflow. It replaces the former Homebrew formula without
creating or importing keys or changing credential storage. Apply it after merge
with `just rebuild personal`.

### Reproducing this Pi config (non-Nix)

For people who want this Pi setup without the Home Manager machinery,
`scripts/install-pi-config.sh` installs the portable core: the shared packages
(`@nikolauska/linear-axi`, `@ff-labs/pi-fff`) and the
Fireworks provider defaults (dark theme, hidden thinking block). It skips the
machine-specific pieces - Nix-store links, the Databricks skills, and the
OpenCode Go model catalog - so bring your own `FIREWORKS_API_KEY`.

```bash
FIREWORKS_API_KEY=... ./scripts/install-pi-config.sh
```

Override `PI_DEFAULT_PROVIDER`, `PI_DEFAULT_MODEL`, or `PI_ENABLED_MODELS` to
point it at a different provider or model.

### Signed Pi Launcher

Both macOS profiles declaratively install `kunchenguid/tap/pi-launcher` and
[Automic Vault](#automic-vault-github-cli-pilot). After `just rebuild`, follow the
[Vault command setup](#manual-gh_token-pilot) and verify that `av --version`
matches the app's `CFBundleShortVersionString`; stop if they differ.

Home Manager installs exactly one credentialed `pi-signed` entrypoint at
`~/.local/bin/pi-signed`. It sets `FM_PI_HARNESS=pi-signed`, requests only
`OPENCODE_API_KEY` from Automic Vault, and targets the absolute signed app
executable `/Applications/Pi Launcher.app/Contents/MacOS/pi-launcher`, preserving
all Pi arguments. Regular `pi` remains unchanged and on `PATH`; there is no
fallback from the signed route to regular Pi. `pi-signed update --self` is
rejected only by this signed route, while the existing regular `pi update --self`
path remains in `just update-firstmate`.

Before making signed launch the normal path, perform one disposable signed
Firstmate supervision smoke. Start Pi exactly as follows, let `pi-signed`
resolve through `PATH`, verify from its bash tool that
`"$FM_HOME/bin/fm-harness.sh"` prints `pi-signed`, and confirm one harmless
Firstmate worker is spawned, observed, and exits normally:

```bash
FM_PI_HARNESS=pi-signed pi-signed
```

That command does not assign or change `FM_HOME`; the existing Firstmate home
continues to apply. Firstmate source and dispatch rules remain unchanged. The
raw signed-app diagnostic path bypasses Vault and injects no secret:

```bash
/Applications/Pi\ Launcher.app/Contents/MacOS/pi-launcher --version
```

The durable custom Pi model catalog is `pi/models.json`; Home Manager links it to
`~/.pi/agent/models.json` without copying it into the Nix store. It contains only
the `OPENCODE_API_KEY` environment-variable reference, never the key itself.
Use the managed route for an approved per-process model command:

```bash
pi-signed --list-models
```

Ox Alpha supports only the `low`, `high`, and `max` thinking levels. The trial
uses `--thinking high`; `max` requires a separate explicit captain instruction.
Do not put the key in a shell profile, command argument, log, session
environment, or generated file.

`just report-pi-signed-drift` is a read-only report of the bundled Pi version
against upstream stable and any open `upstream-pi-blocked` issue. The existing
`just update-firstmate` recipe runs this report after its unchanged regular-Pi
update. The report never updates or installs anything and never closes or
retries an upstream issue. On macOS, verify the new route without an attended
rebuild with:

```bash
just rebuild personal
just report-pi-signed-drift
./tests/pi-signed.sh
```

### Local signoff

The personal Mac installs `signoff`, the signer that posts the App-signed
`local-signoff` check run. It runs a repository's trusted `just signoff` recipe
on a fresh checkout of a pull request head; see
[packages/signoff-src/README.md](packages/signoff-src/README.md) for what it
does and its trust model. [modules/signoff.nix](modules/signoff.nix) installs
it at `/run/current-system/sw/bin/signoff` and declares the `signoff watch`
launchd agent.

- **Source:** `dematom-labs/workflows` is private, so CI and the root-run
  `darwin-rebuild` cannot fetch it as a flake input. `packages/signoff-src` is
  its `signoff/` directory at the `rev` pinned in
  [packages/signoff.nix](packages/signoff.nix). To move to another commit, run
  `scripts/vendor-signoff.sh <sha>`, then `nix build .#signoff`, which runs the
  signer's tests.
- **Trusted PATH:** the build compiles in a read-only `/nix/store` tool
  environment (`git`, `just`, `ast-grep`, `bun`, `node`, `uv`, `python3`, `go`,
  `ruby`, and `bash`) followed by `/usr/bin:/bin`. These are the only tools
  `git`, `just`, and a recipe can resolve. Add a package to `tools` in
  `packages/signoff.nix` when a repository's recipe needs another one.
- **Watcher:** `services.signoff.watch.enable` is off by default. When on, a
  user agent runs one `signoff watch` pass every 120 seconds with App ID
  `5460531`, installation `174959222`, and key fingerprint
  `SHA256:tlF5N8zgxWi5AR2FZdYPcRdbm8C1Dk4LkwsMp77A4Uk=`. A pass exits when done,
  so launchd schedules passes instead of keeping a process alive, and never
  runs two at once. Output goes to `~/.local/state/signoff/watch.log`, and each
  signed head's full log to `~/.local/state/signoff/<owner>/<repo>/<sha>.log`.

Before turning the watcher on, add the installed binary to the App key's access
list. Until then, every signature raises a Keychain prompt.

1. After `just rebuild personal`, print the binary's store path and copy it:

   ```bash
   readlink -f /run/current-system/sw/bin/signoff
   ```

2. Open Keychain Access:

   ```bash
   open "/System/Library/CoreServices/Applications/Keychain Access.app"
   ```

3. Select the **login** keychain and the **Keys** category. Double-click the
   private key imported for the `dematom-local-signoff` App (kind
   **private key**, RSA 2048-bit). Its name depends on how it was imported.
4. On the **Access Control** tab, select **Confirm before allowing access**.
   Under **Always allow access by these applications**, click **+**, press
   **Cmd-Shift-G**, paste the store path from step 1, press **Return**, and
   click **Add**. Select every other entry in the list and click **-**.
5. Click **Save Changes** and enter the login password.

Each signoff build has a new store path and code signature, so repeat these
steps whenever that path changes: after `scripts/vendor-signoff.sh` or a
nixpkgs bump that rebuilds it. Remove the old entry at the same time.

To turn the watcher on, set `services.signoff.watch.enable = true;` in
[hosts/personal.nix](hosts/personal.nix) and run `just rebuild personal`. Then
check that it is loaded and signing:

```bash
launchctl print "gui/$(id -u)/org.nixos.signoff-watch"
tail -f ~/.local/state/signoff/watch.log
```

`nix flake check` runs the `signoff-install` check. It verifies that only the
personal Mac installs the signer, that the watcher ships off with the settings
above, that the binary carries the trusted PATH, and that it refuses a
repository outside `dematom-labs`.

## Linux sandbox server

The flake builds a headless Linux AI sandbox server that `captain` SSHes into.
It is provider-agnostic: no cloud-vendor assumptions, so it applies to any
provisioned x86_64-linux box (bare metal, a droplet, an EC2/GCE instance, a
local VM). The `nixpkgs` pin carries the full Linux/NixOS package set, so it
alone drives both the Darwin hosts and this sandbox. A second, narrowly scoped
`nixpkgs-unstable` input exists only so an overlay can pull a fresher
`terraform` (see `flake.nix`); it isn't a general-purpose second package set.

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

`kubernetes-axi` is built from the exact upstream commit pinned by
`flake.lock`. It is in the shared Home Manager package list, so the
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

### Automic Vault GitHub CLI pilot

Automic Vault is declared as the official
`automic-vault/isotopes/automic-vault` Homebrew cask in `configuration.nix`, so
both Mac profiles install it during a rebuild. After Homebrew runs, nix-darwin's
`postActivation` synchronizes `/usr/local/bin/av` with
`/Applications/Automic Vault.app/Contents/MacOS/av`, creating the destination
directory if needed and replacing a missing or different binary. Every rebuild
verifies byte identity and matching nonempty `--version` output; activation
fails if the bundled CLI is unavailable or synchronization cannot be verified.
Home Manager places a managed Firstmate identity gate ahead of this vendor CLI.
The third-party cask follows this repository's existing rolling Homebrew convention
and is not pinned by `flake.lock`; its cask metadata pins each release artifact
by SHA-256. At pilot start the captain observed `av 3.3.0`.

The [official CLI manual](https://www.automicvault.com/docs/) and
[source repository](https://github.com/automic-vault/automic-vault) are the
authoritative product references.

#### Firstmate project availability

The managed `av` command is available only when the physical working directory
is inside a registered canonical clone, the local dotfiles checkout described
below, or a verified Firstmate worker copy.
Canonical clones are matched by the authoritative Firstmate registry at
`$FM_HOME/data/projects.md`, their real path under `$FM_HOME/projects`, and
Git's common repository directory. When `FM_HOME` is unset or
empty, the gate uses `$HOME/agent-workspace`, the home installed by
`just setup-firstmate`. An isolated copy additionally
requires Firstmate's `FM_TASK_ID`, unique `project`, `worktree`, and `kind`
fields in `$FM_HOME/state/<task>.meta`, a `kind` of `ship` or `scout`, and Git's
registered worktree record pointing at that exact path and common repository
directory.

The physical `$HOME/Code/dotfiles` checkout is also allowed without a task
marker when `$FM_HOME/projects/dotfiles` passes the registered-clone checks.
`$HOME` must be its physical path, and the local checkout must have no symlink
components and must own its real `.git` directory. The two checkouts do not
need to share Git identity or a remote URL. This exception does not extend to
linked worktrees of the local checkout.

Apart from that local dotfiles exception, the gate rejects unregistered clones
and arbitrary repositories. It also rejects symlinks in
registered identity paths, and repositories that merely share a basename or remote
URL. Navigation through a symlink is allowed when the physical working directory
resolves to the verified clone or worker copy. It never creates a second project
registry. It forwards every `av` argument
unchanged to the signed vendor CLI after the identity check.

Availability is not launcher endorsement, secret selection, an approval bypass,
or broader credential scope. Existing per-secret and per-launcher authorization,
including the signed `pi-signed` route and its absolute vendor CLI path, remains
unchanged.

#### Manual GH_TOKEN pilot

This is a bounded, manual pilot for `GH_TOKEN`. It does not harden or replace
the Nix-provided `gh`, migrate credentials, or remove any existing GitHub CLI
authentication.

1. Apply the selected Mac profile with `just rebuild personal` or
   `just rebuild work`.
2. Open the app so its approval service is running. From a project directory
   that satisfies
   [Firstmate project availability](#firstmate-project-availability), verify
   the managed command below and run the remaining `av` steps:

   ```bash
   open /Applications/Automic\ Vault.app
   command -v av
   av --version
   ```

   `command -v av` should print the managed Home Manager `av` wrapper.
3. Audit all reported exposure without changing it. The repository wrapper
   runs the real login-shell path and prints only category, severity, and count:

   ```bash
   just av-scan
   ```

   `just av-scan` exits successfully when the scanner ran, even if findings are
   present. Use `just av-check` for final acceptance; it fails until the same
   app-visible scan has zero findings. Generated-profile regressions isolate
   repository-owned zsh behavior, but they are not a substitute for this real
   operator-path gate.

   Classify every finding before changing state. Generated `zsh` and
   `bash+zsh` configuration is repository-owned. A finding involving both a
   managed command and existing credentials, such as `hcloud` or Git's helper
   selection, needs a repository change only after the captain completes the
   credential migration. Findings for retained tools, Keychain access,
   Homebrew, sudo, Docker, SSH, and external accounts require an explicit
   captain decision. Remove stale tool state only after the captain confirms
   the tool is unused. Preserve Cloudflare Wrangler unless that decision is
   changed explicitly.

   The tracked Git include resets legacy credential helpers and selects the
   native macOS Keychain helper. Do not delete `~/.git-credentials` until a
   private authenticated Git operation succeeds through Keychain; removing the
   old file is a separate captain action.
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
entry and the Vault `postActivation` synchronization block from
`configuration.nix`, then rebuild the selected profile. The copied
`/usr/local/bin/av` is not automatically removed; remove it separately when
uninstalling. That does not delete the `GH_TOKEN` Keychain item. If desired, the
captain can remove that item interactively in Automic Vault after confirming
the fallback works.

The security boundary is local to this Mac. Keychain storage plus per-target
and launcher authorization reduce ambient secret exposure to local agents, but
an approved target controls a secret after receiving it, including in process
memory and its environment. This does not contain same-user malware or a root
compromise, and it does not replace CI, Kubernetes, production, or centralized
secret management.

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

`just check-regressions` verifies the Neovim fff search mapping and the browser
opt-out for both host profiles, keeps Claude and Determinate Nix diagnostics
opt-outs absent, and rejects Clawdbot across tracked configuration, script, and
launch-service surfaces.

## Updating and checks

```bash
cd "$HOME/Code/dotfiles"
git pull
just rebuild          # system, Homebrew, Home Manager, and profile packages
just update           # skills, the FirstMate agent stack, and Ponytail
just check-regressions
```

`just check-regressions` evaluates both flake profiles and verifies their
Darwin and Home Manager homes. Its Terraform check selects both Darwin profiles
on Apple Silicon macOS or the portable sandbox Home Manager output on supported
Linux systems, then verifies the selected package sets and the activated
operator path when safe local evidence is available. It also checks profile
validation, selective OpenCode links, the kept skill sources, SketchyBar
state-file safety (on macOS; on Linux it instead asserts the hook stays
undefined), AXI hook failures and stale shadowing copies, the Neovim fff search mapping, and shell
regressions.

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
├── modules/             # opt-in nix-darwin modules (signoff)
├── packages/            # custom Nix package definitions
├── rebuild.sh           # validated profile selection and darwin-rebuild
├── justfile             # bootstrap, update, skills, and checks
├── tests/               # focused configuration regressions
├── .agents/             # shared skill source and provenance
├── nvim/ zsh/ ghostty/ atuin/ direnv/ git/ yazi/ bat/
├── aerospace/ sketchybar/ karabiner/
├── .wezterm.lua
└── .tmux.conf
```
