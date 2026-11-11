# cluster-up step 10d: realm-import port-forward collides with the Keycloak browser agent on :18080

**Status:** LANDED 2026-11-11 (`3b0e6534`, Claude review: 196/196 bats, new tests red pre-fix) — found 2026-11-11 by Claude investigating /cluster-up aws job `63ed929e` on the M5
**Priority:** P1
**Waiting on:** live check — since 2026-11-11
**Severity:** high — `/cluster-up aws` fails at step 10d on a hub where the Keycloak browser agent is loaded, leaving a billable CloudFormation stack
**Introduced by:** unknown (the Host-less probe wrapper on the M5 is dated 2026-11-06 04:25, the day `632ac235` added Hostinger's writer of this agent; not proven)
**Should have been caught by:** live check
**Prior art:** docs/bugs/2026-11-06-hostinger-refresh-skips-argocd-keycloak-browser-agents.md (find-similar-docs unavailable: vector store context missing; picked by filename) — read, different defect (that one added the agent; this one is its collision with step 10d and its probe)
**Approval:** operator, 2026-11-11 ("go ahead to dispatch")
**Intent approved:** operator, 2026-11-11

## Symptom

Job `63ed929e` (2026-11-11 04:05 PST, M5) passed steps 1–10c and failed:

    INFO: [acg-up] Step 10d/14 — Importing Keycloak realm shopping-cart...
    INFO: [acg-up] Keycloak admin token not ready (attempt 1/5) — retrying in 15s...
    ...
    ERROR: [acg-up] Could not get Keycloak admin token after 5 attempts — realm import is required for SSO and cannot be skipped

## Investigation (Claude, M5, 2026-11-11 04:25–04:40 PST)

1. **The credential is good.** `cluster-up` reads the admin password from Vault `keycloak/admin` (job line 461, `Reusing existing Vault secret keycloak/admin`). ESO syncs the same value into `identity/keycloak-secrets` (`SecretSynced True`). A fresh `kubectl port-forward deploy/keycloak 18091:8080` plus the same token POST returns **200** with an `access_token`.
2. **The same request through :18080 returns 404 from `server: istio-envoy`.** Step 10d port-forwards `deployment/keycloak` to `localhost:18080` (`bin/cluster-up:1136`, `:1167`), but at 04:30 the listener on 127.0.0.1:18080 was
   `kubectl --context k3d-k3d-cluster port-forward --address=127.0.0.1 svc/istio-ingressgateway -n istio-system 18080:80`, child of pid 7873, which is launchd agent `com.k3d-manager.browser.keycloak-http`. The Istio ingress has no route for `Host: localhost`, so `/realms/master/...` returns 404 and `curl -sf` yields no token five times.
3. **The two use the same port by design.** `cluster-up` installs that agent itself on 18080 (`bin/cluster-up:1504`), after step 10d. On a hub that never had it, step 10d runs first and wins. On every later run the agent is already loaded. Step 10d kills the current holders of :18080 (`:1161-1165`), but launchd KeepAlive and the wrapper's own restart loop rebind the port within seconds.
4. **The agent restarts all the time, so it reclaims the port quickly.** The wrapper launchd runs is `~/.local/share/k3d-manager/bin/keycloak-browser-http.sh` (mtime 2026-11-06 04:25). Its health probe is `HEALTHZ_URL=http://127.0.0.1:18080/health/ready` (lines 13, 141, 167), with no Host header. Through the Istio ingress that returns 404 (sampled 404 404 404 404 404 000), while `http://keycloak.shopping-cart.local/health/ready` returns 200 200 200. The log `~/.local/share/k3d-manager/logs/keycloak-browser-http.log` has **11,747** `healthz did not become reachable — restarting` lines. Writers of a wrapper with that probe: `scripts/lib/providers/k3s-hostinger.sh:612` and `bin/cluster-up:1504`. `bin/cluster-up:1505` skips reinstalling the plist while the port-80 relay answers, so the stale wrapper is never replaced.

Not proven: exactly which listener the job's curl reached in each of the five attempts. The job's own `kubectl port-forward` did log `Forwarding from 127.0.0.1:18080 -> 8080` (`k3s-aws/logs/keycloak-pf.log:194458`), and at the time of the check the agent held the port.

## Fix direction (for the spec)

- Step 10d uses its own port, not shared with any launchd agent (or one picked free at run time), for its private admin port-forward. The `bin/cluster-up` lines 1620 and 1337–1396 that reuse `_kc_pf_port` follow.
- The agent's health probe sends the Host the ingress routes (`Host: keycloak.shopping-cart.local`, or the hostname URL) in every writer, so a healthy agent stops restarting.
- `cluster-down:119-123` clears 18080 by `kill -9` of holders. List it under Contract readers.

## Workaround (untested)

Before rerunning, unload the agent with `launchctl bootout gui/$(id -u)/com.k3d-manager.browser.keycloak-http`, then rerun or resume `/cluster-up aws`. Step 10d then owns :18080, and the agent is reinstalled at line 1504. Not yet run. Priority drops to P2 once it is proven.

## Files

| File | Change |
|---|---|
| `bin/cluster-up` | step 10d private admin port-forward on its own port (`_kc_pf_port`, also used at `:1337-1396`, `:1620`), never 18080 or any browser-agent/relay port |
| `scripts/plugins/argocd.sh` | `_argocd_write_port_forward_wrapper` health probe can carry the Host the ingress routes |
| `scripts/lib/providers/k3s-hostinger.sh` | keycloak browser wrapper (`:612`) probes with that Host |
| `bin/cluster-refresh` | keycloak browser wrapper (`:512`) probes with that Host |
| `bin/cluster-up` (`:1504`) | same, for the agent cluster-up installs |
| `scripts/tests/bin/cluster_up.bats`, `scripts/tests/plugins/argocd*.bats` (or the suite that covers the wrapper) | E1, E2 |

## Worker definition of done

- Change only the files above. Grep every writer of a keycloak-http wrapper and every user of port 18080 first, and list them in your report; if one is missing from the Files table, stop and report it rather than editing it.
- Do not touch the running launchd agents or the live hub; E3 is Claude's.
- Show every `must_not` test red against today's code, then green. Mutation-test each guard (break it, see the test fail, restore). Run the full touched suites, not only the new tests, and run the change once read-only against real data where the spec says how. Paste command, rc and the proving lines for each; list every error you saw, and any choice the spec left open. Leave changes uncommitted; Claude reviews and lands.

## Acceptance

```yaml
must:
  - id: M1
    text: step 10d obtains a Keycloak admin token when com.k3d-manager.browser.keycloak-http is loaded and holding its port
  - id: M2
    text: the keycloak-http browser agent's health probe returns success through the Istio ingress when Keycloak is up
must_not:
  - id: N1
    text: step 10d's admin port-forward shares a port with any launchd browser agent or relay
  - id: N2
    text: the keycloak-http wrapper restarts its port-forward while Keycloak answers on its hostname
evidence:
  - id: E1
    proves: [N1]
    kind: offline
    intent: "a test fails if step 10d's admin port-forward port equals the port any browser agent writer uses"
  - id: E2
    proves: [M2, N2]
    kind: offline
    intent: "a generated wrapper's probe, run against a stub that answers 200 only with Host keycloak.shopping-cart.local, counts as healthy"
  - id: E3
    proves: [M1]
    kind: live
    intent: "on the M5 with the keycloak-http agent loaded, /cluster-up aws passes step 10d and the agent log stops adding restart lines"
interface:
  - bin/cluster-up (step 10d, _kc_pf_port)
  - _argocd_write_port_forward_wrapper (scripts/plugins/argocd.sh)
  - scripts/lib/providers/k3s-hostinger.sh browser-agent writer
```

## Contract readers

Port 18080 on the M5 (to be confirmed by grep in the spec): `bin/cluster-up:1136,1161-1177,1620` (step 10d, writer and reader), `bin/cluster-up:1504` (agent writer), `scripts/lib/providers/k3s-hostinger.sh:612` (agent writer), `bin/install-browser-relays.sh:50` (relay 80→18080, reader), `bin/cluster-down:119-123` (kills holders), `bin/cluster-up:263,1452-1463` (port 18080 on the remote `ubuntu` host: different machine, unaffected), `bin/k3dm-webhook:1854` (help text claims ArgoCD UI on 18080: stale doc).

## Side finding

The failed run left CloudFormation stack `k3d-manager-cluster` (us-west-2) running (billable), and the job's port-forward survived the failure path's `kill "${_kc_pf_pid}"`.

## Workaround proven live (2026-11-11)

/cluster-up aws job `40d0e3dd` on the M5 ran pre-fix code (`deploy/hub` 745abb50, `_kc_pf_port=18080`). Before step 10d the
operator ran `launchctl bootout gui/$(id -u)/com.k3d-manager.browser.keycloak-http`; Claude confirmed the agent unloaded and
:18080 free. Step 10d then passed (realm import, e2e identity, frontendUrl; output lines 348-351), 10d.5-10g.9 passed, and
the job ended `up complete`, status `success`. The agent was reinstalled afterwards from the old wrapper (`runs = 9`,
`spawn scheduled`), so it still restart-loops until the fix is promoted. This proves the workaround, not the fix: E3 still
needs a cluster-up after `make hub-promote` includes `3b0e6534`.
