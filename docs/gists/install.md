# Install k3d-manager

```bash
git clone git@github.com:wilddog64/k3d-manager.git
cd k3d-manager
./scripts/k3d-manager
```

Requires bash 4+ (auto-detected — macOS ships bash 3.2, Homebrew bash is used automatically if present).

## Pre-commit Hooks (recommended)

Installs the agent rigor pre-commit hook — enforces shellcheck, security rules, and subtree protection on every commit:

```bash
bash scripts/hooks/install-hooks.sh
```

## rigor-cli (optional — standalone enforcement)

[rigor-cli](https://github.com/wilddog64/rigor-cli) wraps the same agent rigor framework as a standalone CLI. Useful for running `audit`, `lint`, and `checkpoint` outside of the pre-commit hook (e.g. in CI or on demand in any Bash project):

```bash
git clone git@github.com:wilddog64/rigor-cli.git
cd rigor-cli
./bin/rigor --help
```

Full docs: https://github.com/wilddog64/k3d-manager
