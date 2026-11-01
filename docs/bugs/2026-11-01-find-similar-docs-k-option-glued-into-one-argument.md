# Bug: `make find-similar-docs K=<n>` fails with "unrecognized arguments: --k10--"

**Status:** FIXED
**Priority:** P2
**Severity:** low — any `K=` value breaks the target from Slack and from the shell; workaround is to drop `K` (default 5)
**Approval:** operator, 2026-11-01 (posted the failing Slack job; Claude fixed it directly as a one-line change)
**Filed:** 2026-11-01
**Detected by:** operator, Slack `/k3dm find-similar-docs K=10 Q="rotator not redeployed by release"` (M5 webhook job `87e69e3f`)
**Affected:** `Makefile` (`find-similar-docs`)
**Branch:** `k3d-manager-v1.43.13`
**Related:** `docs/bugs/2026-10-24-find-similar-docs-make-target-ignores-q.md` (same recipe, Q handling)

## Observed failure

    usage: find-similar-docs.py [-h] [--k K] [--json] [query ...]
    find-similar-docs.py: error: unrecognized arguments: --k10--
    make: *** [find-similar-docs] Error 2

## Root cause

The recipe built the argv list inside `python3 -c` as
`[..., $(if $(K),"--k",) $(if $(K),"$(K)",) "--", q]`. With `K=10` that expands to `"--k" "10" "--"` with no commas,
and Python joins adjacent string literals into the single argument `"--k10--"`. The target has never worked with `K`.

## Fix

`K` is passed to the inline script as `sys.argv[2]` and added as two list items only when non-empty:
`[sys.executable, "scripts/find-similar-docs.py"] + (["--k", sys.argv[2]] if sys.argv[2] else []) + ["--", q]`.
The relay still validates `K` against `[1-9]|[1-4][0-9]|50` (`scripts/lib/webhook/make_targets.py`).

## Files

- `Makefile`
- `scripts/tests/bin/test_find_similar_docs_make_target.py`

## Acceptance

```yaml
must:
  M1: make find-similar-docs Q="<q>" K=<n> passes --k and <n> as two separate arguments before -- and the query
  M2: the relay form (Q_B64 plus K) passes the decoded query with --k <n>
must_not:
  N1: without K, no --k argument is passed (paired with M1)
evidence:
  E1:
    proves: [M1, M2, N1]
    kind: offline
    intent: >-
      You will see pytest copy the real Makefile into a tmp repo with a stub scripts/find-similar-docs.py that prints
      its argv (the test first asserts the tmp root is not the real repo), then run the target with Q and K=10, with Q
      only, and with Q_B64 and K=5. Pre-fix, the two K cases printed ['--k10--', ...] and ['--k5--', ...].
    what: pytest scripts/tests/bin/test_find_similar_docs_make_target.py
  E2:
    proves: [M1]
    kind: live
    intent: You will see Slack /k3dm find-similar-docs K=10 Q="..." on the M5 return results instead of a usage error.
    what: operator in Slack, after the M5 checkout is at the fix commit
interface:
  - make find-similar-docs Q= K= Q_B64=
```

## Resolution

- E1: the new suite failed 2 of 3 on the pre-fix Makefile (`['--k10--', 'rotator not redeployed']`,
  `['--k5--', "what's recent e2e issues"]`) and passes 3/3 after the fix. `test_find_similar_docs.py`,
  `webhook_make_targets.py` and `test_webhook_thread_dispatch.py` stay green (104 passed, 1 skipped).
- `make find-similar-docs Q=... K=3` on the M4 now gets past argument parsing.
