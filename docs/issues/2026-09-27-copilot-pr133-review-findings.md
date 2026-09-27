# PR #133 review findings — v1.39.0

**PR:** [#133](https://github.com/wilddog64/k3d-manager/pull/133) — `k3d-manager-v1.39.0` → `main`
**Date:** 2026-09-27
**Reviewers:** GitHub Advanced Security (CodeQL), CI

Two findings: one real CI red that the run summary misreported, and one CodeQL
false positive resolved by rename rather than dismissal.

---

## Finding 1 — 12 BATS failures: `rg` does not exist on the CI runner

**Where:** `scripts/tests/plugins/argocd_vectordb.bats` (19 invocations)
**Job:** `lint` → "Run the full offline suite (BATS + Python)" → `make: *** [Makefile:788: test] Error 1`

`argocd_vectordb.bats` asserted against the repo's own YAML with `run rg …`.
`ripgrep` is not installed on `ubuntu-latest`, so every one of those calls exited
**127** and 12 of the file's 16 tests failed.

**Why it passed locally and not in CI.** In this operator's interactive shell `grep`
is aliased to `rg`, so `rg` resolves. `bats` runs under bash and never expands that
alias — but the tests did not call `grep`, they called `rg` *by name*, which the
local machine happens to have installed and the runner does not. The suite was
therefore green locally and red in CI for reasons the local run could not surface.

**This is a recurrence.** The PR #131 findings record the same root cause from the
opposite direction: a `! rg` guard returned 0 when `rg` was absent, making a gate
*vacuously pass*. That was fixed by rewriting to `grep -nE`. Six days later a new
test file reintroduced `rg`. The lesson generalises past the one guard: **`rg` is
not available to any test that has to run in CI.**

### Fix

All 19 invocations converted to POSIX `grep`, preserving each assertion's meaning:

| rg form | grep form | why |
|---|---|---|
| `rg -n <re> <file>` | `grep -nE` | `rg` is ERE-ish by default; `grep` needs `-E` for `(…)` and `\|` |
| `rg -n <re> <dir>` | `grep -rnE` | `rg` recurses into directories implicitly; `grep` needs `-r` |
| `rg -nF <lit>` | `grep -nF` | unchanged semantics |
| `rg -c <re>` | `grep -cE` | unchanged semantics |
| `[^\n]*` | `.*` | `grep` is line-based; `[^\n]` is not a `grep` escape |

**Verification.** 16/16 pass. The negative-only guard (test 3, "defines no Role,
RoleBinding, or ClusterRole") was **mutation-tested** — appending `kind: Role` to
`statefulset.yaml` turns it red, and the file was restored byte-identical
(`cmp`). This matters because a converted *absence* assertion is exactly the shape
that can pass for the wrong reason: if `grep -r` silently failed to read the
directory it would also return 1. The positive `grep -rnE` assertions in tests 2
and 4 read that same directory successfully, which is the control proving `-r`
resolves the path.

---

## Finding 2 — CodeQL `py/clear-text-logging-sensitive-data` (alert 30, high)

**Where:** `bin/k3dm-vectordb-status:96`
**Message:** "This expression logs sensitive data (secret) as clear text."

The flagged expression is the probe's only output:

```python
print(json.dumps(status(offline=args.offline), sort_keys=True))
```

**This is a false positive, and the classification says why.** CodeQL reports the
category as `(secret)` — it selected the source by **identifier name**, not by
value. The names it matched were `EXTERNAL_SECRET`, the local `external_secret`
holding a `kubectl get externalsecret -o json` payload, and the local
`external_secret_synced`. Every one of those carries a `_condition_status()`
result, which is `True`, `False` or `None` — a boolean readiness fact. No
credential is in scope: an `ExternalSecret` custom resource describes *where* a
value comes from and never contains the value, and the probe reads only
`.status.conditions[].status`.

### Fix — rename, not dismiss

Per the standing rule that renaming beats dismissing a name-matched CodeQL alert,
the sensitive-looking identifiers were renamed so no name-tainted value reaches
`print`:

| before | after |
|---|---|
| `EXTERNAL_SECRET` | `EXTERNAL_BINDING` |
| `external_secret` (local) | `binding` |
| `external_secret_synced` (local) | `binding_synced` |

**The output key `"external_secret_synced"` is deliberately unchanged.** It is a
published contract, read by `scripts/lib/hermes/sensors.py:262-270`, by
`bin/k3dm-vectordb-metrics`, by the emitted
`k3dm_vectordb_external_secret_synced` gauge, and by six assertions in
`scripts/tests/hermes/test_vectordb_sensor.py`. Renaming it to satisfy a static
analyser would break live dashboards to silence a finding about a boolean. Only
the variables were renamed; the JSON shape is byte-identical.

**Verification.** `python3 -m py_compile` clean; `--offline` emits all six keys
with `external_secret_synced` present; 19/19 pytest pass.

If the alert survives the rename, the remaining source can only be the dict key
literal itself, at which point dismissal-with-marker is the correct answer rather
than deforming the contract — but that is a decision to take on evidence from the
next scan, not pre-emptively.

---

## Process note

Finding 1 was **misreported by the agent that collected it**: the Phase 1 run
summary stated "all 1165 BATS tests passed with zero `not ok`" and attributed the
`exit code 2` to the BW01 warnings that accompany a 127. The log contains 12
`not ok` lines. The BW01 warning text is loud and appears at the end of the
output, directly above the `Error 1`, which makes it easy to read the warnings as
the cause and the failures as absent. The standing "verify any agent report before
trusting it" rule is what caught this — the check that did it was
`gh run view <id> --log-failed | grep -c 'not ok'`, not re-reading the summary.

**Rule to add:** a test-suite report claiming green must be substantiated by a
`not ok` count of zero from the log, never by the absence of failures in a
summary. And: no test that runs in CI may invoke `rg`.
