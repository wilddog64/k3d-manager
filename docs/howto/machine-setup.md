# Machine setup

`make machine-setup ROLE=hub|worker|console` installs the tools and repositories in the matching `scripts/etc/machine/` manifests. `make machine-check ROLE=...` prints a redacted inventory and exits nonzero when an item is missing. `--check` and `--dry-run` are read-only. Install output (Homebrew, git clone, `make install-*`) goes to `~/.local/state/k3d-manager/machine-setup.log` (mode 600); a failed install reports `missing (see machine-setup.log)`. Run setup from a terminal: secret prompts and the hub setup scripts need it.

Ruff and pytest come from `PATH` or from the setup-managed `${XDG_DATA_HOME:-$HOME/.local/share}/k3d-manager/venv/bin`; add that directory to `PATH` when using the managed venv.

## Starting from a fresh Mac

Download `bin/machine-bootstrap` as a file and read it before running it. Do not pipe it into a shell. It installs Xcode Command Line Tools and signed Homebrew, authenticates GitHub CLI, clones k3d-manager, then runs machine setup. Run from a real terminal so macOS login and Keychain prompts can appear. Keep the M4 account name on the M5 so path-keyed Claude memories continue to resolve.

## Roles

- **hub (M5):** developer and agent tools, hub utilities, and hub LaunchAgents. Do not cut over the hub until the M5 setup and restore are verified.
- **worker (M4):** developer tools, Codex dispatch, tests, ACG sandbox and Playwright. This role does not remove or install hub LaunchAgents; keep the M4 hub services until the cut-over is complete.
- **console (M2):** browser, dashboards and SSH client tools. It does not install hub services.

## M5 hub cut-over

For the staged one-command build and safe agent cut-over, follow the [M5 hub migration guide](m5-hub-migration.md).

1. Read and run the bootstrap. Enable **Remote Login** in Sharing settings on the M4, then run `make machine-setup ROLE=hub FROM=m4-air.local SECRETS=skip AGENTS=skip` on the M5 in a local terminal before cut-over. This copies existing items without offering commands that create or rotate credentials and leaves hub LaunchAgents off the new Mac. It prompts for this Mac's login Keychain password if that Keychain is locked (common in SSH sessions), then for the M4 login password and old Mac Keychain unlock password (normally the same password). Items requiring GUI approval are reported by name; run the file-based export below in a GUI terminal on the M4 for those items.
2. Open OrbStack once (`open -a OrbStack`), accept its first-run screens and approve its helper with your admin password; setup installs the cask but cannot do this step, and `machine-check` does not test it. Wait for `orbctl status` to print `Running`.
3. At cut-over, stop the old Mac's agents first, then rerun `make machine-setup ROLE=hub FROM=m4-air.local` without `AGENTS=skip` to install the hub agents on the new Mac. Run `make machine-check ROLE=hub` twice and confirm the second report is all `ok`.
4. Restore the hub by following [Hub snapshots](hub-snapshots.md). This tool does not move cluster data.
5. Verify the restored hub services and operator access before moving responsibility from the M4. Only then explicitly retire the former hub services.

## Secrets and machine-only keys

### Copy secrets from the old machine

The preferred M5 workflow is `make machine-setup ROLE=hub FROM=m4-air.local`. It streams missing Keychain items through SSH without creating a transfer file. Enable **Remote Login** in Sharing settings on the M4. If the M5 login Keychain is locked, including in an SSH session, pull prompts to unlock this Mac's Keychain before asking for the M4 SSH login password and M4 Keychain unlock password; the latter two are normally the same. Use `SECRETS=skip` on a new Mac to suppress all missing-secret setup prompts while the `FROM=` pull still runs.

If SSH is unavailable, an item needs GUI approval, or you prefer a file, run `make machine-secrets-export ROLE=hub` on the old Mac in a local terminal with the login Keychain unlocked. Enter and confirm a strong passphrase. Transfer the encrypted `.enc` file to the new Mac with AirDrop or `scp`, then run `make machine-secrets-import FILE=<path>` there and enter the passphrase. A successful import deletes the encrypted transfer file; if an item fails, the file is kept for another attempt. Add `FORCE=1` only when intentionally replacing an existing item.

iCloud does not sync these credentials: `security add-generic-password` writes to each Mac's local file-based login Keychain. When setup later prompts to create missing secrets, answer **N** for secrets being copied; the transfer command copies existing values without rotating tokens or changing their live consumers.

The script checks Keychain **presence only**; it never reads values. Missing credentials are re-entered or rotated on the new Mac, never copied from another Mac. Without a TTY, prompts are skipped and the report remains missing. Sign in to Claude (`/login`), Codex (`codex login`), Gemini/agy, and GitHub (`gh auth login`) at the terminal.

SSH and cosign private keys are not copied or read by machine setup. Transfer/recreate them using the operator's approved secure process, then verify their file names and permissions manually. Keep the Bitbucket SSH key available before setting up Bitbucket repositories. Existing checkouts are left untouched; unavailable branches and inaccessible remotes are reported as skipped.

The agent-state sync scripts target shared backup repositories. Until the two-machine `pull --rebase` sync change has been reviewed and merged, let only the M4 run the sync chain. Resolve conflicts manually; never force-push.

## Tracked workstation files

After reviewing each file for secrets, the operator places the workstation files in `zshdotfiles` at these paths:

- `envrc/personal.envrc`, `envrc/k3d-manager.envrc`, and `envrc/ansible.envrc` for the corresponding `.envrc` files.
- `smartcd/src/bash_enter`, `smartcd/personal/bash_enter`, `smartcd/k3d-manager/bash_enter`, and `smartcd/provision-win-tomcat/bash_enter` for the four smartcd hooks. smartcd maps an absolute directory under `~/.smartcd/scripts` to its `bash_enter` file.
- `workspace/CLAUDE.md` for the shared workspace instructions. Setup links all three names `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` to that one file.

Missing source files are reported as skipped. Existing destination files are left for operator review. The worker role includes `install-sudoers` for the scoped host, launchd, CA, and local cluster operations used by ACG. `make setup-worker` configures and deploys the Cloudflare Slack Worker; it is not a workstation worker setup step.

Heartbeat setup renders disabled candidates for review; it does not install a scheduler job. Follow [Independent Heartbeats](independent-heartbeats.md) to enroll checks, review the candidate, and install it separately.
