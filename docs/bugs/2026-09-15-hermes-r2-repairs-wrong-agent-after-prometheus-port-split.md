# Bug: Hermes R2 kickstarts the wrong launchd agent for prometheus.3ai-talk.org

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-15
**Status:** OPEN — not assigned
**Severity:** medium — a self-repair that cannot repair the failure it fires on, and its own
stated grounding is now false.
**Fix lands in:** `scripts/lib/hermes/repairs.py`, `scripts/tests/hermes/test_repairs.py`
**Caused by:** `4f2fda24` (Prometheus auth proxy — the port split), applied live 2026-09-15.

## Evidence (2026-09-15, live, read-only)

`scripts/lib/hermes/repairs.py:22-28` maps the public host to a launchd label, and documents
exactly why that mapping is considered sound:

```python
# prometheus.3ai-talk.org (ingress :19090) maps cleanly to the prometheus PF
# (19090:9090). The other public hosts are served by different mechanisms
# ... and alertmanager's ingress (:9093) does not match its PF listen port
# (:19093) -- none has a known launchd PF label, so R2 is not proposable for them.
PORT_FORWARD_LABELS = {
    "prometheus.3ai-talk.org": "com.k3d-manager.prometheus-port-forward",
}
```

That grounding no longer holds. After the port split the live topology is:

```
cloudflared ingress  ->  127.0.0.1:19090   com.k3d-manager.prometheus-auth-proxy   (python, pid 66640)
auth proxy backend   ->  127.0.0.1:19091   com.k3d-manager.prometheus-port-forward (kubectl, pid 66229)
```

So `prometheus.3ai-talk.org` is served by the **auth proxy**, not the port-forward — precisely
the "ingress port does not match the PF listen port" shape the comment uses to *exclude*
Alertmanager from R2.

## Impact

`launchctl kickstart -k com.k3d-manager.prometheus-port-forward` is now the correct repair for
only one of the two ways the host can go down:

- **Port-forward dead** — proxy is up but its backend is gone. The public host fails; kickstarting
  the PF fixes it. R2 still correct here.
- **Auth proxy dead** — nothing is listening on 19090 at all. The public host fails; kickstarting
  the PF changes nothing, the proxy stays down, and Hermes reports a repair it did not make.
  This is not hypothetical: the proxy crash-looped under `KeepAlive` for the entire window between
  `make observability` and `make install-prometheus-port-forward` today
  (`OSError: [Errno 48] Address already in use`).

The second case is also the more likely one, because the proxy is the process with a real
failure mode (bad credentials file, port conflict, python exception) while the PF is a plain
`kubectl port-forward` under `KeepAlive`.

## Fix

1. Point the mapping at the process that actually serves the ingress port. `PORT_FORWARD_LABELS`
   should resolve `prometheus.3ai-talk.org` to `com.k3d-manager.prometheus-auth-proxy`, or become
   an ordered list so R2 can kickstart the proxy and then the backend PF.
2. Rewrite the block comment to describe the post-split topology, and keep its useful rule
   explicit: **the label R2 restarts must be the agent listening on the cloudflared ingress port.**
   Derive it from `scripts/etc/cloudflared/config.yml` plus the installed plists' listen ports
   rather than assuming a `*-port-forward` label.
3. If a list is chosen, R2 must still propose a single command per cycle — do not batch two
   `launchctl kickstart` calls into one proposal.

## Tests (`scripts/tests/hermes/test_repairs.py`)

Two existing assertions hardcode the old label and will fail — that is the point, update them:

- `test_repairs.py:49` — `assert proposals[0]["command"] == "launchctl kickstart -k com.k3d-manager.prometheus-port-forward"`
- `test_repairs.py:143` — the same label in the executed-calls assertion

Add a guard test that the R2 label for a public host matches the agent bound to that host's
cloudflared ingress port, so the next port move fails a test instead of silently mis-repairing.

## Acceptance

1. Stop the auth proxy, let Hermes observe `prometheus.3ai-talk.org` degraded, and confirm the
   proposed command names the auth-proxy agent and that running it restores the host.
2. Stop the port-forward and confirm the backend is restored (whether by the same proposal or a
   follow-up cycle).
3. `pytest scripts/tests/hermes/test_repairs.py` green.

## What NOT to do

- Do not widen R2 to hosts the comment excludes — Alertmanager, ArgoCD, Keycloak, Grafana,
  frontend — that is a separate question.
- Do not revert the port split to make the old mapping true again.
- Do not have R2 reinstall plists or run `make` targets; kickstart only.
