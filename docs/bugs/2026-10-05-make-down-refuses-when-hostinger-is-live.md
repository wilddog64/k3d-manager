# Bug: a bare `make down` refuses whenever Hostinger is live, although it can only ever target the AWS sandbox

**Status:** OPEN
**Filed:** 2026-10-05
**Branch:** `k3d-manager-v1.41.0`
**Severity:** Low. A usability defect: no wrong teardown, but `make up` and `make down` are not
symmetric in the operator's normal state.
**Files:** `bin/require-unambiguous-provider`, `scripts/tests/lib/provider_active_set.bats`,
`docs/howto/hub-rebuild-from-gitops-vault.md`, `CHANGELOG.md`

## Symptom

With the ACG sandbox and Hostinger both up (the normal state), `make up` builds the sandbox with no
parameter, but `make down` refuses:

```
Refusing: 2 providers are live and CLUSTER_PROVIDER was not set.
Live providers:
  - k3s-aws
  - k3s-hostinger
Re-run with an explicit provider, e.g.:
  make down CLUSTER_PROVIDER=k3s-aws
```

## Root cause

`bin/require-unambiguous-provider` (added in v1.28.0 for parallel multi-cloud sandboxes) refuses
whenever more than one provider is live and `CLUSTER_PROVIDER` was not set explicitly.

For `make down` that ambiguity is false when the second provider is Hostinger:

- The Makefile sets `CLUSTER_PROVIDER ?= k3s-aws`. A bare `make down` always runs the `*)` branch
  (`bin/cluster-down`). It reaches `k3s-hostinger` only through an explicit
  `CLUSTER_PROVIDER=k3s-hostinger`, which bypasses the guard anyway.
- Hostinger is long-lived; it is never the cluster a bare `make down` is meant to remove.

The guard's real case still matters: with two **sandbox** providers live (for example `k3s-aws`
and `k3s-gcp`), a bare `make down` would silently pick `k3s-aws` when the operator may mean the
other.

`make status` and `make status-json` must keep the current behaviour. A bare `make status` passes
an empty provider to `bin/cluster-status`, and `_acg_resolve_provider` probes `ubuntu-hostinger`
first, so with both live it would silently report on Hostinger.

## Fix spec

### File 1 — `bin/require-unambiguous-provider`

**1a.** In the header comment, replace:

```bash
# Purely additive — a no-op unless ALL of these hold:
#   - CLUSTER_PROVIDER was NOT set on the command line / environment (arg1 != 1)
#   - two or more providers are live in the active-providers set
```

with:

```bash
# Purely additive — a no-op unless ALL of these hold:
#   - CLUSTER_PROVIDER was NOT set on the command line / environment (arg1 != 1)
#   - two or more providers are live in the active-providers set
# For MAKE_TARGET=down, k3s-hostinger is not counted: a bare `make down` always
# targets the Makefile default (k3s-aws) and can never reach Hostinger, which is
# long-lived. `make status` keeps counting it, because a bare status resolves to
# Hostinger first.
```

**1b.** Replace:

```bash
mapfile -t _live < <(_acg_list_active_providers 2>/dev/null || true)
```

with:

```bash
mapfile -t _live < <(_acg_list_active_providers 2>/dev/null || true)

if [[ "${MAKE_TARGET:-}" == "down" ]]; then
  _counted=()
  for _p in "${_live[@]}"; do
    [[ "${_p}" == "k3s-hostinger" ]] && continue
    _counted+=("${_p}")
  done
  _live=("${_counted[@]}")
fi
```

The match is on `MAKE_TARGET` exactly equal to `down`; an unset `MAKE_TARGET` keeps today's
behaviour. Keep `set -euo pipefail` working: with zero non-Hostinger providers, `_counted` is
empty, so make sure `"${_counted[@]}"` does not trip `set -u` under the bash this repo runs (macOS
`/bin/bash` 3.2 and Linux bash 5). If it does, use the `${_counted[@]+"${_counted[@]}"}` form.

### File 2 — `scripts/tests/lib/provider_active_set.bats`

After the existing three `require-unambiguous-provider` tests, add these, using the same
`_ACG_ACTIVE_PROVIDERS_DIR` / `_ACG_ACTIVE_PROVIDER_FILE` pattern:

1. **down, aws + hostinger → proceeds:** `MAKE_TARGET=down`, files `k3s-aws` and `k3s-hostinger`,
   arg `0`. Status is 0.
2. **down, two sandboxes + hostinger → still refuses:** `MAKE_TARGET=down`, files `k3s-aws`,
   `k3s-gcp` and `k3s-hostinger`, arg `0`. Status is 3; the output contains `2 providers are live`,
   `k3s-aws` and `k3s-gcp`, and does **not** contain `k3s-hostinger` (use `run !` or `|| false`,
   never a bare `! [[ … ]]`).
3. **down, hostinger only → proceeds:** `MAKE_TARGET=down`, file `k3s-hostinger` only, arg `0`.
   Status is 0.
4. **status, aws + hostinger → still refuses:** `MAKE_TARGET=status`, files `k3s-aws` and
   `k3s-hostinger`, arg `0`. Status is 3.

Do not change the three existing tests; the first one (no `MAKE_TARGET`) must still exit 3.

### File 3 — `docs/howto/hub-rebuild-from-gitops-vault.md`

Replace:

```markdown
- A bare `make down` also **refuses** outright: `bin/require-unambiguous-provider` exits 3 because
  two providers are live (`k3s-aws`, `k3s-hostinger`) and `CLUSTER_PROVIDER` was not set
  explicitly. That guard is doing its job — do not defeat it, give it the right provider.
```

with:

```markdown
- A bare `make down` does **not** protect you here. Since 2026-10-05,
  `bin/require-unambiguous-provider` no longer counts the long-lived `k3s-hostinger` for
  `make down`, so with only the sandbox and Hostinger live it proceeds with the `k3s-aws` default
  and tears the sandbox down. It still refuses when two sandbox providers are live. Give the
  provider explicitly.
```

### File 4 — `CHANGELOG.md`

Under `[Unreleased]` → `### Fixed`, add a prose entry: a bare `make down` now proceeds when the
only other live provider is Hostinger, since it always targets the `k3s-aws` default and cannot
reach Hostinger; it still refuses with two sandbox providers live, and `make status` is
unchanged because a bare status resolves to Hostinger first.

Flip this file's **Status** to FIXED.

## Definition of Done

- [ ] Pre-fix proof: new tests 1 and 2 are RED at `HEAD` (tests 3 and 4 pass there; they guard
      against over-loosening). Paste the output for all four.
- [ ] Mutation: drop the `MAKE_TARGET` condition so Hostinger is filtered for every target;
      test 4 goes red. Restore from a `$TMPDIR` snapshot and prove it with `cmp`.
- [ ] `bats scripts/tests/lib/provider_active_set.bats` is green; paste the counts.
- [ ] `shellcheck bin/require-unambiguous-provider` shows no new findings vs `HEAD`.
- [ ] Changes are left **unstaged**. Claude verifies and commits.

## What NOT to do

- Do NOT change the `Makefile`, `bin/cluster-down`, `_acg_list_active_providers` or
  `_acg_resolve_provider`.
- Do NOT change the `status` / `status-json` behaviour.
- Do NOT run `make down`, `make -n down`, or any lifecycle target. No cluster or AWS access.
- Do NOT touch files outside those listed. No commit, push, PR or `--no-verify`.
