# `add_ubuntu_k3s_cluster` deletes `default` kubeconfig entries it does not own

**Filed:** 2026-09-11
**Branch:** `k3d-manager-v1.33.0`
**Severity:** latent — orphans the hub context on the next run
**Source:** Finding 10 of
`../issues/2026-09-11-hub-post-rebuild-verification-gaps.md`

## Problem

`scripts/plugins/shopping_cart.sh:59-60`, inside `add_ubuntu_k3s_cluster`, runs
unconditionally right after the stale `ubuntu-k3s` context is removed:

```bash
kubectl config delete-cluster default &>/dev/null || true
kubectl config delete-user default &>/dev/null || true
```

The intent is sound: a k3s kubeconfig names its cluster and user `default`, and
`kubectl config rename-context` renames only the *context*, so a previous merge
leaves `default` cluster and user entries behind. Clearing them before
re-merging keeps stale credentials from surviving.

The defect is that `default` is a generic name with no owner, and the delete is
unconditional. On this machine the hub context depends on exactly those entries:

```text
CURRENT   NAME              CLUSTER   AUTHINFO
*         k3d-k3d-cluster   default   default
```

So the next `add_ubuntu_k3s_cluster` run orphans the hub context:
`k3d-k3d-cluster` keeps pointing at a cluster and user that no longer exist, and
every `kubectl --context k3d-k3d-cluster ...` call fails until it is rebuilt.
Nothing in the function warns, because both deletes are `&>/dev/null || true`.

Pre-existing, not caused by the 2026-09-11 stale-context cleanup — confirmed
against the kubeconfig backup taken before that deletion. Recovery is
`k3d kubeconfig merge k3d-cluster`, but the plugin should not be deleting
kubeconfig entries it does not own.

## Fix

Delete a `default` entry only when no remaining context references it. This
preserves the original cleanup exactly (after the `ubuntu-k3s` context is
removed, a `default` left over from a prior merge is unreferenced and still gets
pruned) while never touching one another context owns.

### Change 1 — add the helper

Add this private helper immediately **above** `function add_ubuntu_k3s_cluster()`
in `scripts/plugins/shopping_cart.sh`:

```bash
function _shopping_cart_prune_orphan_default_entries() {
  local _refs
  _refs=$(kubectl config view \
    -o jsonpath='{range .contexts[*]}{.context.cluster}{"\n"}{end}' 2>/dev/null || true)
  if printf '%s\n' "${_refs}" | grep -qx "default"; then
    _info "[shopping_cart] Keeping kubeconfig cluster 'default' — still referenced by a context"
  else
    kubectl config delete-cluster default &>/dev/null || true
  fi
  _refs=$(kubectl config view \
    -o jsonpath='{range .contexts[*]}{.context.user}{"\n"}{end}' 2>/dev/null || true)
  if printf '%s\n' "${_refs}" | grep -qx "default"; then
    _info "[shopping_cart] Keeping kubeconfig user 'default' — still referenced by a context"
  else
    kubectl config delete-user default &>/dev/null || true
  fi
}
```

### Change 2 — call it instead of the bare deletes

In `add_ubuntu_k3s_cluster`, replace exactly:

```bash
  kubectl config delete-cluster default &>/dev/null || true
  kubectl config delete-user default &>/dev/null || true
```

with:

```bash
  _shopping_cart_prune_orphan_default_entries
```

Do not move it — it stays in the same position, after the `ubuntu-k3s` context
removal and before `cp "${local_kubeconfig}" "${_tmp_kube}"`.

## Behaviour verified before filing

The helper was prototyped against three kubeconfig fixtures:

| Fixture | `default` referenced by | Result |
|---|---|---|
| hub-style: context `k3d-k3d-cluster` -> cluster/user `default` | yes | both **kept**, both info lines printed |
| orphan: no context references `default` | no | both **deleted** (original behaviour) |
| empty config, no `contexts:` key at all | n/a | no deletion attempted, exit 0 under `set -euo pipefail` |

`grep -qx` is deliberate — an anchored whole-line match, so a context using a
cluster named `default-old` does not count as a reference.

## Tests

Add to `scripts/tests/plugins/shopping_cart.bats`. Stub `kubectl` as a shell
function, as the existing tests in that file do; assert on which
`delete-cluster` / `delete-user` calls the stub recorded.

1. **keeps `default` when a context still references it** — stub
   `kubectl config view` to emit `default` for both jsonpath queries; assert the
   stub recorded no `delete-cluster` and no `delete-user` call, and that output
   contains `Keeping kubeconfig cluster 'default'`.
2. **prunes `default` when nothing references it** — stub `kubectl config view`
   to emit only `ubuntu-hostinger`; assert the stub recorded both
   `delete-cluster default` and `delete-user default`.
3. **no unconditional delete remains in the source** — a grep guard mirroring
   the existing `local k3s kubeconfig keeps loopback endpoint` test style:

```bash
@test "add_ubuntu_k3s_cluster does not unconditionally delete default kubeconfig entries" {
  run grep -nE '^\s*kubectl config delete-(cluster|user) default' scripts/plugins/shopping_cart.sh
  [ "$status" -ne 0 ]
  run grep -nF '_shopping_cart_prune_orphan_default_entries' scripts/plugins/shopping_cart.sh
  [ "$status" -eq 0 ]
}
```

Note the grep in test 3 is anchored to the start of the line so it does not
match the guarded calls inside the helper, which are indented under `else`.

## Rules

- `shellcheck -S error scripts/plugins/shopping_cart.sh` must report zero
  findings.
- `bats scripts/tests/plugins/shopping_cart.bats` must pass in full — paste the
  complete output, not a summary.
- Double-quote every variable expansion.
- No inline comments in the shell blocks.
- Minimal patch — do not refactor anything else in `add_ubuntu_k3s_cluster`, and
  do not touch the `ubuntu-k3s` context removal above it.

## Definition of Done

- [ ] Helper `_shopping_cart_prune_orphan_default_entries` added above
      `add_ubuntu_k3s_cluster`, verbatim as specified
- [ ] The two unconditional `delete-cluster` / `delete-user default` lines
      replaced by the single helper call, in the same position
- [ ] Three BATS tests added to `scripts/tests/plugins/shopping_cart.bats`
- [ ] `shellcheck -S error` clean on the plugin
- [ ] `bats scripts/tests/plugins/shopping_cart.bats` green, full output pasted
- [ ] Commit message exactly:
      `fix(shopping_cart): prune only orphaned default kubeconfig entries`
- [ ] Pushed to `origin/k3d-manager-v1.33.0`; report the SHA and confirm it with
      `git rev-parse origin/k3d-manager-v1.33.0`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with
      the SHA and status; paste the lines added

## What NOT to Do

- Do NOT create a PR
- Do NOT merge anything
- Do NOT commit to `main` — work only on `k3d-manager-v1.33.0`
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside `scripts/plugins/shopping_cart.sh`,
  `scripts/tests/plugins/shopping_cart.bats`, and the two memory-bank files
- Do NOT change `~/.kube/config` on this machine — this task is code only
