# Bug: `prometheus.3ai-talk.org` is publicly readable with no authentication

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-15
**Status:** OPEN
**Severity:** high — a public, unauthenticated read of every metric series, target list, and scrape config on the hub.
**Files:** `bin/prometheus-auth-proxy` (new), `scripts/etc/launchd/com.k3d-manager.prometheus-auth-proxy.plist.tmpl` (new), `scripts/etc/launchd/com.k3d-manager.prometheus-port-forward.plist.tmpl`, `scripts/plugins/observability.sh`, `scripts/tests/lib/observability.bats`, `CHANGELOG.md`
**Related:** `docs/bugs/v1.6.1-bugfix-prometheus-acg-web-config-arg.md` (why the operator path was abandoned)

## Evidence (2026-09-15)

The operator-account login checks (`384b0202`) reported:

```
✗ Prometheus login: admin via Vault k3d-manager/prometheus-basic-auth: auth not enforced
✓ Alertmanager login: admin via ~/.local/share/k3d-manager/alertmanager-basic-auth.env: HTTP 200
```

"auth not enforced" means the **unauthenticated** probe of
`https://prometheus.3ai-talk.org/api/v1/status/buildinfo` returned 200.

Live, read-only confirmation:

- `monitoring/prometheus-web-config` exists on `ubuntu-hostinger` (55d old) and holds a real
  `basic_auth_users:` entry.
- The Prometheus CR `acg-kube-prometheus-stack-prometheus` has **`spec.web` empty** — nothing
  mounts that Secret and nothing passes `--web.config.file`. The Secret is inert.
- No consumer of `prometheus-web-config` exists anywhere in the repo outside the function that
  creates it.

## Root cause

Two independent facts combine:

1. **The operator path was deliberately removed** in v1.6.1: `prometheus-operator` v0.79.2 added
   `web.config.file` to its managed-args denylist, so `additionalArgs` broke reconciliation. The
   accepted trade-off at the time was "Prometheus runs without basic auth on the ACG dev cluster
   (acceptable for ephemeral sandbox environments)". `_prometheus_acg_web_config_secret` was left
   in place, still creating a Secret nothing reads.
2. **That same values path now serves a public endpoint.** `scripts/etc/cloudflared/config.yml`
   publishes `prometheus.3ai-talk.org → http://127.0.0.1:19090`, and 19090 is the **raw**
   port-forward (`com.k3d-manager.prometheus-port-forward.plist.tmpl`, `19090:9090`). The
   "ephemeral sandbox" rationale does not hold for an internet-reachable hostname.

Alertmanager is not exposed this way: `alertmanager.3ai-talk.org → 127.0.0.1:9093` is
`bin/alertmanager-auth-proxy`, which authenticates and forwards to the raw port-forward on 19093.
Prometheus simply never got the equivalent, which is why its line is the only red one.

## Fix — mirror the Alertmanager auth-proxy pattern

Do **not** revive the operator `web.config.file` path; v1.6.1 documents why it fails.

1. **`bin/prometheus-auth-proxy`** — same shape as `bin/alertmanager-auth-proxy`: a stdlib
   `ThreadingHTTPServer` basic-auth reverse proxy, backend `http://127.0.0.1:19091`, credentials
   from an env file (`--credentials-file`), hop-by-hop headers stripped, `WWW-Authenticate` on 401.
   Reuse the existing module's structure; do not import it across files if that means reshaping
   `bin/alertmanager-auth-proxy` — a small, parallel script is preferred over a risky refactor.
2. **Port split** — `com.k3d-manager.prometheus-port-forward.plist.tmpl` binds **`19091:9090`**
   (was `19090:9090`); the auth proxy listens on **19090**. `scripts/etc/cloudflared/config.yml`
   is unchanged, so the public hostname keeps working and becomes authenticated.
3. **Credentials file** — `_observability_ensure_prometheus_login`, modelled on
   `_observability_ensure_alertmanager_login`: read `user` / `password` from Vault
   `secret/k3d-manager/prometheus-basic-auth` via the existing hub port-forward helper, write
   `~/.local/share/k3d-manager/prometheus-basic-auth.env` with mode `0600` and lines
   `PROMETHEUS_BASIC_AUTH_USER=` / `PROMETHEUS_BASIC_AUTH_PASSWORD=`. Never echo either value.
   If Vault is unreadable, `_warn` and skip — do not invent a password.
4. **`_observability_install_prometheus_auth_proxy`** — mirror
   `_observability_install_alertmanager_auth_proxy`: mac-only, skip with `_warn` when `launchctl`
   or `python3` is missing or the credentials file is absent, render the plist template, then
   `launchctl bootout` + `bootstrap`. Call it next to the Alertmanager one, and extend
   `_observability_restore_alertmanager_access_layer`'s prometheus equivalent if one exists.
5. **Rotation** — `observability_rotate_prometheus_basic_auth` must rewrite the credentials file
   and re-bootstrap the proxy, so a rotated password does not lock the operator out.
6. Leave `_prometheus_acg_web_config_secret` alone; it is out of scope here.

## Tests (`scripts/tests/lib/observability.bats`, stubs only)

- The port-forward template binds `19091:9090`, and the proxy plist template names port `19090`.
- `_observability_ensure_prometheus_login` writes the env file with both keys, mode `0600`, and the
  password never appears in the function's stdout/stderr (assert with a sentinel).
- Vault unreadable → warn, no file written, no proxy bootstrap.
- Missing credentials file → install is skipped with a warning, and `launchctl bootstrap` is not called.
- `launchctl bootout` precedes `bootstrap` in the install path.
- Assert meaningful tokens, never whole source lines.
- `shellcheck -S warning -x scripts/plugins/observability.sh` stays clean.

## Acceptance (operator runs these; not part of the code change)

1. `make observability` (or the targeted install) to write the credentials file and load the proxy.
2. `curl -sS -o /dev/null -w '%{http_code}' -A k3dm-smoketest/1 https://prometheus.3ai-talk.org/api/v1/status/buildinfo` → **401**.
3. The same URL with the operator's basic auth → **200**.
4. `make status CLUSTER_PROVIDER=k3s-hostinger` → `✓ Prometheus login`.
5. Confirm Grafana's Prometheus datasource and any federation client still work; if a client scrapes
   the public hostname unauthenticated, it must be given the credential rather than the auth removed.

## What NOT to do

- Do not re-add `web.config.file` via `additionalArgs` or `spec.web` — v1.6.1 proves the operator rejects it.
- Do not remove or weaken the Alertmanager auth proxy.
- Do not print, log, or commit any credential; no base64 comparisons.
- Do not run `launchctl`, `kubectl`, `helm`, or `curl` against the live cluster from tests or from the implementation run.
- Do not edit `scripts/lib/foundation/` or `scripts/lib/acg/`.
- No PR, no merge, no `main` commit, no force-push, no `--no-verify`. No `git add -A`, no `git stash`.
