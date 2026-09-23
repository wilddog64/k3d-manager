# `bin/cluster-status --full` aborts immediately on unbound `PLUGINS_DIR`

**Filed:** 2026-09-20
**Branch:** `k3d-manager-v1.36.0`
**Severity:** Medium — `make status-full` is 100% broken, and `make status` tells the operator to
run it.

## Symptom

Found while bringing the rebuilt hub back to a clean `make status`.

```
$ make status-full CLUSTER_PROVIDER=k3d
scripts/plugins/observability.sh: line 6: PLUGINS_DIR: unbound variable
make: *** [status-full] Error 1
```

Reproducible on every invocation, with or without a provider, and directly:
`CLUSTER_PROVIDER=k3d bin/cluster-status --full` fails identically. There is no partial output —
it dies before the first check.

`make status` (summary) **works**, which is what hides this: the two modes do not share a code
path.

```bash
# bin/cluster-status:32-37
if [[ "${_status_mode}" != full ]]; then
  exec "${SCRIPT_DIR}/cluster-status-summary" --mode "${_status_mode}"
fi
source "${REPO_ROOT}/scripts/lib/system.sh"
source "${REPO_ROOT}/scripts/lib/provider.sh"
source "${REPO_ROOT}/scripts/plugins/observability.sh"     # <-- only --full reaches this
```

Summary mode `exec`s a different script and never reaches the `source`. So the broken line is
only on the `--full` path, and the summary output ends with:

```
Overall: FAIL (4 errors, 1 warnings)
Details: make status-full
```

**It points the operator at a command that cannot run.** That is the part worth fixing first: the
diagnostic escape hatch is dead exactly when a failing summary makes you reach for it.

## Root cause

`bin/cluster-status:14` sets `set -euo pipefail`. `scripts/plugins/observability.sh:6` then
dereferences a variable only the dispatcher defines:

```bash
VAULT_PLUGIN="$PLUGINS_DIR/vault.sh"
```

`PLUGINS_DIR` is exported by `scripts/k3d-manager`, which lazy-loads plugins. Any consumer that
sources a plugin **directly** — as `bin/cluster-status` does — has never set it, and under `set -u`
the expansion aborts the script at source time, before any function is even defined.

This is the sourcing-contract half of
[[reference_dispatcher_lazy_load_cross_plugin_calls]]: plugins assume the dispatcher's environment,
and a `bin/` script that sources one directly does not get it.

## The first fix attempt was wrong — recorded because the reasoning matters

The obvious fix is to make the plugin self-locating:
`VAULT_PLUGIN="${PLUGINS_DIR:-$(dirname "${BASH_SOURCE[0]}")}/vault.sh"`. **That does not work**,
and trying it produced the evidence for the real fix:

1. It moved the failure one file along — `observability.sh` sources `vault.sh`, and
   `scripts/plugins/vault.sh:14` has the identical `$PLUGINS_DIR` dereference. Fixing that too
   moved it again, to `vault.sh:22` → `SCRIPT_DIR: unbound variable`.
2. `SCRIPT_DIR` cannot be papered over the same way, because `observability.sh` uses it
   **throughout its function bodies** — `${SCRIPT_DIR}/etc/argocd/applicationsets/...`,
   `${SCRIPT_DIR}/etc/prometheus/rules`, and a dozen more. It is not a source-time detail; the
   plugin genuinely requires the dispatcher's layout contract at call time.
3. The first spelling also added a shellcheck `SC1007` warning on the `CDPATH= cd` idiom.

Conclusion: plugins legitimately depend on the two variables `scripts/k3d-manager:64-65` exports,
and the defect belongs to the **consumer** that sources a plugin without honouring that contract.

## Latent in four more files

The same unguarded top-level pattern exists elsewhere and will break the moment another `bin/`
script sources one of them under `set -u`:

| File | Line |
|---|---|
| `scripts/plugins/vault.sh` | 14 — `ESO_PLUGIN="$PLUGINS_DIR/eso.sh"` |
| `scripts/plugins/argocd.sh` | 18, 25 |
| `scripts/plugins/hub_recovery.sh` | 13, 18, 23 |

Only `observability.sh` is reached by a `bin/` consumer today, so only it is fixed here — the rest
are recorded rather than changed, per the minimal-patch rule. Do **not** bundle them into this fix.

## Fix

Honour the dispatcher's contract in the consumer. In `bin/cluster-status`, immediately after the
summary early-exit and before the `source` lines:

```bash
SCRIPT_DIR="${REPO_ROOT}/scripts"
PLUGINS_DIR="${SCRIPT_DIR}/plugins"
```

Two subtleties make the placement load-bearing:

- **`bin/cluster-status` already defines `SCRIPT_DIR`, and its value is wrong for a plugin.**
  Line 16 sets it to the `bin/` directory, whereas plugins expect `scripts/` — so
  `${SCRIPT_DIR}/etc/prometheus/rules` inside `observability.sh` would resolve under `bin/`. The
  reassignment is required, not merely additive.
- **It must go after the early-exit at lines 32-37**, which is the only other consumer of the
  `bin/` value (`exec "${SCRIPT_DIR}/cluster-status-summary"`). Verified with
  `grep -n SCRIPT_DIR bin/cluster-status`: the variable appears only at lines 16, 17, 34 and 36,
  all before the source, and 34/36 sit in a branch that `exec`s away. `REPO_ROOT` (line 17) is
  computed from the original value and stays correct.

Zero plugin files change, so no other consumer's behaviour moves.

## Tests

`scripts/tests/bin/` is the right home. Assert the contract the fix establishes — that
`bin/cluster-status` defines both variables, pointing at `scripts/`, before it sources a plugin:

```bash
run env -u PLUGINS_DIR bash -u -c '
  SCRIPT_DIR="${PWD}/scripts"; PLUGINS_DIR="${SCRIPT_DIR}/plugins"
  source scripts/plugins/observability.sh && declare -f deploy_observability >/dev/null'
[ "$status" -eq 0 ]
```

plus an ordering assertion that the assignments precede the `source` of a plugin, since a correct
value placed after the source would still abort. Assert on meaningful tokens, not whole lines.

## Definition of Done

- [ ] `CLUSTER_PROVIDER=k3d bin/cluster-status --full` runs to completion
- [ ] `make status-full` runs to completion
- [ ] `make status` (summary) output unchanged
- [ ] BATS case above passes; `make test` green or failures shown pre-existing
- [ ] `shellcheck scripts/plugins/observability.sh` — zero new warnings
- [ ] CHANGELOG `[Unreleased] → ### Fixed`

## What NOT to Do

- Do NOT set `PLUGINS_DIR` in `bin/cluster-status` as the fix.
- Do NOT change the four latent files listed above in this patch.
- Do NOT remove `set -euo pipefail` from `bin/cluster-status`.
