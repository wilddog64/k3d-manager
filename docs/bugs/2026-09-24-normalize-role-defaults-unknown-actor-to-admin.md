# Bug: `_normalize_role` defaults an unknown role to admin, on both sides of `_role_allows`

**Branch:** `k3d-manager-v1.37.0`
**Filed:** 2026-09-24 by Claude, from a finding Codex surfaced and stopped on during webhook Phase 3
**Status:** OPEN — root cause confirmed by trace; **not currently exploitable**; fix specced below, not applied
**Component:** `scripts/lib/webhook/policy.py` (moved there by Phase 1, `b6c8a141`)

## The defect

```python
def _normalize_role(role):
    role = (role or "").strip().lower()
    return role if role in _ROLE_LEVELS else _ROLE_DEFAULT      # _ROLE_DEFAULT == "admin"


def _role_allows(actual_role, required_role):
    return _ROLE_LEVELS[_normalize_role(actual_role)] >= _ROLE_LEVELS[_normalize_role(required_role)]
```

`_normalize_role` is applied to **both** arguments, but the safe default is **opposite** for each:

| Argument | Meaning | Unknown → admin is… |
|---|---|---|
| `required_role` | what the action demands | **correct** — most restrictive, fail-safe |
| `actual_role` | what the caller holds | **wrong** — most permissive, fail-open |

One function, two contradictory semantics. The `required_role` behaviour is load-bearing and must be
kept: Phase 1b's `strictest_role()` (`57ac113d`) deliberately relies on an empty/unknown requirement
resolving to `admin` so that an unspecified requirement can never mean "unchecked".

## Observed effect

Measured on `_fix_mode_enabled(question, role)` — the gate that decides whether an AI agent may
**mutate the cluster** — with a fix-intent question:

```
reader      False
operator    True
admin       True
""          True     <-- empty role granted fix mode
"nonsense"  True     <-- unrecognised role granted fix mode
```

## Why it is NOT currently exploitable

Every path that reaches a role check sanitizes first. Traced end to end:

| Entry point | Resolver | Unknown/invalid input becomes |
|---|---|---|
| `/api/v1/ask` → `_run_cluster_ask(role=request_role)` (`bin/k3dm-webhook:3331`) | `_request_role` | header present but invalid → `"reader"` (explicit fail-closed) |
| `/slack/events` thread → `_handle_thread_command(role=slack_role)` (`:2978`, `:2990`, `:3003`) | `_slack_user_role` (`webhook/auth.py:98`) | unmapped user → `"reader"` (docstring: "Unknown → reader (fail closed)") |
| `/api/v1/make` | `_effective_make_role` | caps at the caller's mapped Slack role; unknown → `"reader"` |

A missing `X-K3DM-Role` header resolving to `admin` is **intentional and documented** —
`_request_role` treats a bare bearer token as the admin credential. That is a different decision and
is not in scope here.

So `actual_role` is always one of `reader|operator|admin` at every call site today. The fail-open
branch is unreachable.

## Why it still needs fixing

The gate's safety currently depends on **every caller remembering to sanitize**, which is exactly the
property that does not survive maintenance. This is the same shape as two defects already found in
this release:

- Phase 1's route table declared a `min_role` that nothing read — safety that looked present but was
  inert (`docs/plans/v1.37.0-webhook-server-decomposition.md`, Phase 1b).
- The ACG preflight inferred Path B from a directory's existence, making its hard error unreachable
  because that directory always exists.

In both cases the code was defensible line by line and wrong as a system. A new caller that passes a
raw string — from a job file, a queue payload, a future route — silently gets admin. Nothing fails,
nothing logs, and the AI agent becomes write-capable.

## Fix (proposed, NOT applied)

Split the two meanings. Keep `_normalize_role` as the **requirement** normalizer (unknown → admin,
fail-safe, relied on by `strictest_role`) and add a subject normalizer that fails closed:

```python
def _normalize_actor_role(role):
    """Normalize a CALLER's role. Unknown fails CLOSED to reader, unlike a requirement."""
    role = (role or "").strip().lower()
    return role if role in _ROLE_LEVELS else "reader"


def _role_allows(actual_role, required_role):
    return _ROLE_LEVELS[_normalize_actor_role(actual_role)] >= _ROLE_LEVELS[_normalize_role(required_role)]
```

Do **not** change `_normalize_role` itself, and do **not** make both sides fail closed — an unknown
*requirement* resolving to `reader` would mean "anyone may do it", which reintroduces the fail-open
authorization hole Phase 1b closed.

### Blast radius to check before applying

`_role_allows` is called from the route enforcement path, `_handle_thread_command`,
`_effective_make_role` and `make_target_help`. Because every caller already passes a sanitized
`actual_role`, the fix should be **behaviour-neutral for all current callers** — assert that rather
than assume it. `make_target_help(role, _role_allows)` is the one to watch: it filters the Slack help
listing by role, so a change there would alter what users see.

### Tests

1. `_normalize_actor_role` — `""`, `"nonsense"`, `None`, `"ADMIN"`, `" operator "` → assert each,
   with unknown values yielding `reader`.
2. `_role_allows` asymmetry, as literals: `("nonsense", "operator")` → **False** (actor fails closed)
   while `("reader", "nonsense")` → **False** (requirement fails safe). Both directions in one test
   is the whole point.
3. `_fix_mode_enabled` matrix including `""` and `"nonsense"` → **False**. This is the row that is
   `True` today.
4. An existing-behaviour guard: every current caller's `(actual, required)` pair still returns what it
   returns today. Enumerate them rather than sampling.

### Mutations

- Make `_normalize_actor_role` default to `_ROLE_DEFAULT` → test 1 and test 3 red.
- Apply `_normalize_actor_role` to the `required_role` side as well → test 2's second case red.
- Revert `_role_allows` to the symmetric form → test 3 red.

## Out of scope

- The intentional missing-header → admin behaviour in `_request_role`.
- `_ROLE_DEFAULT` itself, which `strictest_role` needs.
- Webhook Phase 3, which is a behaviour-neutral extraction and must not carry this change. Phase 3
  pins the **observed** matrix with a comment pointing here; this bug changes it afterwards, and the
  Phase 3 test is updated in the same commit as the fix.
