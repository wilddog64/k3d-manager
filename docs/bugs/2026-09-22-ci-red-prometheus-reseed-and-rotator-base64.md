# Bug: PR #130 CI red — Prometheus reseed conflates two states, two no-op BATS assertions, a stale Makefile assertion, and `base64 --decode` in the platform-ops rotators

**Filed:** 2026-09-22
**Branch:** `k3d-manager-v1.36.0`
**Blocks:** PR #130 (cannot merge while `lint` is red)
**Failing run:** [35722946408](https://github.com/wilddog64/k3d-manager/actions/runs/35722946408) at `02c4bee3` — job `lint`, `make test` exits 1

## Symptom

Four BATS cases fail. The first three were introduced by this branch's Prometheus reseed work;
the fourth is a pre-existing test that has never actually tested what it claims.

```
not ok 57  no bare '! cmd' assertions in BATS suites (set -e ignores them)
not ok 174 deploy_observability_acg falls back to generated Prometheus config when Vault bootstrap write fails
not ok 179 prometheus auth proxy skips unreadable Vault credentials and missing auth files
not ok 388 make alertmanager-secret rejects empty input without calling Vault
```

A fifth defect is in the same blast radius and is fixed here rather than in a second doc: the
Keycloak and ArgoCD credential rotators call `base64 --decode`, which the container image's
BusyBox `base64` rejects.

## Root causes

### M1 — `_observability_ensure_prometheus_login` cannot tell "Vault unreachable" from "entry absent"

`scripts/plugins/observability.sh:282-320`. The Vault read is `curl -sf ... | python3 -c ...`,
and **every** way that pipeline can fail collapses into one state:

```bash
  if ! _prom_creds=$(curl -sf \
      --header "@${_vault_hdr}" \
      "http://127.0.0.1:18200/v1/secret/data/k3d-manager/prometheus-basic-auth" 2>/dev/null \
      | python3 -c "..." 2>/dev/null); then
    _prom_creds=""
  fi

  if [[ -z "${_prom_creds}" ]]; then
    _warn "[observability] Prometheus credentials absent from Vault — reseeding the canonical entry"
```

`_prom_creds=""` means all of: Vault is down, the port-forward is not up, the token is wrong,
the KV entry is genuinely gone, or the entry exists but is malformed. The function then treats
all of them as "gone" and **reseeds** — generating a new password and overwriting Vault.

That is wrong in the common case and destructive in the worst one. When Vault is merely
unreachable the correct action is to skip: warn and leave both Vault and the local auth file
alone. Reseeding on an unreachable Vault means a transient port-forward outage rotates a
credential nobody asked to rotate, and the "no recoverable password" branch invalidates every
saved login — `_warn "... generated a new one; saved logins will stop working"`.

This is exactly what tests 174 and 179 pin. Test 179 stubs `curl() { return 22; }` — Vault
unreachable — and asserts the old, correct behaviour:

```bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"Prometheus Vault credentials unreadable"* ]]
  [[ "$output" == *"Prometheus auth file missing"* ]]
  run test -f "${auth_file}"
  [ "$status" -ne 0 ]          # no auth file written
  run test -e "${calls_log}"
  [ "$status" -ne 0 ]          # launchctl never invoked
```

Both tests are **correct and must not be weakened**. They are the regression guard for this
defect. They failed because the reseed change broke a real behavioural contract, not because
they were stale.

### M1 note — the reseed capability must survive

Do not fix this by deleting the reseed. It exists for a real incident: the live KV entry
`secret/k3d-manager/prometheus-basic-auth` was lost, Vault answered `404`, and
`make show-service-passwords` printed `N/A` with no self-repair. The fix must keep reseeding
when the entry is genuinely absent and skip when Vault cannot be reached.

### M2 — two bare-`!` assertions are no-ops

`scripts/tests/plugins/observability_prometheus_reseed.bats:47` and `:84`:

```bash
  ! grep -F 'test-vault-token' "${calls}"
  ! grep -Fx 'password' "${calls}"
```

A bare `!` suppresses `set -e`, so neither assertion can ever fail the test — they assert
nothing. `scripts/tests/lib/bats_negation_lint.bats` gates this repo-wide and is test 57.

These two are not merely lint debt. Line 47 is the assertion that the Vault **token** never
reaches the recorded call log, and line 84 is the assertion that the literal string `password`
is never written as a credential. Both are security assertions that are currently inert.

### M3 — test 388 asserts a message the recipe does not emit, and never reaches the code it claims to test

`scripts/tests/plugins/alertmanager_config_secret.bats:42-54`. Two independent defects:

1. **Stale message.** The test asserts `*"all three values are required"*`. The recipe
   (`Makefile:590`) emits `[alertmanager-secret] ERROR: unresolved:$_missing`. The string
   `all three values are required` does not appear anywhere in the Makefile.

2. **The stub exits at the root-token check.** The `kubectl` stub is `printf '#!/bin/sh\nexit 0\n'`
   — it prints nothing, so `_tok` is empty and the recipe bails at its first gate:

   ```
   [ -n "$$_tok" ] || { echo "... cannot read Hub Vault root token" >&2; exit 1; }
   ```

   Execution never reaches the empty-value validation the test is named after. The test passes
   its `[ "${status}" -ne 0 ]` assertion for entirely the wrong reason.

3. **It is not hermetic.** `security find-generic-password` is not stubbed. On the Linux CI
   runner the binary is absent so `|| true` yields empty values and the unresolved path is
   reached by accident. **On a macOS developer box where the operator has the real Keychain
   entries, all three values resolve, every validation passes, and the recipe attempts a live
   Vault write.** A unit test must never be able to do that.

### M4 — `base64 --decode` is rejected by BusyBox in the rotator image

All four platform-ops rotators run on `docker.io/alpine/k8s:1.31.4`, whose `base64` is BusyBox
and accepts only `-d`. `--decode` is rejected with a usage error. Verified directly in the image.

| File | Line | Consequence |
|---|---|---|
| `scripts/etc/argocd/platform-ops/keycloak-credential-rotator.yaml` | 98 | `slack_url` is always empty — **the rollback-failure alert is never sent** |
| `scripts/etc/argocd/platform-ops/keycloak-credential-rotator.yaml` | 113 | success notification never sent |
| `scripts/etc/argocd/platform-ops/argocd-credential-rotator.yaml` | 118 | `old_mtime` always empty (`|| true`-guarded) |
| `scripts/etc/argocd/platform-ops/argocd-credential-rotator.yaml` | 139 | success notification never sent |
| `scripts/etc/argocd/platform-ops/argocd-credential-rotator.yaml` | 117 | **no `|| true` guard — under `set -eu` this aborts the job** |
| `scripts/etc/argocd/platform-ops/grafana-credential-rotator.yaml` | 128 | correct already (`base64 -d`) — do not touch |

Keycloak line 98 is the serious one. The spec for that rotator called a failed rollback "the
worst possible outcome" precisely because it can lock the operator out of the console, and the
Slack alert is the only signal that it happened. It is currently silent.

ArgoCD line 117 reads the existing bcrypt hash with no `|| true`, so the failing `base64`
likely aborts the ArgoCD rotator at its first step. **This is inferred from source, not
observed** — the ArgoCD rotator has not been run since the defect was found. Do not claim it is
confirmed.

Confirmed empirically on 2026-09-22 during the live Keycloak rotation: the job reached
`SuccessCriteriaMet succeeded=1` and its logs — which are empty by design — instead carried the
BusyBox usage error. The rotation itself succeeded; only the notification was lost.

## Before You Start

Read all of these before editing anything:

- `memory-bank/activeContext.md` and `memory-bank/progress.md` — current state, including the
  2026-09-22 Keycloak rotation record
- `scripts/plugins/observability.sh:240-340` — `_observability_seed_prometheus_vault_entry`,
  `_observability_ensure_prometheus_login`, `_observability_install_prometheus_auth_proxy`
- `scripts/tests/lib/observability.bats:175-230` (test 174) and `:340-366` (test 179) — the two
  correct tests that must pass **unmodified**
- `scripts/tests/plugins/observability_prometheus_reseed.bats` — all of it, including the
  `stub_prometheus_reseed` helper
- `scripts/tests/plugins/alertmanager_config_secret.bats:42-54`
- `Makefile:590-625` — the `alertmanager-secret` recipe and its exact error strings
- `scripts/etc/argocd/platform-ops/grafana-credential-rotator.yaml:120-135` — the correct
  `base64 -d` idiom to copy

## M1 — separate "unreachable" from "absent"

Add a small reachability helper next to the existing Vault helpers in
`scripts/plugins/observability.sh`:

```bash
function _observability_vault_reachable() {
  local _hdr="$1"
  curl -sf --max-time 5 --header "@${_hdr}" \
    "http://127.0.0.1:18200/v1/sys/health?standbyok=true&perfstandbyok=true" >/dev/null 2>&1
}
```

Then gate the reseed on it. Replace the `if [[ -z "${_prom_creds}" ]]; then` block's entry
condition so the three states are distinct:

```bash
  if [[ -z "${_prom_creds}" ]]; then
    if ! _observability_vault_reachable "${_vault_hdr}"; then
      _warn "[observability] Prometheus Vault credentials unreadable — Vault is unreachable; not reseeding"
      rm -f "${_vault_hdr}"
      return 0
    fi
    _warn "[observability] Prometheus credentials absent from Vault — reseeding the canonical entry"
    ...
```

Requirements:

- The header file must be removed on **every** exit path, including the new early return. It
  holds the Vault root token; leaking it into `/tmp` is a security regression. The current code
  does `rm -f "${_vault_hdr}"` once, before the `-z` check — confirm the ordering you end up
  with removes it exactly once and always, and do not read the file after removing it.
- The unreachable path returns **0** and writes **no** auth file. Test 179 asserts both.
- The warning must contain the substring `Prometheus Vault credentials unreadable` — test 179
  matches on it.
- Do not modify tests 174 or 179.

### M1b — fix the reseed suite's own stubs

Adding the probe means `stub_prometheus_reseed` must declare Vault reachable, or every reseed
test skips instead of reseeding. Add one line to the helper:

```bash
  _observability_vault_reachable() { return 0; }
```

Then fix the one test whose intent now collides with test 179. `prometheus reseed: failed write
remains a failure through refresh` currently stubs `curl() { return 22; }` and asserts
`_observability_ensure_prometheus_login` returns non-zero. With the probe stubbed reachable that
still holds — the read fails, the reseed is attempted, the POST fails, the function returns 1.
Confirm it does, and if the stub needs to distinguish the read from the POST, make it do so
rather than changing the assertion. The test's stated intent — a failed **write** is a failure —
must survive.

## M2 — convert both bare-`!` assertions

```bash
  run grep -F 'test-vault-token' "${calls}"
  [ "$status" -ne 0 ]
```

and

```bash
  run grep -Fx 'password' "${calls}"
  [ "$status" -ne 0 ]
```

Do not change what is asserted, only the form. Note that `run` inside a test that has already
used `run` overwrites `$status`/`$output`, so place these after the assertions that consume the
earlier `run`.

**Mutation check required.** Both are absence assertions, so they pass trivially and prove
nothing on their own. Prove each can fail: make the stub write the asserted string into
`${calls}`, show the assertion go red, then revert. Paste both outputs. A converted assertion
that still cannot fail is the same no-op in a new costume.

## M3 — make test 388 test what it is named after

Three changes to `scripts/tests/plugins/alertmanager_config_secret.bats:42-54`:

1. `kubectl` stub must emit a base64 token so the recipe gets past the root-token gate:
   `printf '#!/bin/sh\nprintf dG9rZW4=\n'`
2. Stub `security` to exit non-zero, so the Keychain lookups resolve to empty on macOS as well
   as Linux and the test becomes hermetic: `printf '#!/bin/sh\nexit 1\n'`
3. Assert the message the recipe actually emits — `*"unresolved:"*` — plus the `gmail_from`,
   `gmail_app_pw` and `sms_gateway` names, so the assertion pins the operator-facing content
   rather than one brittle full line. Do **not** paste a whole source line as the pattern;
   whole-line assertions rot.

Keep `[ ! -e "${BATS_TEST_TMPDIR}/curl-called" ]` — that is a file-existence test, not a bare
`!` command assertion, and the lint does not flag it.

**Mutation check required.** With the stubs fixed, confirm the test now fails if the
`unresolved:` assertion is changed to a string the recipe does not emit, and confirm the recipe
is genuinely reaching the three-values gate — not still exiting at the token check. Show the
captured `${output}` to prove which gate fired.

## M4 — `base64 --decode` → `base64 -d`

Replace `base64 --decode` with `base64 -d` at:

- `scripts/etc/argocd/platform-ops/keycloak-credential-rotator.yaml:98,113`
- `scripts/etc/argocd/platform-ops/argocd-credential-rotator.yaml:117,118,139`

Do not touch `grafana-credential-rotator.yaml` — it is already correct. Do not change any other
line in these manifests, and do not add a `|| true` to ArgoCD line 117: the abort-on-failure
there is correct behaviour once `base64` works, because the rotator cannot proceed without the
old hash.

### M4b — a test that bans the long form repo-wide

Add a case to `scripts/tests/plugins/platform_ops_rotators.bats` (create the file if it does not
exist, following the setup idiom of `keycloak_credential_rotator.bats`):

```bash
@test "platform-ops rotators use BusyBox-compatible base64 -d" {
  run grep -rn -- 'base64 --decode' "${SCRIPT_DIR}/etc/argocd/platform-ops"
  [ "$status" -ne 0 ]
}
```

**Mutation check required.** Absence assertion — prove it fails by reintroducing
`base64 --decode` into one manifest on a scratch copy, then restore.

Also add a case asserting each rotator that reads a Kubernetes Secret pipes through `base64 -d`
at least once, so a future edit cannot satisfy the ban by dropping the decode entirely.

## Rules

- `set -euo pipefail` conventions of the surrounding shell; double-quote every expansion
- LF endings only; no inline comments in shell blocks
- **No bare `!` in any BATS assertion** — `run <cmd>` then `[ "$status" -ne 0 ]`. You are fixing
  two of these; do not add a third.
- Never print, echo or log a credential — the Vault root token, the Prometheus password, the
  Slack webhook URL, or an ArgoCD bcrypt hash. Do not add `set -x` anywhere.
- No credential in argv. The Vault token stays in the header file; the Slack URL stays in a
  variable passed via `-H`/`-d`.
- Minimal patch. Do **not** "fix" info-severity shellcheck findings on lines this doc does not
  touch — CI runs `shellcheck -S error` (`.github/workflows/ci.yml:55`) and info findings are
  not gates. A previous run in this project wasted a change rewriting an intentionally-literal
  string for SC2016; do not repeat it.
- Do NOT weaken, skip, or modify `scripts/tests/lib/observability.bats` tests 174 or 179.
- Do NOT run anything against the live cluster, Vault, Keycloak, ArgoCD, Prometheus or a
  port-forward. Source-only change with stubbed tests.
- Do NOT `kubectl apply` any manifest and do NOT create any Job. The operator triggers real runs.
- Do NOT seed, write, rotate or repair any credential anywhere.
- Do NOT modify `scripts/lib/foundation/` or `scripts/lib/acg/` (upstream subtrees), or the
  `shopping-cart-infra` repo.
- Do NOT `git add -A`. Do NOT `git stash` — forbidden in this session; use a scratch copy for
  mutation checks and restore it.
- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.

## Files you may touch

- `scripts/plugins/observability.sh`
- `scripts/tests/plugins/observability_prometheus_reseed.bats`
- `scripts/tests/plugins/alertmanager_config_secret.bats`
- `scripts/tests/plugins/platform_ops_rotators.bats` (new)
- `scripts/etc/argocd/platform-ops/keycloak-credential-rotator.yaml`
- `scripts/etc/argocd/platform-ops/argocd-credential-rotator.yaml`
- `docs/howto/rotate-service-credentials.md` (M5 below)
- `CHANGELOG.md`
- `memory-bank/activeContext.md`, `memory-bank/progress.md`

Touch no others.

## M5 — documentation

Every feature and fix gets its documentation updated in the same release; the CHANGELOG and
memory-bank do not count. Add a short subsection to
`docs/howto/rotate-service-credentials.md` under "Expect it to take a few minutes, and expect
no logs" recording that:

- rotator job logs are empty **on success**, so any output at all is a defect worth reading
- the image's `base64` is BusyBox and accepts only `-d`
- a missing Slack notification does not mean the rotation failed, and vice versa — check job
  status, not Slack

## Gates — run every one and paste the real output

```
1. shellcheck -S error -x scripts/plugins/observability.sh; echo "RC=$?"
2. bats scripts/tests/lib/observability.bats
3. bats scripts/tests/plugins/observability_prometheus_reseed.bats
4. bats scripts/tests/plugins/alertmanager_config_secret.bats
5. bats scripts/tests/plugins/platform_ops_rotators.bats
6. bats scripts/tests/lib/bats_negation_lint.bats
7. yq '.' scripts/etc/argocd/platform-ops/keycloak-credential-rotator.yaml >/dev/null; echo "KC_RC=$?"
   yq '.' scripts/etc/argocd/platform-ops/argocd-credential-rotator.yaml >/dev/null; echo "ARGO_RC=$?"
8. make check-doc-links
9. make test          # the full suite; ~15 minutes, NOT a hang — all four named cases must pass
```

Gate 9 is mandatory and is the only gate that reproduces CI. Do not report done on the strength
of the targeted suites alone: tests 174 and 179 live in a different file from the change that
broke them, which is the whole reason this defect reached CI.

For every mutation check, state explicitly whether the assertion is expected to pass before your
change — an absence assertion proves nothing on its own.

## Definition of Done

- M1–M5 implemented
- Tests 57, 174, 179 and 388 all pass, and tests 174/179 are **unmodified** (`git diff` on
  `scripts/tests/lib/observability.bats` must be empty — show it)
- All nine gates run with real output pasted, including the four mandatory mutation checks
- `CHANGELOG.md` `## [Unreleased]` → `### Fixed`, naming: the reseed unreachable-vs-absent
  distinction, the two no-op assertions, the stale and non-hermetic alertmanager test, and the
  BusyBox `base64` defect that silenced the rotators' Slack notifications
- Commit message first line exactly:

      fix(observability): distinguish unreachable Vault from an absent Prometheus entry

  and end the commit message with these two trailer lines:

      Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
      Claude-Session: https://claude.ai/code/session_01B9RRyT5eU8S76oXYMrLZN8

- `git push origin k3d-manager-v1.36.0`
- Confirm with `git rev-parse origin/k3d-manager-v1.36.0` and report that SHA. Do NOT report done
  until the push has succeeded. If you cannot create `.git/index.lock` (a sandbox restriction hit
  in this project before), do NOT fabricate a SHA — say plainly that the change is uncommitted in
  the working tree and stop. Do not leave unrelated edits behind.
- Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with the SHA and status

## Report back

- The commit SHA and the output of `git rev-parse origin/k3d-manager-v1.36.0`
- `git show <sha> --stat`
- All nine gates' pasted output, plus each mutation check
- `git diff origin/k3d-manager-v1.36.0~1 -- scripts/tests/lib/observability.bats` (must be empty)
- The exact before/after of the reseed gating condition, so the unreachable path can be reviewed
  without reading the whole function
- Where the Vault header file is removed on each of the function's exit paths
- Anything in this doc you judged wrong, impossible or unsafe, and what you did instead — say so
  plainly rather than diverging silently
