# Plugin Development Guide

Plugins live under `scripts/plugins/` and are sourced only when their function is invoked (lazy loading). Unused plugins do not slow startup.

## Plugin Skeleton

```bash
#!/usr/bin/env bash
# scripts/plugins/mytool.sh

function mytool_do_something() {
  _kubectl apply -f my.yaml
}

function _mytool_helper() {
  :
}
```

## Rules

- **Public entry points** — no leading `_`. These are callable via `./scripts/k3d-manager mytool_do_something`.
- **Private helpers** — `_` prefix. Not callable directly.
- Keep functions **idempotent** — safe to run multiple times.
- Avoid side effects on load (plugin file is sourced, not executed).
- Use `_run_command`, `_kubectl`, `_helm`, `_curl` helpers — never call binaries directly.

---

## `_run_command` Helper

Executes system commands with consistent error handling and optional `sudo` support.

```
_run_command [--quiet] [--prefer-sudo|--require-sudo] [--probe '<subcmd>'] -- <prog> [args...]
```

| Flag | Behaviour |
|---|---|
| `--prefer-sudo` | Use sudo if available, fall back to current user |
| `--require-sudo` | Fail if sudo is unavailable |
| `--probe '<subcmd>'` | Run `<prog> <subcmd>` first to decide if sudo is needed |
| `--quiet` | Suppress stderr; still returns exit code |

```bash
# Prefer sudo, fall back to current user
_run_command --prefer-sudo -- apt-get install -y jq

# Require sudo, abort if unavailable
_run_command --require-sudo -- mkdir /etc/myapp

# Probe a subcommand to decide if sudo is needed
_run_command --probe 'config current-context' -- kubectl get nodes
```

Use `--` to separate `_run_command` options from the command being executed.

**Never call `sudo` directly.** Never use `command sudo`. Always route through `_run_command`.

---

## Security Rules for Plugins

See [CLAUDE.md](../../CLAUDE.md) for the full security rules. Key points:

- Always double-quote variable expansions: `"$var"`, never bare `$var`
- New Vault policies: grant minimum required paths
- New ServiceAccounts: never `cluster-admin` — use namespace-scoped Role + RoleBinding
- New Helm installs: pin chart versions explicitly
- Sensitive CLI flags: register in `_args_have_sensitive_flag` in `scripts/lib/system.sh`

---

## Testing Your Plugin

Add a BATS test file in `scripts/tests/plugins/`:

```bash
# scripts/tests/plugins/mytool.bats
@test "mytool_do_something succeeds" {
  run mytool_do_something
  [ "$status" -eq 0 ]
}
```

Run via:

```bash
./scripts/k3d-manager test plugins
./scripts/k3d-manager test mytool    # single file
```

Tests must use `env -i` isolation — no ambient shell state, no cluster dependencies.
