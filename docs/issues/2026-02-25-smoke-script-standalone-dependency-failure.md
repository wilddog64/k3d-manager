# Smoke Script Fails When Run in Isolation

**Date:** 2026-02-25
**Status:** Open

## Description

`bin/smoke-test-jenkins.sh` exits early when invoked directly (outside the
`deploy_jenkins` flow) because it cannot find its library dependencies
(`scripts/lib/system.sh`, `scripts/plugins/vault.sh`, etc.).

Gemini observed this when attempting to run the script standalone for validation:

```bash
bash -x ./bin/smoke-test-jenkins.sh jenkins jenkins.dev.local.me 8443 default
```

The script sources these files relative to `SCRIPT_DIR` at startup:
```bash
source "${SCRIPT_DIR}/../scripts/lib/system.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../scripts/plugins/vault.sh" 2>/dev/null || true
```

The `|| true` means missing sources are silently swallowed, but downstream
functions (`_vault_exec`, `_kubectl`, etc.) are undefined, causing early exit
when they are called.

## Impact

- Standalone validation of the smoke script is unreliable — failures may be
  caused by missing dependencies rather than real smoke test issues.
- Agents (Gemini, CI) that try to run the script directly will get misleading
  results or silent failures.

## Correct Invocation

The smoke script must be invoked through the deployer, which sources the full
library before calling `_jenkins_run_smoke_test`:

```bash
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_jenkins --enable-vault
```

This ensures all library functions are available in the shell environment before
the smoke script is called.

## Fix Options for Codex

**Option 1 (preferred):** Add a self-sufficiency guard at the top of
`bin/smoke-test-jenkins.sh` that detects missing dependencies and prints a
clear error with the correct invocation hint, rather than silently failing
mid-run:

```bash
if ! declare -f _kubectl >/dev/null 2>&1; then
  echo "ERROR: smoke-test-jenkins.sh must be run via deploy_jenkins, not directly." >&2
  echo "       Use: CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_jenkins --enable-vault" >&2
  exit 1
fi
```

**Option 2:** Make the script fully self-sourcing by sourcing the library
unconditionally (remove `|| true`) and exiting with a clear error if the
source fails. Higher risk — changes startup behavior.

Option 1 is preferred: fail fast and loud with a helpful message rather than
silently degrading.

## Verification

After fix: running `bin/smoke-test-jenkins.sh` directly should immediately print
the error and hint rather than silently failing partway through.

## Resolution (2026-02-25)

- Adopted **Option 1**: the script now checks for `_kubectl` immediately after the
  optional sources and exits with the guidance above when it is not present. This keeps
  the smoke helper dependent on the deployer environment while making standalone runs
  fail fast and self-documenting.
- Manual verification: running `./bin/smoke-test-jenkins.sh` from a fresh shell now
  prints the error/usage hint and exits non-zero before any smoke logic executes.
- No change to orchestrated runs (`deploy_jenkins`, `test_jenkins_smoke`) because the
  guard already finds `_kubectl` in those shells.
