# Hermes — Phase-1 read-only ops monitoring (off-hub)

Hermes is the k3d-manager monitoring agent. **Phase 1 only observes, correlates, and reports.**
It has no command surface and no mutation path: it never runs `kubectl apply/patch/delete`, never
syncs ArgoCD, never restarts pods, never writes to Git, and holds no write credential. Those are
deferred to Phases 2/3, each of which requires its own scope document before any code lands
(see [What is NOT implemented](#what-is-not-implemented)).

It runs **off-hub** — on the laptop, the same tier as [`bin/k3dm-webhook`](../../bin/k3dm-webhook) —
so it can still report when the hub cluster is degraded. That placement is what satisfies the
"don't monitor from inside the failure domain" requirement without waiting for dedicated hardware.

**Scope authority:** [`docs/architecture/hermes-phase1-monitoring-scope.md`](../architecture/hermes-phase1-monitoring-scope.md).
**Implementation plans:** [`docs/plans/v1.29.0-hermes-phase1-implementation.md`](../plans/v1.29.0-hermes-phase1-implementation.md),
[`docs/plans/v1.29.0-hermes-ws1-ws2-sensors-correlator.md`](../plans/v1.29.0-hermes-ws1-ws2-sensors-correlator.md),
[`docs/plans/v1.29.0-hermes-ws0-ws3-access-and-installer.md`](../plans/v1.29.0-hermes-ws0-ws3-access-and-installer.md).

---

## The pieces

| Component | File | Role |
|-----------|------|------|
| Agent entrypoint | [`bin/k3dm-hermes`](../../bin/k3dm-hermes) | One sense → correlate → report cycle per run; persists state |
| Records | [`scripts/lib/hermes/records.py`](../../scripts/lib/hermes/records.py) | Normalized `{sensor, status, evidence, sampled_at}` record; status enum |
| Sensors | [`scripts/lib/hermes/sensors.py`](../../scripts/lib/hermes/sensors.py) | The five read-only sensors |
| Correlator | [`scripts/lib/hermes/correlator.py`](../../scripts/lib/hermes/correlator.py) | Deterministic multi-signal fire + bounded LLM enrichment |
| Slack relay | [`scripts/lib/hermes/slack.py`](../../scripts/lib/hermes/slack.py) | One-way summary POST (no command surface) |
| Installer | [`bin/k3dm-hermes-setup`](../../bin/k3dm-hermes-setup) → `_install_hermes_agent` (lib-foundation) | launchd LaunchAgent install/uninstall |
| LaunchAgent template | [`scripts/etc/launchd/com.k3d-manager.hermes.plist.tmpl`](../../scripts/etc/launchd/com.k3d-manager.hermes.plist.tmpl) | Bounded-poll launchd job |
| Tests | [`scripts/tests/hermes/test_hermes.py`](../../scripts/tests/hermes/test_hermes.py) | Sensors, correlator, budget, Slack |

The agent is Python 3 standard-library only — no third-party runtime dependency.

---

## The webhook is authoritative

Hermes does **not** run a second cluster-health model. Cluster truth comes from the existing
k3d-manager webhook — `GET /api/v1/health?provider=<p>` (Bearer token, port 7443), served by
[`bin/k3dm-webhook`](../../bin/k3dm-webhook). When the webhook is unreachable it reports
`overall: "unknown"`, and Hermes then emits status `unknown` — **"status source unavailable"**,
never a fabricated verdict. This is a hard rule: an `unknown` sensor never counts toward an
incident.

Sensor status is a three-value enum defined in
[`records.py`](../../scripts/lib/hermes/records.py): `healthy`, `degraded`, `unknown`.

---

## The five sensors

Each sensor emits one normalized record per cycle and debounces on a sustained signal (a single
flap does not trip it). All are read-only.

1. **`eso`** — ExternalSecrets health, from the webhook `services[]` entries `ESO ClusterSecretStore`
   and `ESO ExternalSecrets`. Not-synced sustained beyond the debounce → `degraded`; source missing
   → `unknown`.
2. **`argocd`** — per-`Application` `Degraded` / `OutOfSync`, from `argocd app list -o json --grpc-web`
   using the read-only `hermes` API token (get-only). The webhook JSON does not expose per-app state,
   which is the one reason Hermes holds an ArgoCD token at all.
3. **`reachability`** — wraps the already-shipped [`bin/public-endpoint-probe --json`](../../bin/public-endpoint-probe)
   (v1.28.0), which discriminates edge-down from single-service failures. Probe "source unavailable"
   exit → `unknown`.
4. **`node_pressure`** — node / control-plane / data-layer pressure, again via the **webhook** payload
   (the `Data layer` entry plus aggregate service health), never a direct node probe.
5. **`ci`** — GitHub Actions / required-check health via the GitHub read API (failed, timed-out,
   cancelled, or stuck in-progress runs).

---

## Correlation and reporting

The correlator ([`correlator.py`](../../scripts/lib/hermes/correlator.py)) is **deterministic and
in-code — not an LLM.** It keeps a rolling window of degraded sensors and fires only on **sustained
multi-signal** degradation: at least two *distinct* degraded sensors within the correlation window
(default 3 cycles). It emits:

- **one** incident summary on the transition into a correlated incident (de-duplicated — it will not
  re-fire while the same incident is active), and
- **one** resolved note when the incident clears.

Unknowns never count toward the two-signal threshold. Single-sensor flaps stay silent.

An LLM is called **only when an incident trips**, to phrase the summary — never for sensing. The
default provider is **`gemini`** (a non-Claude agent); Claude is verify-only and **never authors** a
summary (`correlator.py` refuses to call the LLM when the provider is `claude`). A **per-day call
budget** (default 10) is enforced from day one; when the budget is exhausted or the call fails,
Hermes falls back to a deterministic template. The summary is delivered one-way to the existing
Slack relay by [`slack.py`](../../scripts/lib/hermes/slack.py) — there is no inbound command path.

---

## Access model (least privilege, read-only)

Hermes holds three read-only credentials, all off-hub in the laptop login Keychain (account
`k3dm`). It provisions **no** direct Kubernetes credential — no ServiceAccount, no kubeconfig — by
design: the webhook already is the authoritative read path, so a second cluster credential would add
risk for no signal.

| Purpose | Keychain service | Notes |
|---------|------------------|-------|
| Webhook status (ESO, node pressure, service health) | `k3dm-webhook-token` | Existing token, reused; GET-only in use |
| ArgoCD per-app status | `k3dm-hermes-argocd-token` | `hermes` local account, `apiKey` capability only, RBAC `get` only |
| CI / required-check status | `k3dm-hermes-gh-token` | GitHub fine-grained PAT, read-only permissions only |
| Slack summary delivery | `k3dm-slack-webhook` | Existing incoming-webhook relay |

The ArgoCD `hermes` account and its RBAC (`get` only, no `sync`/`update`/`delete`) live in
[`scripts/etc/argocd/values.yaml.tmpl`](../../scripts/etc/argocd/values.yaml.tmpl). The ArgoCD token
is minted out-of-band (`argocd account generate-token --account hermes`); the GitHub PAT is minted by
the repository owner. Neither is committed, and the installer never mints, reads, or modifies any
credential — it only checks that they are present.

To confirm the read-only posture: `argocd account can-i get applications '*/*'` → yes,
`argocd account can-i sync applications '*/*'` → no; the GitHub PAT succeeds on a read call and is
403/404 on any write.

---

## Install and uninstall

The installer helper `_install_hermes_agent` lives in **lib-foundation** (`scripts/lib/system.sh`,
subtree-pulled into [`scripts/lib/foundation/`](../../scripts/lib/foundation)); never edit the subtree
copy directly. It is macOS-launchd only, and it **preflights** that the four Keychain entries above
exist, refusing to run if any is missing — it never creates a credential.

Provision the read-only credentials first (see [Access model](#access-model-least-privilege-read-only)),
then:

```bash
# Install and start the LaunchAgent (com.k3d-manager.hermes)
bin/k3dm-hermes-setup

# Confirm the job is loaded and watch a cycle
launchctl print "gui/$(id -u)/com.k3d-manager.hermes"
tail -f ~/Library/Logs/k3dm-hermes.log

# Remove the agent (leaves the read-only Keychain credentials intact)
bin/k3dm-hermes-setup --uninstall
```

The LaunchAgent runs the agent on a **bounded `StartInterval`** (default 300s) with `RunAtLoad` and
**no `KeepAlive`** — one cycle per interval, not a tight loop. No secret is stored in the plist; the
agent reads credentials from the Keychain at runtime. Polling is jittered: with `K3DM_HERMES_JITTER`
set (the template sets it), `bin/k3dm-hermes` sleeps a random 0–30s before sensing so runs do not
align to a hard boundary.

---

## Configuration

`bin/k3dm-hermes` reads these environment variables (all optional; safe defaults shown):

| Variable | Default | Meaning |
|----------|---------|---------|
| `K3DM_HERMES_STATE` | `~/.k3dm/hermes/state.json` | State file (dir `0700`, file `0600`) |
| `K3DM_HERMES_WEBHOOK_HOST` | `127.0.0.1:7443` | Webhook host:port |
| `K3DM_HERMES_PROVIDER` | (unset) | Cluster provider passed to the webhook query |
| `K3DM_HERMES_CORRELATION_WINDOW` | `3` | Cycles in the correlation window |
| `K3DM_HERMES_LLM_PROVIDER` | `gemini` | LLM provider on trip (never `claude` as author) |
| `K3DM_HERMES_LLM_DAILY_BUDGET` | `10` | Max LLM calls per day before template fallback |
| `K3DM_HERMES_JITTER` | (unset) | When set, sleep 0–30s before sensing |

---

## Running the tests

```bash
# Standard-library agent; tests need pytest in a venv (the repo interpreter has none)
python3 -m venv /tmp/k3dm-hermes-pytest
/tmp/k3dm-hermes-pytest/bin/pip install pytest
/tmp/k3dm-hermes-pytest/bin/pytest -q scripts/tests/hermes/

# lib-foundation installer unit tests (bash)
env -i HOME="$HOME" PATH="$PATH" \
  bats scripts/lib/foundation/scripts/tests/lib/hermes_install.bats
```

---

## What is NOT implemented

Phase 1 is deliberately advisory-only. The following are **not** built and each requires its own
scope document before any code is written:

- **Phase 2** — any action surface (remediation, sync, restart, edge refresh, Git or
  branch-protection changes). Hermes holds no write credential today, by design.
- **Phase 3** — autonomous or scheduled remediation.

If you are reading this to add a mutating capability: stop and write the Phase-2 scope doc first.
The "no mutation path in the codebase" property is grep-assertable and is part of the release
Definition of Done — keep it that way.
