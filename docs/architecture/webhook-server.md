# Webhook Server Architecture

**Component:** `bin/k3dm-webhook` + `scripts/lib/webhook/`
**Status:** modularization Phase 1 landed (v1.13.0); Phases 2–5 pending
**Related specs:** [`docs/plans/v1.13.0-webhook-modularization.md`](../plans/v1.13.0-webhook-modularization.md) (umbrella),
`v1.13.0-webhook-modularization-phase1.md` (config), `-render.md` (render), `-auth.md` (proc + auth)

This document describes the webhook server **as it exists after the v1.13.0 in-repo
modularization refactor** — what has been extracted, what still lives in the monolith,
and the seams the remaining phases will cut along.

---

## What it is

`bin/k3dm-webhook` is a single-process Python HTTP server (stdlib
`http.server.ThreadingHTTPServer`, no framework) bound to `127.0.0.1:7443`. It runs under
launchd (`scripts/etc/launchd/com.k3d-manager.webhook.plist.tmpl`) and is fronted by the
Cloudflare `k3dm-slack-relay` Worker, which verifies Slack requests and proxies them here
(see [`docs/architecture/cloudflare-slack-relay.md`](cloudflare-slack-relay.md)).

It is the execution backend for Slack slash commands and thread commands — cluster
lifecycle (`cluster-up/down/refresh/status`), diagnostics, failure analysis, and the
multi-agent `/ask` `/claude` `/gemini` `/codex` handlers.

> **Operational note:** launchd runs whatever `bin/k3dm-webhook` was on disk when it last
> started — it does **not** auto-reload after a `git pull`/merge. Run `make restart-webhook`
> after any change. See [`docs/howto/slack-slash-commands.md`](../howto/slack-slash-commands.md).

---

## Module layout after Phase 1

The refactor keeps `bin/k3dm-webhook` as the entrypoint and process host, and pulls
**pure, low-risk helpers** into an importable package at `scripts/lib/webhook/`. The
entrypoint wires the package onto `sys.path` before importing:

```python
# bin/k3dm-webhook:22
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts" / "lib"))
from webhook.config import (...)
from webhook.render import (...)
from webhook.proc   import _spawn_capture_text
from webhook.auth   import (...)
```

| Module | Lines | Responsibility | Depends on |
|--------|-------|----------------|------------|
| `webhook/config.py`  | ~50  | Constants, env-var parsing, filesystem paths (`JOB_DIR`, `RUN_DIR`, `TOKEN_FILE`, ports, Slack/Pushgateway URLs), `_safe_job_dir()` job-id validation | — (leaf) |
| `webhook/render.py`  | ~90  | Slack output: `_slack_post` (incoming webhook/response_url), `_post_slack_bot` (chat.postMessage), `_fetch_thread_context` | `config` |
| `webhook/proc.py`    | ~80  | `_spawn_capture_text` — the fork-safe `os.posix_spawn` capture primitive (avoids macOS NEF atfork SIGSEGV) | — (leaf) |
| `webhook/auth.py`    | ~65  | `_keychain_secret`, `_get_token` (bearer resolution), `_verify_slack_signature`; computes `SLACK_SIGNING_SECRET` at import | `config`, `proc` |

`webhook/__init__.py` is empty — the package is a plain namespace.

### Dependency direction

```
config  ◄── render
   ▲
   └────── auth ──► proc ◄── (bin/k3dm-webhook also imports proc directly)
```

`config` and `proc` are leaves (no intra-package imports), which is what makes them safe to
import from BATS/pytest and from the smoke gate without booting the HTTP server.

---

## What still lives in the monolith

`bin/k3dm-webhook` is still ~2,950 lines. Everything below is **not yet extracted** and
maps to the phases still to come:

| Area (functions) | Lines (approx) | Future home (planned) |
|------------------|----------------|-----------------------|
| HTTP routing — `_Handler.do_POST` / `do_GET`, `__main__` server bootstrap | 2568–2953 | `server.py`, `routes.py` |
| Provider resolution — `_normalize_provider`, `_resolve_provider`, `_provider_context` | 56–141 | `dispatch.py` |
| RBAC / audit — `_normalize_role`, `_request_role/actor`, `_role_allows`, `_action_policy`, `_audit_remote_action` | 142–195 | `commands.py` / `dispatch.py` |
| Request validation — `_validate_namespace/resource_name/diagnostics_request` | 206–258 | `routes.py` |
| Job runner — `_posix_spawn_job`, `_read_job_tail`, `_running_cluster_job`, `_clear_stale_jobs`, `_notify_job` | 349–1295 | `jobs.py` |
| Cluster ops — `_run_cluster`, `_run_cluster_resume`, `_run_cleanup`, `_run_upgrade` | 290–568 | `dispatch.py` |
| Command handlers — `_run_cluster_status/refresh/diagnostics/ask`, `_run_hostinger_*`, `_run_analyze`, `_handle_thread_command` | 629–2567 | `commands.py` |
| Diagnostics / failure analysis — `_collect_cluster_state`, `_analyze_failure`, `_analyze_stall`, `_call_gemini`, `_smoke_test_services`, `_run_post_provision_check` | 904–1671 | `diagnostics.py` |
| k8s / metrics — `_init_k8s_ctx`, `_push_metrics`, `_provider_supports_pushgateway` | 1165–1390 | `dispatch.py` / `diagnostics.py` |

**Deliberately not extracted yet** (per the umbrella spec's "Why not `lib-foundation` yet"):
these paths are tightly bound to the repo's provider model, shopping-cart diagnostics,
Slack command semantics, and cluster lifecycle — the seams are not stable enough to lift.

---

## Request flow (current)

```
Slack ──► Cloudflare Worker (k3dm-slack-relay)
            │  verify signature, proxy
            ▼
    127.0.0.1:7443  _Handler.do_POST                 [bin/k3dm-webhook]
            │
            ├─ auth: _verify_slack_signature / _get_token   [webhook.auth]
            ├─ route by path, validate body                 [monolith]
            ├─ ack Slack within 3s, spawn background job     [_posix_spawn_job → webhook.proc]
            │       └─ job dir under JOB_DIR                 [webhook.config._safe_job_dir]
            ▼
    command handler (_run_cluster_*, _run_analyze, …)        [monolith]
            │  provider-aware subprocess (make up/down/…)
            ▼
    result ──► Slack via _post_slack_bot / _slack_post       [webhook.render]
```

Auth and Slack I/O sit at the package boundary; routing, job lifecycle, and command
execution are still monolith-internal.

---

## Testing & operational surfaces

- **BATS:** `scripts/tests/lib/webhook.bats` — end-to-end handler behavior. Must isolate
  `K3DM_JOB_DIR` / `K3DM_RUN_DIR` (and stub `make` / `K3DM_GEMINI_BIN`) so it never touches
  the live `:7443` job dirs — see the v1.13.0 bats-isolation bugfix specs in `docs/bugs/`.
- **Smoke gate:** `bin/smoke-test-webhook` boots an isolated instance and hits
  `/api/v1/health`; it **must** override `K3DM_JOB_DIR` / `K3DM_RUN_DIR` or it clobbers
  live jobs.
- **launchd:** `com.k3d-manager.webhook.plist.tmpl`; token auto-rotation via
  `com.k3d-manager.webhook-token-rotate.plist.tmpl` + `bin/rotate-webhook-token`.
- **Secrets:** bearer token and Slack signing secret resolve from the macOS Keychain
  (account `k3dm`: `k3dm-webhook-token`, `k3dm-slack-signing-secret`) via
  `webhook.auth._keychain_secret`, with env-var overrides.

---

## Roadmap (remaining phases)

Phase 1 (config/auth/render/proc) is done. The umbrella spec sequences the rest by risk:

- **Phase 2** — command registry + dispatch split (`commands.py`, `dispatch.py`)
- **Phase 3** — jobs/state management split (`jobs.py`)
- **Phase 4** — diagnostics/failure analysis split (`diagnostics.py`)
- **Phase 5** — evaluate generic extraction candidates for `lib-foundation` (auth,
  job-state primitives, subprocess wrappers) — only if another repo demonstrably needs them

No change to the external Slack/Worker contract is planned across any phase.
