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

1. Read and run the bootstrap, then `make machine-setup ROLE=hub` on the M5.
2. Open OrbStack once (`open -a OrbStack`), accept its first-run screens and approve its helper with your admin password; setup installs the cask but cannot do this step, and `machine-check` does not test it. Wait for `orbctl status` to print `Running`.
3. Re-enter secrets at the TTY when prompted. Run `make machine-check ROLE=hub` twice and confirm the second report is all `ok`.
4. Restore the hub by following [Hub snapshots](hub-snapshots.md). This tool does not move cluster data.
5. Verify the restored hub services and operator access before moving responsibility from the M4. Only then explicitly retire the former hub services.

## Secrets and machine-only keys

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
