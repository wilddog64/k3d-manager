# hostinger registration never sets the provider label, so ambient CNI dirs resolve to generic

**Filed:** 2026-09-23
**Branch:** `k3d-manager-v1.37.0`
**Severity:** high — this is the remaining link in the chain that kept `istio-cni-node` 0/1 on
ubuntu-hostinger for 17 days. `02e3fa76` fixed the overwrite mechanism but cannot produce a correct
value while the provider label reads `unknown`.

## Symptom

`istio-cni-node-vgr6m` on ubuntu-hostinger has been `0/1 Running` since 2026-09-06.
`install-cni` readiness returns HTTP 503, **160,074 probe failures over 17 days, 0 restarts** — the
probe has never once passed. Ambient is in real use, not cosmetic: `ztunnel-69cft` is `1/1` and
namespace `shopping-cart-apps` carries `istio.io/dataplane-mode: ambient`.

## Evidence

The hub's registration Secret for hostinger carries a provider of `unknown`:

```
$ kubectl --context k3d-k3d-cluster -n cicd get secret cluster-ubuntu-hostinger \
    -o jsonpath='{.metadata.labels.k3d-manager/provider}'
unknown

$ kubectl ... -o jsonpath='{.metadata.annotations.k3d-manager/registered-at}'
2026-09-24T01:52:01Z
```

That timestamp is the operator's own `make refresh-registration CLUSTER_PROVIDER=k3s-hostinger`
run, tonight. The registration succeeded and **still** wrote `unknown`, so the `CLUSTER_PROVIDER`
passed on the command line never reaches the label.

The live `istio-ambient` ApplicationSet consequently still holds the generic dirs:

```yaml
cni:
  cniConfDir: /etc/cni/net.d
  cniBinDir: /opt/cni/bin
```

## Root cause

`_hostinger_register_cluster` (`scripts/lib/providers/k3s-hostinger.sh:1033+`) sets seven
`ARGOCD_APP_CLUSTER_*` variables in the subshell that calls `register_app_cluster` and
**never sets `ARGOCD_APP_CLUSTER_PROVIDER`**:

```
$ grep -c ARGOCD_APP_CLUSTER_PROVIDER scripts/lib/providers/k3s-hostinger.sh
0
```

So `register_app_cluster` falls through to its default at `scripts/plugins/argocd.sh:1500`:

```yaml
    k3d-manager/provider: "${ARGOCD_APP_CLUSTER_PROVIDER:-unknown}"
```

`_istio_ambient_target_provider` then reads `unknown` off the label, and
`_istio_ambient_cni_dirs unknown` hits the `*)` catch-all and returns the generic pair. The
substrate-derived path introduced by `02e3fa76` therefore produces exactly the value it was written
to prevent, and does so confidently.

### Why the new guard does not catch it

`scripts/plugins/argocd.sh:1280` refuses generic dirs only when the provider matches `k3s*`:

```bash
      if [[ -n "${conf:-}" && "${conf}" == "/etc/cni/net.d" && "${provider:-}" == k3s* ]]; then
```

`unknown` does not match `k3s*`, so the guard is inert in precisely the state that is broken. It
guards a case that cannot currently occur and ignores the one that does.

The glob is also too narrow in a second way. The resolver's substrate-specific arms are `k3d` and
`k3s-hostinger`:

```bash
function _istio_ambient_cni_dirs() {
  case "${1:-}" in
    k3d)           printf '%s %s\n' /var/lib/rancher/k3s/agent/etc/cni/net.d /bin ;;
    k3s-hostinger) printf '%s %s\n' /var/lib/rancher/k3s/agent/etc/cni/net.d /var/lib/rancher/k3s/data/cni ;;
    *)             printf '%s %s\n' /etc/cni/net.d /opt/cni/bin ;;
  esac
}
```

A `k3d` target whose live AppSet held generic dirs would sail past a `k3s*` test just as `unknown`
does. **Note that the bare string `k3s` is NOT substrate-specific** — it falls to the catch-all and
yields the generic pair. The only correct value for the Hostinger VPS is the exact string
`k3s-hostinger`. Do not "simplify" it to `k3s`.

## S1 — pass the provider at hostinger registration

In `scripts/lib/providers/k3s-hostinger.sh`, inside `_hostinger_register_cluster`, add
`ARGOCD_APP_CLUSTER_PROVIDER` to the env block of the subshell that calls `register_app_cluster`.

Old:

```bash
    ARGOCD_APP_CLUSTER_ENVIRONMENT="${HOSTINGER_ARGOCD_APP_CLUSTER_ENVIRONMENT:-${ARGOCD_APP_CLUSTER_ENVIRONMENT:-dev}}" \
    ARGOCD_APP_CLUSTER_INSECURE="${insecure}" \
```

New:

```bash
    ARGOCD_APP_CLUSTER_ENVIRONMENT="${HOSTINGER_ARGOCD_APP_CLUSTER_ENVIRONMENT:-${ARGOCD_APP_CLUSTER_ENVIRONMENT:-dev}}" \
    ARGOCD_APP_CLUSTER_PROVIDER="${ARGOCD_APP_CLUSTER_PROVIDER:-k3s-hostinger}" \
    ARGOCD_APP_CLUSTER_INSECURE="${insecure}" \
```

The `:-` default keeps an explicit caller override working while making the common path correct.

## S2 — make the CNI-dir refusal depend on the resolver, not a glob

Add a companion to the resolver in `scripts/plugins/istio_ambient.sh`, immediately after
`_istio_ambient_cni_dirs`. It is the single source of truth for "is this provider substrate-specific":

```bash
function _istio_ambient_cni_provider_is_specific() {
  case "${1:-}" in
    k3d|k3s-hostinger) return 0 ;;
    *)                 return 1 ;;
  esac
}
```

Then in `scripts/plugins/argocd.sh`, replace the `k3s*` glob guard.

Old:

```bash
      if [[ -n "${conf:-}" && "${conf}" == "/etc/cni/net.d" && "${provider:-}" == k3s* ]]; then
         _warn "[argocd] ${name}: refusing generic CNI dirs for provider ${provider}"
         conf=""
         bin=""
      fi
```

New:

```bash
      if [[ -n "${conf:-}" && "${conf}" == "/etc/cni/net.d" ]] \
         && declare -f _istio_ambient_cni_provider_is_specific >/dev/null 2>&1 \
         && _istio_ambient_cni_provider_is_specific "${provider:-}"; then
         _warn "[argocd] ${name}: refusing generic CNI dirs for provider ${provider}"
         conf=""
         bin=""
      fi
      if [[ -n "${conf:-}" && "${conf}" == "/etc/cni/net.d" ]] \
         && [[ -z "${provider:-}" || "${provider}" == unknown ]]; then
         _warn "[argocd] ${name}: provider is '${provider:-<empty>}' — writing GENERIC CNI dirs, which are wrong for any k3s or k3d substrate"
         _warn "[argocd] ${name}: re-register the target so its k3d-manager/provider label is set"
      fi
```

The first block is the existing refusal, now keyed off the resolver so `k3d` is covered too. The
second block does **not** change the value — an unrecognized provider may legitimately be generic,
e.g. orbstack — it only makes the guess audible instead of silent. That distinction matters: this
whole class of bug survived three fixes because writing a wrong value produced no output at all.

## S3 — warn when any registration omits the provider

In `scripts/plugins/argocd.sh`, in `register_app_cluster`, before the Secret is rendered, warn when
the provider is unset. This is what stops the next provider repeating the same omission:

```bash
  if [[ -z "${ARGOCD_APP_CLUSTER_PROVIDER:-}" ]]; then
    _warn "[argocd] ARGOCD_APP_CLUSTER_PROVIDER unset — registering ${ARGOCD_APP_CLUSTER_NAME:-<unnamed>} with provider 'unknown'"
    _warn "[argocd] Substrate-derived config (ambient CNI dirs) will fall back to generic defaults for this cluster"
  fi
```

Do **not** make this fatal. Registration must keep working for callers that genuinely have no
provider, and a hard failure here would break `make up` paths that are currently green.

## Tests

New suite `scripts/tests/plugins/argocd_app_cluster_provider_label.bats`:

1. `hostinger registration sets the k3s-hostinger provider label` — stub the hub `_kubectl`, run
   `_hostinger_register_cluster`, assert the rendered Secret contains
   `k3d-manager/provider: "k3s-hostinger"`. Follow the existing pattern at
   `scripts/tests/lib/provider_contract.bats:836`, which already asserts
   `k3d-manager/provider: "k3s-aws"`.
2. `an explicit provider override still wins` — export `ARGOCD_APP_CLUSTER_PROVIDER=k3s-other`,
   assert the label is `k3s-other`, proving the `:-` default did not harden into a constant.
3. `register_app_cluster warns when the provider is unset` — assert the warning text and that the
   function still returns 0.

Append to `scripts/tests/plugins/istio_ambient_cni_dirs.bats`:

4. `_istio_ambient_cni_provider_is_specific accepts k3d and k3s-hostinger`
5. `_istio_ambient_cni_provider_is_specific rejects unknown, empty and bare k3s` — the bare `k3s`
   case is the trap; assert it explicitly.

Append to `scripts/tests/plugins/argocd_appset_cni_dir_precedence.bats`:

6. `generic live dirs are refused for a k3d target` — the case the old `k3s*` glob missed.
7. `an unknown provider warns that generic dirs are being written` — assert the warning fires and
   that the emitted dirs are still the generic pair (behaviour unchanged, audibility added).

## Mutations — prove each test can fail

- **M1** — revert S1 (drop the `ARGOCD_APP_CLUSTER_PROVIDER` line). Test 1 must go red on the
  asserted label, showing `unknown`. It must fail on the label value, not on a stub error.
- **M2** — in `_istio_ambient_cni_provider_is_specific`, add `k3s` to the accepted arm. Test 5 must
  go red. This proves the suite pins the exact string that actually resolves correctly.
- **M3** — restore the `k3s*` glob in place of the resolver call. Test 6 must go red for the `k3d`
  target while the existing k3s cases stay green.

For each: reintroduce the defect, run the suite, paste the red, restore the file, and confirm
`git diff --quiet` before the next mutation. A new test that passes is not evidence it can fail.

## Docs

- `docs/guides/istio-ambient.md` — add a short subsection: the ambient CNI dirs are derived from the
  target's `k3d-manager/provider` label, the only substrate-specific values are `k3d` and
  `k3s-hostinger`, bare `k3s` resolves to the generic pair, and a cluster registered without a
  provider silently gets generic dirs. Include the one-line check:
  `kubectl -n cicd get secret cluster-<name> -o jsonpath='{.metadata.labels.k3d-manager/provider}'`.
- `CHANGELOG.md` — `[Unreleased]` → `### Fixed`.
- `memory-bank/activeContext.md` and `memory-bank/progress.md` — commit SHA and status.

## Definition of Done

- [ ] S1, S2 and S3 implemented exactly as written above.
- [ ] All seven tests green; paste the bats output with counts.
- [ ] `shellcheck -x` on `scripts/plugins/argocd.sh`, `scripts/plugins/istio_ambient.sh` and
      `scripts/lib/providers/k3s-hostinger.sh` — zero new warnings. Paste before and after counts.
- [ ] M1, M2, M3 each mutation-proved red, pasted, then restored.
- [ ] `make test` green (~15 min; that is not a hang) and bare `pytest` green. Paste both summaries.
- [ ] Pushed to `origin/k3d-manager-v1.37.0`; `git rev-parse HEAD` and
      `git rev-parse origin/k3d-manager-v1.37.0` print the same SHA.

Commit message, verbatim:

```
fix(argocd): set the provider label when registering ubuntu-hostinger

_hostinger_register_cluster set seven ARGOCD_APP_CLUSTER_* variables and never
set ARGOCD_APP_CLUSTER_PROVIDER, so register_app_cluster fell through to its
"unknown" default. _istio_ambient_cni_dirs then hit its catch-all and returned
the generic /etc/cni/net.d and /opt/cni/bin, which are wrong for the k3s VPS.
The substrate-derived precedence added in 02e3fa76 therefore produced exactly
the value it was written to prevent, and istio-cni-node stayed 0/1 for 17 days.

The refusal guard could not catch it either: it matched the provider against
k3s*, which "unknown" does not match, and which also misses a k3d target whose
live AppSet holds generic dirs. It now asks the resolver whether a provider is
substrate-specific, and warns loudly when the provider is unknown or empty
rather than writing a guess in silence.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B9RRyT5eU8S76oXYMrLZN8
```

## What NOT to do

- Do NOT create a pull request, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT touch the live cluster: no kubectl, no helm, no docker, no `make up`, no `make refresh`,
  no ApplicationSet reapply, no re-registration. The reapply is the operator's step and is gated on
  the operator's explicit go. Your task is code, tests and docs only.
- Do NOT hand-patch the live `cluster-ubuntu-hostinger` Secret. It would be overwritten by the next
  registration and it hides the defect this spec exists to fix.
- Do NOT change `ARGOCD_APP_CLUSTER_PROVIDER` to the bare string `k3s`. It resolves to the generic
  dirs. The correct value is `k3s-hostinger`.
- Do NOT make the S3 warning fatal.
- Do NOT revert or weaken `02e3fa76`, `03b875c5` or `114e5c82`. All three are correct.
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/` — subtrees, fixed upstream.
- Do NOT edit `scripts/etc/argocd/applicationsets/istio-ambient.yaml` or `scripts/etc/argocd/vars.sh`.
- Do NOT DELETE, MOVE or RENAME any file outside the target list, for any reason, including a scope
  or hygiene check. If a check flags an unrelated or untracked file, LEAVE IT ALONE and report it in
  your final message instead. A previous run deleted an untracked spec file it judged to be
  test-generated; it was not, and the work had to be reconstructed from a log.

## Target files

```
scripts/lib/providers/k3s-hostinger.sh
scripts/plugins/istio_ambient.sh
scripts/plugins/argocd.sh
scripts/tests/plugins/argocd_app_cluster_provider_label.bats      (new)
scripts/tests/plugins/istio_ambient_cni_dirs.bats                 (2 cases appended)
scripts/tests/plugins/argocd_appset_cni_dir_precedence.bats       (2 cases appended)
docs/guides/istio-ambient.md
CHANGELOG.md
memory-bank/activeContext.md, memory-bank/progress.md
```

## Operator runbook — NOT for the implementing agent

After this lands, the operator (not the agent) runs, in order:

1. `make refresh-registration CLUSTER_PROVIDER=k3s-hostinger`, then confirm the label is now
   `k3s-hostinger`.
2. Reapply the `istio-ambient` ApplicationSet and confirm it writes
   `/var/lib/rancher/k3s/agent/etc/cni/net.d` and `/var/lib/rancher/k3s/data/cni`.
3. Roll `istio-cni-node` and confirm `1/1`, then confirm `KubeDaemonSetRolloutStuck` clears.
