# Bug: the role code assumes every token role is in `_ROLE_LEVELS` — a third, unranked role would crash auth

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-28 by Claude (cloud session), from a review of `v1.41.0-cloud-bridge-e2e-dispatch.md`
**Status:** OPEN — latent. Unreachable today; becomes reachable the moment that spec's M1 lands.
**Component:** `scripts/lib/webhook/policy.py`, `scripts/lib/webhook/auth.py`, `bin/k3dm-webhook`
**Related:** `2026-09-24-normalize-role-defaults-unknown-actor-to-admin.md` (FIXED). Same family —
role handling that is correct only because every value happens to be one of three strings — but a
different site, and not a recurrence of that fix.

## The defect

`_resolve_token_role` (`auth.py:63`) returns only `"admin"`, `"reader"` or `None` today. Every
consumer of its result indexes `_ROLE_LEVELS` directly, with no membership check:

```python
# policy.py, _request_role
    if raw is None:
        role = token_role or _ROLE_DEFAULT            # "cloud-runner" passes straight through
    ...
    if token_role is not None and _ROLE_LEVELS[role] > _ROLE_LEVELS[token_role]:   # KeyError
        return token_role

# policy.py, _effective_make_role
    return header_role if _ROLE_LEVELS[header_role] <= _ROLE_LEVELS[user_role] else user_role  # KeyError
```

`v1.41.0-cloud-bridge-e2e-dispatch.md` M1-M2 add a third token that resolves to `"cloud-runner"`,
and M2 requires that `cloud-runner` is **not** added to `_ROLE_LEVELS` (so it cannot transitively
grant every lower target). Those two requirements together hit the lines above:

| Request with the cloud-runner token | Path | Result |
|---|---|---|
| no `X-K3DM-Role` header (the bridge sends none) | `role = token_role` → `_ROLE_LEVELS["cloud-runner"]` | `KeyError` |
| any `X-K3DM-Role` header | `role` sanitized, but `_ROLE_LEVELS[token_role]` | `KeyError` |

So every cloud-runner request raises inside authorization. That fails closed by accident — an
exception, not a decision — and the spec's gates M5.1 ("a non-listed target is refused") would pass
for the wrong reason, because *every* target, listed or not, is "refused".

### Second site — an unknown actor is displayed as admin

`bin/k3dm-webhook:611`, in `_handle_thread_command`'s refusal message:

```python
_notify_job(job_id, f"⛔ `{cmd}` requires role *{required}* — you have *{_normalize_role(role)}*.")
```

`_normalize_role` is the **requirement** normalizer (unknown → `admin`). Applied to the caller, an
unrecognised role is shown to the user as "you have *admin*" while being refused. The 2026-09-24 fix
switched the check and the audit trail to `_normalize_actor_role` but missed this display site. It is
cosmetic today (Slack roles are sanitized to `reader` upstream by `_slack_user_role`), but it is the
exact confusion that bug was about, and a `cloud-runner` value reaching it would print "admin".

### Third site — `token_role or _ROLE_DEFAULT`

In `_request_role`, a falsy `token_role` becomes `admin`. That is the documented "bare admin bearer"
behaviour when no token role is known, and is out of scope here. But it means a future resolver that
returns `""` instead of `None` for "unknown token" would grant admin. Assert `None` explicitly.

## Why file it now

The e2e-dispatch spec would have an implementer add the role, see every gate go red or green for the
wrong reason, and patch the KeyError locally — likely by adding `cloud-runner` to `_ROLE_LEVELS`,
which the same spec forbids. Settling the shape before M1 avoids that.

## Fix

Handle a capability role before any rank comparison, in one place:

1. In `_request_role`: if `token_role` is not in `_ROLE_LEVELS`, return it unchanged and ignore any
   `X-K3DM-Role` header (a header may only narrow a *ranked* role; a capability role has nothing to
   narrow to).
2. In `_effective_make_role`: same early return — a capability role is not capped by a Slack role.
3. In authorization (`do_POST` enforcement / `_action_policy`): a role not in `_ROLE_LEVELS` is
   allowed **iff** `(role, target)` is in its capability set (`CLOUD_RUNNER_TARGETS` for
   `cloud-runner`). It never reaches `_role_allows`. Any unknown role without a capability set is
   refused.
4. `bin/k3dm-webhook:611`: use `_normalize_actor_role(role)` for the displayed role.
5. `_request_role`: change `token_role or _ROLE_DEFAULT` to an explicit `token_role is None` test.

Do not add `cloud-runner` to `_ROLE_LEVELS`, and do not change `_normalize_role`
(`strictest_role` depends on unknown-requirement → admin).

This fix can land as the first milestone of `v1.41.0-cloud-bridge-e2e-dispatch.md` (its M2 should
point here) rather than as a separate change; it is a precondition, not a follow-up.

## Tests

1. `_request_role({}, token_role="cloud-runner")` and
   `_request_role({"X-K3DM-Role": "admin"}, token_role="cloud-runner")` both return `"cloud-runner"`
   and raise nothing.
2. Authorization with `cloud-runner`: `e2e-remote` allowed; `test-pytest` (reader tier) refused;
   `fix-delete-pod` refused. The reader-tier refusal is the proof it is a set, not a rank.
3. Every existing `(token_role, header)` pair for `admin`/`reader` returns what it returns today —
   enumerate, don't sample.
4. The thread-command refusal message for role `"nonsense"` says `reader`, not `admin`.
5. `_request_role({}, token_role="")` does not return `admin`.

### Mutations

- Remove the early return in `_request_role` → test 1 red (`KeyError`).
- Add `cloud-runner` to `_ROLE_LEVELS` → test 2's reader-tier case red.
- Revert line 611 to `_normalize_role` → test 4 red.
