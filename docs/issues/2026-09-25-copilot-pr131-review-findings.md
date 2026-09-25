# PR #131 review findings — two gates that could not fail

**Date:** 2026-09-25
**PR:** [#131](https://github.com/wilddog64/k3d-manager/pull/131) — `feat: v1.37.0 — webhook decomposition and gates that prove their claim`
**Reviewer:** Copilot
**Findings:** 2 (both accepted, both fixed)

Both findings are the same class of defect the v1.37.0 milestone exists to eliminate: a test
that reports green without exercising what it claims to cover. Neither was a false positive.

---

## Finding 1 — `rg`-based disappearance gate is vacuously green

**File:** `scripts/tests/lib/hostinger_pushgateway_port_forward.bats:19`

The guard asserting that no producer still names the bare `pushgateway` service was written as
a negated `rg` invocation:

```bash
run bash -c "! rg -n --pcre2 'get svc pushgateway|svc/pushgateway(?![[:alnum:]_-])|helm upgrade --install pushgateway(?![[:alnum:]_-])' '${hostinger}' '${cluster_up}' '${observability}'"
[ "${status}" -eq 0 ]
```

`!` inverts *any* non-zero exit, not just "no matches found". Two environments pass without
checking anything:

| Condition | `rg` exit | after `!` | verdict |
|---|---|---|---|
| no matches (intended pass) | 1 | 0 | pass |
| matches found (intended fail) | 0 | 1 | fail |
| `rg` not installed | 127 | 0 | **vacuous pass** |
| `rg` built without PCRE2 | 2 | 0 | **vacuous pass** |

`rg` is a Homebrew package on the operator's laptop and is not installed by the CI workflow,
so the two vacuous rows are not hypothetical.

**Fix** — `grep -nE`, which is POSIX and assumed present, with an exact status assertion:

```bash
run grep -nE 'get svc pushgateway([^[:alnum:]_-]|$)|svc/pushgateway([^[:alnum:]_-]|$)|helm upgrade --install pushgateway([^[:alnum:]_-]|$)' "${hostinger}" "${cluster_up}" "${observability}"
[ "${status}" -eq 1 ]
[ -z "${output}" ]
```

`grep` exits `1` only for "no lines selected" and `2` for any error, so asserting `-eq 1`
rejects a missing binary, an unreadable file and a bad pattern — all of which the old form
silently accepted. The PCRE2 negative lookahead `(?![[:alnum:]_-])` has no ERE equivalent, so
it becomes a consuming alternation `([^[:alnum:]_-]|$)`; the `|$` arm is what preserves the
end-of-line match the lookahead gave for free.

---

## Finding 2 — Alertmanager route tests depend on PyYAML

**File:** `scripts/tests/plugins/e2e_observability.bats:225,230`

Both new Alertmanager route tests parsed the template with `python3 -c 'import yaml'`. PyYAML
is not a declared dependency of this repo's test environment — `scripts/tests/plugins/argocd.bats:389`
already guards it (`if command -v python3 && python3 -c 'import yaml'`), which is the repo's own
evidence that it cannot be assumed. Where PyYAML is absent the tests raise `ModuleNotFoundError`
and fail **even when the template is correct**: a false red rather than a false green, but still
a gate that does not measure what it names.

**Fix** — `yq`, which four other suites (`prometheus_port_split`, `signing`,
`grafana_dashboard_appsets`, `alertmanager_config_secret`) already invoke unguarded, so it is the
established assumption:

```bash
@test "Alertmanager has a non-null severity warning route" {
  run yq -r '.route.routes[] | select(.matchers[] == "severity = warning") | .receiver' "${AM_TMPL}"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
  [ "${output}" != "null" ]
}
```

The `[ -n "${output}" ]` line matters: a `select` that matches nothing exits `0` with empty
output, so without it the test would go vacuously green if the warning route were deleted
outright rather than merely repointed at `null`.

The ordering test resolves both route indices and range-checks them before comparing, because
`[ "${warning}" -gt "${allow}" ]` on an empty string is a `bash` syntax error, not a failure:

```bash
[[ "${allow}" =~ ^[0-9]+$ ]]
[[ "${warning}" =~ ^[0-9]+$ ]]
[ "${warning}" -gt "${allow}" ]
```

The template path also moved into an `AM_TMPL` variable beside the other five at the top of the
file, rather than being repeated inline in each test.

---

## Verification

All three rewritten assertions were mutation-tested against the live tree — a test that has
never been observed failing has not been shown to work:

| Mutation | Expected failure | Result |
|---|---|---|
| append `# svc/pushgateway` to `observability.sh` | `no producer refers to the bare pushgateway service name` | failed ✅ |
| set the `severity = warning` route's receiver to `'null'` | `Alertmanager has a non-null severity warning route` | failed ✅ |
| swap the warning route ahead of the named allowlist | `Alertmanager warning catch-all follows the named allowlist` | failed ✅ |

Both suites restored and green afterwards: 20/20.

---

## Process note

The v1.37.0 theme is *gates that prove their claim*, and both findings landed inside that
milestone's own new tests. The generalisable rules:

- **Never assert a disappearance with `! <tool>`.** Invert on an exact status instead, so a
  missing tool or an unreadable file is a failure rather than a pass. `grep`'s `1`-vs-`2` split
  exists precisely for this.
- **A test may only depend on tooling something else in the suite already depends on
  unguarded.** PyYAML was guarded elsewhere in the repo — that guard was the signal not to take
  a hard dependency on it.
- **A `select`/filter query needs a non-empty assertion**, or deleting the thing under test
  passes.
