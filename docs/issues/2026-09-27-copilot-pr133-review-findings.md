# PR #133 review findings — v1.39.0

**PR:** [#133](https://github.com/wilddog64/k3d-manager/pull/133) — `k3d-manager-v1.39.0` → `main`
**Date:** 2026-09-27
**Reviewers:** GitHub Advanced Security (CodeQL), CI

Three findings: one real CI red that the run summary misreported, one CodeQL
false positive resolved by rename rather than dismissal, and one genuine defect
Copilot caught that this PR had itself introduced.

Copilot independently flagged the `rg` dependency of finding 1, from the
portability angle rather than the CI-failure angle.

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

**Confirmed by the next scan: alert 30 is now `fixed`.** Querying
`code-scanning/alerts?ref=refs/pull/133/head` after the rename reports state
`fixed` for `bin/k3dm-vectordb-status:96`. That settles the diagnosis — the source
was the identifier name and nothing else, since no value, control flow or output
shape changed. The contingency of a dismissal-with-marker, had the dict key
literal also been a source, was not needed.

---

## Finding 3 — the ACG rules apply swallowed failures, the defect this PR fixes elsewhere

**Where:** `scripts/plugins/observability.sh:735-738` (as reviewed), inside `_deploy_pushgateway_acg`
**Raised by:** Copilot

> This apply path swallows failures: if applying the ACG PrometheusRules directory
> fails, the function still continues and reports success (the `&& _info` only gates
> the log line). That recreates the "failed apply looked like success" defect that
> this PR fixes for the hub rules path.

This is correct and it is the most valuable finding of the three, because the PR
body advertises exactly this fix for the hub path while the branch introduced a
**new** instance of it for the app cluster:

```bash
_kubectl apply --context "${_app_context}" -f "${_acg_rules_dir}/" >/dev/null   && _info "[observability] app-cluster PrometheusRules applied from ${_acg_rules_dir}/"
```

`&&` gates only the log line, so a failed apply is indistinguishable from a
successful one: no error, no non-zero status, just a missing success message that
nobody is watching for.

**It is in scope, and that was checked rather than assumed.** `git show
main:scripts/plugins/observability.sh` has no `_acg_rules_dir` at all — the block
arrived on this branch in `22e9c53d`. The same `apply … >/dev/null && _info` shape
occurs 9 more times in this file (dashboards, promtail, the ArgoCD dashboard), but
all of those are pre-existing on `main`; fixing them here would be an unsolicited
refactor of code this release does not touch. Filed as backlog instead.

### Fix

```bash
local _acg_rules_failed=0
local _acg_rules_dir="${SCRIPT_DIR}/etc/prometheus/rules-acg"
if [[ -d "${_acg_rules_dir}" ]]; then
  if _kubectl apply --context "${_app_context}" -f "${_acg_rules_dir}/" >/dev/null; then
    _info "[observability] app-cluster PrometheusRules applied from ${_acg_rules_dir}/"
  else
    _err "[observability] Failed to apply app-cluster PrometheusRules from ${_acg_rules_dir}/"
    _acg_rules_failed=1
  fi
fi
_observability_apply_trivy_dashboard "${_app_context}"
return "${_acg_rules_failed}"
```

**Why a flag rather than a bare `return 1` at the failure site.** An early return
would skip `_observability_apply_trivy_dashboard`, which has nothing to do with
the rules apply — turning a reporting bug into a silent loss of unrelated work.
The flag makes the failure loud *and* the exit status honest while leaving the
sequence intact. Note this function has no `set -e` above it and its caller at
line 692 ignores the status, so the non-zero return is for the record and for
future callers; the `_err` line is what a human or a log scrape actually sees
today. There is deliberately no behaviour change to the pushgateway install above
it, which warns and returns 0 on purpose ("deployment metrics disabled").

**Verification.** New guard, `the ACG PrometheusRules apply cannot report success
on failure`, asserts the contract rather than a source line: the block contains
`_err`, does **not** contain `&& _info`, and the function returns the flag. It is
**mutation-tested** — reverting `observability.sh` to the pre-fix source turns it
red, and the file was restored byte-identical by `cmp`. 6/6 in
`observability_public_endpoint_probes.bats`; shellcheck `-S warning` clean on both
`HEAD` and `main`.

---

## Incidental — `deploy_observability` tripped the if-count audit

Committing the finding-3 fix was blocked by the `_agent_audit` pre-commit hook:

```
WARN: Agent audit: scripts/plugins/observability.sh exceeds if-count threshold in: deploy_observability:9
```

**This is not caused by the fix.** The threshold is 8
(`AGENT_AUDIT_MAX_IF`). Counting `if` statements per function across three
revisions: `main` has no offender, `HEAD` before this commit already reports
`deploy_observability: 9`, and the staged tree with the fix still reports 9 — the
count is unchanged. The function crossed the threshold earlier on this branch, in
`cc4d634b`, which added the per-file `if envsubst … then` loop to the hub rules
apply. The fix itself added an `if/else` to a *different* function
(`_deploy_pushgateway_acg`), which is well under the limit.

The hook only audits `.sh` files that are **staged**, which is why it surfaced
now: the first commit on this PR staged BATS, Python and Markdown, so
`observability.sh` was never presented to it.

Resolved with the mechanism the repo provides for exactly this — an entry in
`scripts/etc/agent/if-count-allowlist`, whose own header reads "Temporary
allowlist for functions pending refactors … See docs/issues entries for each
item" and which already carries eight such entries:

```
scripts/plugins/observability.sh:deploy_observability
```

**This is a deferral, not a fix, and it loosens a repo-wide quality gate by one
function.** The honest alternative is decomposing `deploy_observability`, which is
an unsolicited refactor of code already reviewed in this release and does not
belong in a review-response commit. Flagged for the operator: if the preference is
to refactor rather than allowlist, that is a follow-up, and this entry should be
removed when it lands.

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
