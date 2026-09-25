# Unify the ArgoCD browser TLS dir on the provider-scoped path

**Filed:** 2026-09-17
**Status:** FIXED — landed in `e259c718` (v1.35.0)
**Follow-up filed:** `2026-09-24-argocd-browser-listener-not-restarted-on-wrapper-change.md` — the path move left the long-running listener bound to the legacy flat dir
**Branch:** `k3d-manager-v1.35.0`
**Follow-up to:** `2026-09-17-cluster-down-argocd-browser-tls-key-not-removed.md` (`4184d23e`)

## Background — what `4184d23e` fixed and what it left

`4184d23e` fixed the leak: `bin/cluster-down` now removes the ArgoCD browser TLS material
from **both** the legacy flat dir and the provider-scoped dir, so a Vault-PKI-issued
`tls.key` no longer survives teardown.

That was deliberately a containment fix. **The divergence that caused it is still there.**

## The divergence

Every `bin/` script computes the dir with the identical, correct, provider-scoped fallback:

```bash
# bin/cluster-up:571, bin/cluster-refresh:494, bin/cluster-down:210
_argocd_browser_tls_dir="${ARGOCD_BROWSER_TLS_DIR:-${_ACG_STATE_DIR}/argocd-browser-https-tls}"
```

`scripts/plugins/argocd.sh:61` pre-assigns the variable to a **flat, provider-agnostic** path:

```bash
: "${ARGOCD_BROWSER_TLS_DIR:=${HOME}/.local/share/k3d-manager/argocd-browser-https-tls}"
```

`: "${VAR:=default}"` **assigns**. So whether the correct `:-` fallback in a `bin/` script
ever fires depends entirely on whether `argocd.sh` was sourced first:

| Script | sources `plugins/argocd.sh` | effective dir |
|---|---|---|
| `bin/cluster-up` (line 52) | yes | **flat** — its own fallback is dead code |
| `bin/cluster-refresh` (line 31) | yes | **flat** — same |
| `bin/cluster-down` | no | **scoped** |

Identical source lines, two different directories, no error anywhere. That asymmetry was
the whole bug.

`scripts/lib/providers/k3s-hostinger.sh:378-379` independently hardcodes the same flat path
as its own fallback:

```bash
CERT_FILE="${ARGOCD_BROWSER_TLS_CERT_FILE:-${HOME}/.local/share/k3d-manager/argocd-browser-https-tls/fullchain.crt}" \
KEY_FILE="${ARGOCD_BROWSER_TLS_KEY_FILE:-${HOME}/.local/share/k3d-manager/argocd-browser-https-tls/tls.key}" \
```

## Why the flat path is wrong beyond the leak

The flat dir is **shared across every provider**. `k3s-aws`, `k3s-az`, `k3s-gcp` and
`k3s-hostinger` all write `fullchain.crt` / `tls.key` / `ca.crt` to the same three
filenames. Bringing up a second provider silently overwrites the first provider's cert and
key; the first provider's listener then serves a cert issued by a different cluster's Vault
CA. Everything else in the tree is already provider-scoped via `_acg_provider_state_dir`
(`scripts/lib/provider.sh:177`) — this one directory is the exception.

## Required change

### 1. `scripts/plugins/argocd.sh` — source `provider.sh`, then scope the default

`_acg_provider_state_dir` must be in scope. **Do not guard with `declare -f`** — a
`declare -f` guard is the known smell for this class of problem, and it silently no-ops.
Use the guarded-source idiom this same file already uses for its `vault` and `eso`
dependencies at lines 6-18, pointed at `lib/provider.sh`:

```bash
PROVIDER_LIB="$SCRIPT_DIR/lib/provider.sh"
if [[ -r "$PROVIDER_LIB" ]]; then
   # shellcheck disable=SC1090
   source "$PROVIDER_LIB"
fi
```

Place it with the other dependency sources near the top of the file, before the `:` default
assignments — the default at line 61 calls the function, so it must already be defined.
Note the surrounding file indents with **3 spaces**, not 2; match it.

Then replace line 61:

```bash
# OLD
: "${ARGOCD_BROWSER_TLS_DIR:=${HOME}/.local/share/k3d-manager/argocd-browser-https-tls}"

# NEW
: "${ARGOCD_BROWSER_TLS_DIR:=$(_acg_provider_state_dir "${CLUSTER_PROVIDER:-k3s-aws}")/argocd-browser-https-tls}"
```

Lines 62-64 (`..._CERT_FILE`, `..._KEY_FILE`, `..._CA_FILE`) derive from
`${ARGOCD_BROWSER_TLS_DIR}` and must be left exactly as they are — they follow
automatically.

`k3s-aws` is the correct fallback provider: it is the default already used at
`bin/cluster-down:27`.

**Verified reachable:** `scripts/k3d-manager:68` sources `lib/provider.sh` before any
plugin is lazy-loaded, and `bin/cluster-up` (48 before 52), `bin/cluster-refresh` (25
before 31) and `bin/cluster-down` (23) all source it first too. The guarded source is for
the standalone case — a BATS file that sources `argocd.sh` on its own.

### 2. `scripts/lib/providers/k3s-hostinger.sh:378-379` — drop the hardcoded flat fallbacks

Point both fallbacks at the provider-scoped dir. Derive from
`_acg_provider_state_dir "${CLUSTER_PROVIDER:-k3s-hostinger}"` in this file — note the
default provider here is `k3s-hostinger`, not `k3s-aws`. Do not duplicate the literal
`${HOME}/.local/share/k3d-manager/...` string anywhere.

## No migration. Do not write one.

A migration is the obvious move and it is the wrong one. Two reasons:

1. **The flat dir's contents are unattributable.** It may hold `k3s-aws`'s cert, or
   `k3s-hostinger`'s, or one overwritten by the other. Moving it into a provider-scoped dir
   asserts an origin nobody can verify, and could install one cluster's key under another
   cluster's name.
2. **Re-issue is already automatic.** `bin/cluster-up:582` calls
   `_argocd_issue_browser_tls_material "${_argocd_browser_tls_dir}"` unconditionally on the
   not-healthy branch, so the next bring-up mints fresh material into the scoped dir from
   that cluster's own Vault PKI. A short-TTL leaf cert (≤720h) is meant to be re-issued.

An already-running listener keeps serving from its existing wrapper, which embeds the old
absolute cert path, until it is torn down — so this change is non-breaking for a live
cluster. The legacy flat dir is cleaned up by the `4184d23e` teardown path.

## Tests

Add to `scripts/tests/plugins/` (new file or the closest existing argocd suite):

- With `CLUSTER_PROVIDER=k3s-aws` and `ARGOCD_BROWSER_TLS_DIR` unset, sourcing `argocd.sh`
  yields a dir under the `k3s-aws` scoped state dir.
- With `CLUSTER_PROVIDER=k3s-hostinger`, the dir differs from the `k3s-aws` one. **Assert
  the two are not equal** — that inequality is the entire point of the change and is what
  regresses if someone reinstates a flat literal.
- An explicit `ARGOCD_BROWSER_TLS_DIR=/tmp/custom` in the environment still wins (the
  `:=` override contract must not break).
- `..._CERT_FILE` / `..._KEY_FILE` / `..._CA_FILE` sit inside whichever dir won.

Set `HOME` to `${BATS_TEST_TMPDIR}/home` so nothing touches the real state dir. Stub
`uname` if any assertion crosses an `_is_mac` branch — do not read the host OS.

## Rules

- `set -euo pipefail`; double-quote every expansion.
- `shellcheck -S error` clean on every file touched.
- Minimal patch — no unsolicited refactors, no reformatting of surrounding lines.
- No inline comments in shell blocks.
- No bare `!` in BATS; no whole-line `grep -F` of a source line.
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/`.

## Definition of Done

- [ ] `argocd.sh` sources `lib/provider.sh` via the file's existing guarded-source idiom.
- [ ] `argocd.sh:61` default is provider-scoped; 62-64 unchanged.
- [ ] `k3s-hostinger.sh:378-379` no longer contain a hardcoded flat path.
- [ ] `command grep -rn 'share/k3d-manager/argocd-browser-https-tls' scripts/plugins/ scripts/lib/ bin/` returns
      **only** the legacy-cleanup lines in `bin/cluster-down` — that is the one place the
      literal is still correct, because it exists to delete it. The gate deliberately does
      **not** cover `scripts/tests/` — `cluster_down.bats` holds the same literal on purpose,
      because its job is to prove the legacy dir gets cleaned. Do NOT split or rewrite that
      string to make a grep stop matching; that is gate evasion, not a fix.
- [ ] New BATS coverage per the Tests section, including the not-equal assertion.
- [ ] `make test` green; `make test-bin` green (108 cases).
- [ ] `shellcheck -S error` clean.
- [ ] CHANGELOG `### Fixed` entry under `[Unreleased]`.
- [ ] Commit message exactly:
      `fix(argocd): scope the browser TLS dir to the cluster provider`
- [ ] `git push origin k3d-manager-v1.35.0` succeeded, and
      `git rev-parse origin/k3d-manager-v1.35.0` matches the local HEAD.
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with the SHA.

## What NOT to Do

- Do NOT write a migration that moves or copies the existing flat cert material. See above.
- Do NOT `rm -rf` the legacy flat dir here — teardown already handles it, named-file only.
- Do NOT guard `_acg_provider_state_dir` with `declare -f`.
- Do NOT change `bin/cluster-up`, `bin/cluster-refresh` or `bin/cluster-down` — their
  fallbacks are already correct and become live once the plugin stops overriding them.
- Do NOT touch `_acg_provider_state_dir` or `_acg_normalize_provider` in
  `scripts/lib/provider.sh`.
- Do NOT raise `VAULT_PKI_ROLE_TTL` or `ARGOCD_BROWSER_VAULT_PKI_ROLE_TTL`.
- Do NOT touch a live cluster, listener, launchd job, Keychain, or Vault. No `kubectl`, no
  `helm`, no `launchctl`, no `security add-trusted-cert`. Code plus BATS only.
- Do NOT create a PR. Do NOT merge. Do NOT commit to `main`. Do NOT force-push.
- Do NOT use `--no-verify`. Do NOT run `git add -A`.
