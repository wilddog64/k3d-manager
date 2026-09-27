# Bug: the Hermes `eso` sensor reports `unknown` forever, while holding a real finding it discards

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-27
**Status:** OPEN — assigned to Codex
**Files:** `scripts/lib/webhook/smoke.py`, `scripts/lib/hermes/sensors.py`,
`scripts/tests/lib/webhook_hub_eso.bats`, `scripts/tests/hermes/test_hermes.py`,
`docs/guides/hermes.md`, `CHANGELOG.md`
**Prior art:** `docs/bugs/2026-07-17-status-health-absent-vs-fail.md` (introduced the tri-state
`ok is None` contract and `_kubectl_absent`), `docs/bugs/2026-09-14-status-hub-eso-unmonitored.md`
(added the `Hub ESO *` rows to `make status` but explicitly left `scripts/lib/hermes/` alone)

---

## Problem

Every Hermes cycle reports:

```
eso  unknown  ESO status source unavailable
```

This has persisted across many cycles and was assumed to be a credential or transport problem.
It is neither. There are **four** distinct defects stacked on top of each other, and the last one
is the reason this went unnoticed for two releases.

### Reproduction — deterministic, no credential, no mutation

```bash
PYTHONPATH=scripts/lib python3 - <<'PY'
from webhook import smoke
from hermes.sensors import eso
res = smoke._eso_health_results("ubuntu-k3s")
for name, ok, detail in res:
    print(f"  {name!r}: ok={ok!r} detail={detail!r}")
payload = {"services": [{"name": n, "ok": ok, "detail": d} for n, ok, d in res]}
print("sensor:", eso(lambda *a, **k: payload, {}, token="x")["status"])
PY
```

Observed (2026-09-27):

```
  'ESO ClusterSecretStore': ok=None detail='not installed (no ClusterSecretStore on ubuntu-k3s)'
  'ESO ExternalSecrets': ok=None detail='not installed (no ExternalSecret CRD on ubuntu-k3s)'
sensor: unknown
```

Both records claim the resources are **not installed**. That claim is false — nothing was ever
queried, because there is no `ubuntu-k3s` cluster to query.

### D1 — `_kubectl_absent()` classifies a kubeconfig error as resource absence

`~/.local/share/k3d-manager/active-provider` does not exist, so `_resolve_provider("")` falls
through to its `"k3s-aws"` default, and `_provider_context("k3s-aws")` returns `"ubuntu-k3s"`.
The kubeconfig holds only `k3d-k3d-cluster` and `ubuntu-hostinger`. kubectl therefore prints:

```
Error in configuration: context was not found for specified context: ubuntu-k3s
```

Lowercased, that string contains the substring **`not found`**, which is one of
`_kubectl_absent()`'s absence signatures (`scripts/lib/webhook/smoke.py`). So:

```
kubeconfig error  →  "not found" substring  →  _kubectl_absent() True
                  →  (name, None, "not installed …")  →  sensor sees ok is None  →  unknown
```

"Absent" is a claim about a cluster that was **successfully queried**. When kubectl never reached
a cluster, the resource's existence is simply unknown, and asserting "not installed" is wrong.

### D2 — `_posix_spawn_capture()` discards the exit code, leaving only substring matching

`scripts/lib/webhook/smoke.py`:

```python
def _posix_spawn_capture(cmd, timeout, cwd=None, env=None):
    if _posix_capture is not None:
        return _posix_capture(cmd, timeout, cwd=cwd, env=env)
    _rc, output, timed_out = _spawn_capture_text(cmd, cwd=cwd, env=env, timeout=timeout)
    return output.strip(), timed_out
```

`_spawn_capture_text` (`scripts/lib/webhook/proc.py:16`) returns `(rc, output, timed_out)` — the
exit code **is available and is thrown away one line later**. With it gone, a configuration error
(`rc=1`, reached nothing) is indistinguishable from a legitimate `No resources found` (`rc=0`,
queried successfully), so classification degenerates to guessing from prose. This is the same
defect class as discarding an `HTTPError` body: the authoritative signal is in hand and dropped.

Threading `rc` through every caller is a wider change than this fix needs; D1's fix closes the
live symptom. The discard is recorded here as the underlying cause.

### D3 — the sensor never reads the `Hub ESO *` rows, so it discards a real finding

`docs/bugs/2026-09-14-status-hub-eso-unmonitored.md` added hub rows to `/api/v1/health`, and
scoped `scripts/lib/hermes/` out on purpose. Nothing has wired them in since. The sensor
exact-matches the unprefixed pair only:

```python
entries = [item for item in services if item.get("name") in
           ("ESO ClusterSecretStore", "ESO ExternalSecrets")]
```

So `Hub ESO ClusterSecretStore` / `Hub ESO ExternalSecrets` are never evaluated. What they
actually contain right now:

```
  'Hub ESO ClusterSecretStore': ok=True  detail='Ready=True'
  'Hub ESO ExternalSecrets':    ok=False detail='1/8 not synced: cosign-public-key'
```

**The sensor is not merely blind — it is blind while holding the answer.** Every cycle it computes
a genuine, actionable failure (`platform-ops/cosign-public-key`, already an open backlog item),
discards it, and reports `unknown` on the strength of a cluster that does not exist.

Two compounding bugs in that selector:

- `len(entries) != 2` hard-codes the unprefixed pair's arity; with hub rows present the real
  count is 4.
- `any(item.get("ok") is None …) → unknown` **contradicts the tri-state contract** established in
  `docs/bugs/2026-07-17-status-health-absent-vs-fail.md`, which states: *"`None` → not deployed /
  not installed → neutral; NOT a failure"* and *"`all_ok` and every gate treat `None` as passing:
  only `ok is False` counts against them."* Every other consumer honours that. The sensor alone
  treats a neutral record as poisoning the whole verdict, so one legitimately-absent resource
  blinds it to every other record in the payload.

### D4 — the hub-ESO test suite tests dead code, which is why D1–D3 stayed green

`bin/k3dm-webhook:70` imports the live implementation:

```python
from webhook.smoke import (  # noqa: E402
    _smoke_test_services,
    configure_runtime as _configure_smoke_runtime,
)
```

`bin/k3dm-webhook` **also** defines its own `_kubectl_absent` (line 1381) and
`_eso_health_results` (line 1392). Those are unreachable duplicates: the only callers of that
file's `_kubectl_absent` are lines 1403 and 1420, both inside its own dead
`_eso_health_results`, and nothing calls that.

`scripts/tests/lib/webhook_hub_eso.bats` loads `bin/k3dm-webhook` with `SourceFileLoader` and
asserts against `webhook._eso_health_results` — which resolves to the **dead duplicate**. Tests
1–3 have been exercising unreachable code and passing, while the live `scripts/lib/webhook/smoke.py`
path they were written to protect had no coverage at all. (Test 4 is unaffected: it calls
`inspect.getsource(webhook._smoke_test_services)`, and that name *is* the import, so it reads
smoke.py's source.)

This is why a duplicate is worse than untested code — it absorbs the fix and keeps the gate green.

---

## Fix

### S1 — `scripts/lib/webhook/smoke.py`: never classify a kubeconfig failure as absence

Immediately **above** `def _kubectl_absent(output):`, insert:

```python
_KUBECTL_CONFIG_ERROR_SIGNATURES = (
    "error in configuration",
    "context was not found",
    "no configuration has been provided",
    "error loading config file",
    "unable to read client-cert",
    "unable to read client-key",
    "the connection to the server",
)


def _kubectl_config_error(output):
    """True when kubectl never reached a cluster (bad or missing context, unreadable
    kubeconfig, unreachable API server) as opposed to reporting on a resource.

    Absence is a claim about a cluster that WAS queried. A kubeconfig error means the
    resource's existence is unknown, so it must not be reported as 'not installed' —
    note that 'context was not found for specified context: X' contains the substring
    'not found' and would otherwise match _kubectl_absent()."""
    if not output or not output.strip():
        return False
    _low = output.lower()
    return any(sig in _low for sig in _KUBECTL_CONFIG_ERROR_SIGNATURES)
```

Then, in `_kubectl_absent`, insert the guard as the first statement after the empty-output check.

**Exact old block:**

```python
    if not output or not output.strip():
        return False
    _low = output.lower()
    return any(sig in _low for sig in (
        "notfound",
```

**Exact new block:**

```python
    if not output or not output.strip():
        return False
    if _kubectl_config_error(output):
        return False
    _low = output.lower()
    return any(sig in _low for sig in (
        "notfound",
```

Apply this to the `_kubectl_absent` in `scripts/lib/webhook/smoke.py` only. Do not add a second
copy anywhere.

### S2 — `scripts/lib/webhook/smoke.py`: report an unusable context distinguishably

In `_eso_health_results`, both `try` blocks currently go straight from the timeout check to
`_kubectl_absent`. Add a config-error branch **before** each `_kubectl_absent` call so the detail
names the real problem instead of claiming the resource is missing.

**Exact old block (first `try`):**

```python
        if _css_timeout:
            raise RuntimeError("kubectl clustersecretstore timed out")
        if _kubectl_absent(_css_out):
            results.append((css_name, None,
                            f"not installed (no ClusterSecretStore on {context})"))
```

**Exact new block:**

```python
        if _css_timeout:
            raise RuntimeError("kubectl clustersecretstore timed out")
        if _kubectl_config_error(_css_out):
            results.append((css_name, None,
                            f"cluster unreachable (kube context '{context}' unusable)"))
        elif _kubectl_absent(_css_out):
            results.append((css_name, None,
                            f"not installed (no ClusterSecretStore on {context})"))
```

**Exact old block (second `try`):**

```python
        if _es_timeout:
            raise RuntimeError("kubectl externalsecret timed out")
        if _kubectl_absent(_es_out):
            results.append((es_name, None,
                            f"not installed (no ExternalSecret CRD on {context})"))
            _es_data = None
```

**Exact new block:**

```python
        if _es_timeout:
            raise RuntimeError("kubectl externalsecret timed out")
        if _kubectl_config_error(_es_out):
            results.append((es_name, None,
                            f"cluster unreachable (kube context '{context}' unusable)"))
            _es_data = None
        elif _kubectl_absent(_es_out):
            results.append((es_name, None,
                            f"not installed (no ExternalSecret CRD on {context})"))
            _es_data = None
```

Both stay `None` (neutral), per the tri-state contract — an app cluster that is not provisioned is
not a failure. Only the detail text changes, so the operator can tell "I did not look" from
"I looked and it is not there".

### S3 — `scripts/lib/hermes/sensors.py`: grade every ESO row, ignore neutral ones

**Exact old block:**

```python
        services = _webhook_services(fetch, token, provider)["services"]
        entries = [item for item in services if item.get("name") in
                   ("ESO ClusterSecretStore", "ESO ExternalSecrets")]
        if len(entries) != 2 or any(item.get("ok") is None for item in entries):
            return record("eso", "unknown", "ESO status source unavailable")
        failed = [item for item in entries if item.get("ok") is False]
```

**Exact new block:**

```python
        services = _webhook_services(fetch, token, provider)["services"]
        entries = [item for item in services
                   if isinstance(item.get("name"), str)
                   and item["name"].endswith(("ESO ClusterSecretStore", "ESO ExternalSecrets"))]
        graded = [item for item in entries if item.get("ok") is not None]
        if not graded:
            return record("eso", "unknown", "ESO status source unavailable")
        failed = [item for item in graded if item.get("ok") is False]
```

Then, in the same function, the two remaining references to `entries` in the healthy path must
read `graded` instead.

**Exact old block:**

```python
        _debounced("eso", False, threshold, state)
        return record("eso", "healthy", "; ".join(item.get("detail", item["name"]) for item in entries))
```

**Exact new block:**

```python
        _debounced("eso", False, threshold, state)
        return record("eso", "healthy", "; ".join(item.get("detail", item["name"]) for item in graded))
```

Three behaviour changes, all deliberate:

1. `endswith` matches the `Hub ` prefix (and any future prefix) instead of the unprefixed pair only.
2. The `len(entries) != 2` arity gate is gone — with hub rows the real count is 4, and hard-coding
   2 is what made the count fragile in the first place.
3. Neutral (`ok is None`) rows are **skipped**, not fatal, which aligns the sensor with the
   tri-state contract every other consumer already honours. `unknown` now means what it should:
   *no ESO row in the payload could be graded at all.*

With the live payload this yields `degraded` on `1/8 not synced: cosign-public-key` after the
debounce threshold, instead of `unknown`.

### S4 — `bin/k3dm-webhook`: delete the dead duplicates

Delete both `def _kubectl_absent(output):` (line ~1381) and `def _eso_health_results(context, label_prefix=""):`
(line ~1392) from `bin/k3dm-webhook`, including their bodies, leaving the surrounding blank-line
spacing tidy. They are unreachable (see D4) and they silently absorbed this fix's test coverage.

**Before deleting, prove they are dead** and paste the output:

```bash
command grep -n '_eso_health_results\|_kubectl_absent' bin/k3dm-webhook
```

Every hit must be either the two `def` lines or a line inside the body of that file's own
`_eso_health_results`. If any other call site exists, **stop and report** — do not delete, and do
not invent a workaround.

Do not touch the module-level docstring above them, and do not remove the `_smoke_test_services`
import at line 70.

### S5 — retarget `scripts/tests/lib/webhook_hub_eso.bats` at the live module

Tests 1–3 currently load `bin/k3dm-webhook` via `SourceFileLoader` and call
`webhook._eso_health_results`, which after S4 no longer exists there — and which was the dead copy
before S4. Rewrite those three to import the live module instead:

```python
import sys
sys.path.insert(0, os.path.join(os.environ["REPO_ROOT"], "scripts", "lib"))
from webhook import smoke
```

Pass `REPO_ROOT="${repo_root}"` in the `run env …` line alongside the existing variables. Keep each
test's existing fake-`_posix_spawn_capture` monkeypatch approach and its existing assertions,
retargeted from `webhook._eso_health_results` to `smoke._eso_health_results` and
`smoke._posix_spawn_capture`. Test 4 (`inspect.getsource(webhook._smoke_test_services)`) already
reads smoke.py's source through the import — leave it as it is.

Then **add two new tests** to the same file:

5. **A kubeconfig error is not reported as "not installed".** Fake both kubectl calls returning
   `("Error in configuration: context was not found for specified context: ubuntu-k3s", False)`.
   Assert, for `smoke._eso_health_results("ubuntu-k3s")`:
   - both `ok` values are `None`;
   - both details contain `cluster unreachable`;
   - **neither detail contains `not installed`** — this is the regression guard for D1.
6. **A genuinely absent CRD still reports "not installed".** Fake
   `('error: the server doesn\'t have a resource type "externalsecret"', False)` for the
   externalsecret call and valid `Ready=True` JSON for the ClusterSecretStore call. Assert the
   ExternalSecrets row is `ok is None` with a detail containing `not installed`, proving S1's guard
   did not swallow the legitimate absence case.

Do not use a bare `!` or a whole-line `grep -F` in any assertion.

### S6 — `scripts/tests/hermes/test_hermes.py`: update the contract, add the regression

`test_eso_healthy_degraded_unknown_and_debounce` currently asserts the **old** contract:

```python
    unknown = health([{"name": "ESO ClusterSecretStore", "ok": None, "detail": "absent"},
                      {"name": "ESO ExternalSecrets", "ok": True, "detail": "ok"}])
    assert eso(webhook(unknown), {}, token="x")["status"] == "unknown"
```

That expectation is **intentionally reversed by S3** — one neutral row alongside one gradeable
healthy row is now `healthy`, not `unknown`. Change that assertion to `== "healthy"` and add a
comment naming this bug doc so the next reader does not "restore" it. Keep every other assertion
in the test unchanged.

Then add a new test, `test_eso_grades_hub_rows_and_ignores_unreachable_app_cluster`, reproducing
the live payload exactly:

```python
def test_eso_grades_hub_rows_and_ignores_unreachable_app_cluster():
    payload = health([
        {"name": "ESO ClusterSecretStore", "ok": None,
         "detail": "cluster unreachable (kube context 'ubuntu-k3s' unusable)"},
        {"name": "ESO ExternalSecrets", "ok": None,
         "detail": "cluster unreachable (kube context 'ubuntu-k3s' unusable)"},
        {"name": "Hub ESO ClusterSecretStore", "ok": True, "detail": "Ready=True"},
        {"name": "Hub ESO ExternalSecrets", "ok": False,
         "detail": "1/8 not synced: cosign-public-key"},
    ])
    state = {}
    statuses = [eso(webhook(payload), state, token="x")["status"] for _ in range(3)]
    assert statuses == ["healthy", "healthy", "degraded"]
    final = eso(webhook(payload), state, token="x")
    assert_normalized(final, "eso")
    assert final["status"] == "degraded"
    assert "cosign-public-key" in final["evidence"]
```

Add a second new test asserting `unknown` survives when it should — a payload whose only ESO rows
are all `ok is None` must still return `unknown`, so S3 did not simply delete the unknown path.

### S7 — docs

In `docs/guides/hermes.md`, in the section describing the `eso` sensor, state that the sensor
grades **every** row whose name ends in `ESO ClusterSecretStore` or `ESO ExternalSecrets`,
including the `Hub ` -prefixed pair; that neutral (`ok: null`) rows are skipped rather than
treated as `unknown`; and that `unknown` therefore means no ESO row could be graded at all. Add a
short troubleshooting note headed **"`eso` says `unknown` — check the kube context before the
credential."**, giving the `PYTHONPATH=scripts/lib python3` reproduction from this doc.

In `CHANGELOG.md`, under `## [Unreleased]` → `### Fixed`, add a bullet explaining the defect class
in prose: a kubeconfig error whose text contains `not found` was classified as resource absence,
which made every ESO row neutral and the Hermes `eso` sensor permanently `unknown`, while the
`Hub ESO *` rows it never read carried a real unsynced-ExternalSecret finding.

---

## Rules

- `python3 -m py_compile scripts/lib/webhook/smoke.py scripts/lib/hermes/sensors.py bin/k3dm-webhook` → exit 0.
- `bats scripts/tests/lib/webhook_hub_eso.bats scripts/tests/lib/webhook.bats` → all pass; paste the summary.
- `pytest -q scripts/tests/hermes` → all pass; paste the summary. Invoke `pytest` bare.
- Disappearance gate: `command grep -c '_eso_health_results' bin/k3dm-webhook` → `0`.
- Disappearance gate: `command grep -c 'len(entries) != 2' scripts/lib/hermes/sensors.py` → `0`.
- Presence gate: `command grep -c 'def _kubectl_config_error' scripts/lib/webhook/smoke.py` → `1`.
- **Mutation-test both new guards and paste the failing output.** Revert S1's
  `if _kubectl_config_error(output): return False` guard → the new bats test 5 must fail. Revert
  S3's `endswith` back to the exact-match tuple → the new hub test in `test_hermes.py` must fail.
  Restore the tree afterwards and re-confirm green. A new test that has never been observed to
  fail has not been shown to test anything.
- No new third-party imports. Do not change `_posix_spawn_capture`, `_spawn_capture_text`,
  `_resolve_provider`, or `_provider_context`.
- Double-quote all shell variable expansions. LF endings only. No inline comments in shell blocks.

---

## Definition of Done

- [ ] S1–S7 applied; `git diff --stat` lists only the six files named at the top of this doc.
- [ ] `py_compile` clean on all three Python targets.
- [ ] `bats scripts/tests/lib/webhook_hub_eso.bats scripts/tests/lib/webhook.bats` green (summary pasted).
- [ ] `pytest -q scripts/tests/hermes` green (summary pasted).
- [ ] All four grep gates pass (output pasted).
- [ ] Both mutation tests demonstrated failing, then the tree restored and re-confirmed green
      (output pasted for each).
- [ ] S4's dead-code proof pasted before the deletion.
- [ ] Committed and pushed to `k3d-manager-v1.40.0`; `git rev-parse origin/k3d-manager-v1.40.0`
      matches the commit.
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with the SHA and status.

**Commit message (exact):**

```
fix(hermes): grade every ESO row and stop reading a kubeconfig error as absence
```

---

## Out of scope — do NOT change (Claude escalates these to the operator)

- **`_provider_context()`'s `ubuntu-k3s` default** (`bin/k3dm-webhook:154-161`). `_resolve_provider`
  defaults to `k3s-aws` and `_provider_context`'s `.get(provider, "ubuntu-k3s")` defaults there
  too, so with no `active-provider` file there is no way to resolve a context that exists in this
  kubeconfig. That is a real defect, but changing the default provider affects every webhook
  consumer and is the operator's decision, not this fix's.
- **Threading the exit code through `_posix_spawn_capture`** (D2). The correct long-term fix, and a
  wider change than this bug needs.
- The `platform-ops/cosign-public-key` ExternalSecret itself — this fix makes Hermes *report* it;
  repairing it is separate and operator-owned.

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT modify any file outside the six listed targets.
- Do NOT run `kubectl`, `make restart-webhook`, `launchctl`, or anything that touches a live
  cluster, the webhook process, or the Hermes agent. This is a pure code + test change.
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/` — they are subtrees.
- Do NOT "restore" the `test_hermes.py` assertion S6 deliberately inverts.
- Do NOT make the `0/0 synced` ExternalSecrets case neutral — it stays `ok is True`.
- Do NOT add `Hub ESO *` rows to either triage `ns_map` in `bin/k3dm-webhook`; those maps query the
  app context, which is the wrong cluster for hub rows.
