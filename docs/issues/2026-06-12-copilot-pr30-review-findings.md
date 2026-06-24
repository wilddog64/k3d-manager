# Copilot PR #30 Review Findings — cluster-provider hook stdout leak

**Date:** 2026-06-12
**PR:** [#30](https://github.com/wilddog64/lib-foundation/pull/30) — `feat(core): extensible cluster-provider validation via optional consumer hook`
**Fix commit:** `8de372f`

---

## Finding 1 — `scripts/lib/core.sh:25` (`_cluster_provider`)

Copilot: calling the consumer hook in the `if` condition can leak hook stdout into
`_cluster_provider`'s output, which is contractually exactly the provider string. A consumer
whose `_cluster_provider_is_extra_supported` does any `echo`/debug logging would corrupt the
captured provider value.

## Finding 2 — `scripts/lib/core.sh:792` (deploy-cluster validation path)

Same root cause on the second `case` block — the predicate was invoked without suppressing
its stdout, so hook output could end up in `deploy_cluster` output/logs.

---

## Root cause

The hook `_cluster_provider_is_extra_supported` is a **predicate** (exit-status only), but it
was called bare in the `&&` condition. `_cluster_provider` emits the resolved provider on
stdout via `printf`; any stdout a consumer hook produces would interleave with — and corrupt —
that value when callers capture it via `$(...)`.

## Fix applied

Redirect the predicate call to `>/dev/null` at both `case` sites (stderr preserved so genuine
errors stay visible):

**Before:**
```bash
   && _cluster_provider_is_extra_supported "$provider"; then
```

**After:**
```bash
   && _cluster_provider_is_extra_supported "$provider" >/dev/null; then
```

Added regression test `_cluster_provider: noisy consumer hook does not corrupt provider output`
— a hook that `echo`es debug noise but returns 0 must still yield exactly `k3s-foo`. Suite is
21/21 green; `shellcheck -S warning` clean.

---

## Process note

When adding an **optional consumer hook** to a function whose stdout is a contract (the return
value), always invoke the hook as a pure predicate with stdout redirected. Add this to the hook
spec template: *"predicate hooks must be called with `>/dev/null` so consumer output cannot
corrupt the host function's stdout."*
