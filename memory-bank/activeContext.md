# Active Context — k3d-manager

## 2026-09-22 — Grafana "no data" triaged; smoke + hub-snapshot specs assigned to Codex

**Grafana is not broken.** Hub Prometheus has 31 active targets up and serves data; the
`kube-prometheus-stack-grafana-datasource` ConfigMap points at
`http://kube-prometheus-stack-prometheus.monitoring:9090/` unauthenticated (correct — hub
Prometheus has no basic auth) and all 30 dashboard ConfigMaps provisioned cleanly. Grafana's
own logs contain no datasource query errors. Grafana is reachable at `grafana.3ai-talk.org`
(HTTP 200); its port-forward is `:3001`, not `:13000`.

What is actually empty, and why — three independent causes, none of them a query fault:

- **e2e dashboards.** `e2e_last_run_pass = 0` — the last run, 15.6h ago
  (`run_id=1790025545-10464`, `tier=vcluster`, `runner=local-m4`), FAILED.
  `e2e_last_success_timestamp_seconds` has **never** been published, so every
  "last success" and trend panel is legitimately blank.
- **e2e failure detail.** `e2e_failure_info` and `e2e_failure_group_info` are empty even
  though the run failed, and `e2e_run_info` carries a malformed `failure_ratio="/"` —
  an empty-over-empty division. A failed run produced no failure detail. This is the gap
  `docs/plans/v1.36.0-e2e-deterministic-triage-and-corpus.md` covers.
- **Hermes.** `hermes_sensor_status` and `hermes_last_poll_timestamp_seconds` empty because
  `K3DM_HERMES_STATUS_ENABLED` is deliberately unset. By design.
  `hermes_incident_active` and all `trivy_*` metrics DO have data.

Metric names match the dashboards exactly — there is no `k3dm_` prefix mismatch.

**Tier 1 and Tier 2 e2e remain unrunnable; both blockers verified, not assumed.**
Tier 1: the `gh` token scopes are `admin:public_key, gist, read:org, repo` — no
`read:packages`, so the in-cluster Playwright job cannot pull from GHCR. Runner health is
otherwise green (`hub=ok`, `runner=m2jump`, `runner_status=available`). Operator must run
`gh auth refresh -h github.com -s read:packages`. Tier 2: no ACG context exists at all
(only `k3d-k3d-cluster` and `ubuntu-hostinger`); needs the manual TTY login.

**Two specs written and pushed as `b37acb91`, dispatched to Codex (session
`01a0c93c-45b4-7301-9ac7-661b66e21204`):**

- `docs/plans/v1.36.0-make-smoke-target.md` — no `make smoke` exists today; three
  `bin/smoke-test-*` scripts are invoked ad hoc. Tiered target: offline checks always,
  cluster checks only when the context is reachable (unreachable = SKIP with a reason, not
  FAIL). Deprecated `bin/smoke-test-jenkins` stays unwired.
- `docs/plans/v1.36.0-hub-snapshot-capture-and-retention.md` — **the restore half already
  exists** (`hub_recovery_plan/validate/targets/restore`, executed 2026-09-11). Only capture
  is missing. Capture must emit the exact layout `hub_recovery_restore` already consumes
  (`server-db/state.db`, `server-token`, `pv-pvc.yaml`, `node-*-storage/pvc-<uid>_<ns>_<claim>/`),
  offload to M2, and prune.

**Measured sizes (hub, 2026-09-22):** Prometheus 2.0G, keycloak-postgres 67M, Loki 46M,
Vault 23M → **≈2.15G per snapshot**. M2 (`m2jump`/`m2-air.local`) has **382Gi** free vs the
M4's 163Gi, so M2 is the store, as the operator proposed.

**Retention ceiling — the governing constraint.** Hub Prometheus runs
`--storage.tsdb.retention.time=3d --storage.tsdb.retention.size=8GB` and prunes
out-of-retention blocks *at startup*. A snapshot older than 3 days therefore restores blocks
Prometheus immediately deletes — the feature would silently do nothing. Snapshot retention
defaults to 3 kept snapshots for that reason. Long-term history needs raised retention or
remote-write, NOT snapshots. `enableAdminAPI` is `false` and stays false: capture happens
during teardown, so a cold copy is consistent by construction.

Two spec decisions worth remembering: node placement must be **derived from the live PV**,
not read from `_hub_recovery_records` — `local-path` pins to whichever node the pod landed
on, and Prometheus measured on `agent-1` today while the record says `agent-0`. And Vault KV
needs no separate export: `secrets/data-vault-0` is the file backend and already contains it.

Wiring capture into `make down`/`make up` is explicitly OUT of scope until capture is proven
on a real hub — adding a 2.15G transfer to the destructive `down` path unreviewed is not
acceptable.

## 2026-09-22 — Prometheus reseed and rotator CI fix

Implemented and committed as `7d475a9fe1e8e5f051d035b4f917559341d8b127` (`fix(observability): distinguish unreachable Vault from an absent Prometheus entry`), then pushed to `origin/k3d-manager-v1.36.0`. Vault reachability now gates Prometheus reseeding; unreachable Vault skips without writing, while an absent entry still reseeds. The two reseed security assertions are effective, the Alertmanager test is hermetic and checks the real unresolved-value gate, and the Keycloak/ArgoCD rotators use BusyBox-compatible `base64 -d`. Added the platform-ops regression suite and rotation-guide note. Verification: shellcheck, all focused suites, doc links, and `make test` (1,010/1,010) passed; `scripts/tests/lib/observability.bats` is unchanged.

## 2026-09-22 — Post-merge housekeeping for promoter PRs

Both `shopping-cart-product-catalog` PR #55 and `shopping-cart-infra` PR #99 merged successfully
at 2026-09-22 00:04-00:05Z, merge commits `b6ff80b7` (product-catalog) and `91432535` (infra).
Both fixed the PROMOTER_SSH_KEY promotion failure: product-catalog's `ci.yml` now forwards the key
to the reusable workflow, and infra gained the guard step that detects an empty key and fails with
an actionable error message. Main synced locally for both repos and merge commits verified present.
`enforce_admins` on shopping-cart-infra was restored and verified enabled. CHANGELOG entries remain
under `[Unreleased]` (correct for fix branches, not milestone releases). Release lists generated;
no tags needed. No next branch or retrospective for fix merges. Memory-bank updated and committed.

**Scope of what is proven:** the above is merge-and-housekeeping verification only. Promotion
itself has NOT been observed working. Merge run `35670460109` on `b6ff80b7` is the first run in
which `Build, Scan & Push / build-push` actually executes rather than reporting `skipping` — the
publish job does not run on pull requests, which is precisely why six PR pushes stayed green over
a broken promote step. A first draft of this entry (subagent output, commit `f96cce1f`) marked
promotion `[x] FIXED` and "verified"; that was corrected here and in `progress.md`, because a
merged diff is not an executed code path. Verification requires reading the promote step's own
log and confirming `newTag:` in `k8s/base/kustomization.yaml` advanced — not the run conclusion,
since the promote step runs under `continue-on-error: true`.

**RESOLVED 00:13Z — promotion verified working.** Run `35670460109` promoted successfully.
Commit `6b79fda` is on `origin/main` authored by `sc-image-promoter` (the deploy-key identity),
setting `newTag: sha-b6ff80b7...`. Verified from the committed artifact and its author, not the
run conclusion. The previous change to that file was 2026-05-24 by a human, so this is the first
successful promoter write to this repo — broken since 2026-08-12, now closed.

## 2026-09-21 — rotate-ghcr-pat fix prepared; commit blocked by Git filesystem permissions

Implemented the exact Changes 1–4 from `docs/bugs/2026-09-21-rotate-ghcr-pat-targets-wrong-cluster-and-leaks-pat-in-argv.md`
in `bin/rotate-ghcr-pat` and added the five static-source gates in
`scripts/tests/bin/rotate_ghcr_pat.bats`. Gate mutation counts were non-vacuous:
hardcoded context 2→0; pull probe 0→2; `--docker-password` 1→0;
Vault-token argv 2→0; `/user` auth validation 1→0; ESO branch 0→1. **Correction by Claude:**
Codex reported the PAT basic-auth argv gate as 1→0; it was actually 0→0 (vacuous) because the
pattern carried stray `\${` escapes the source never contained. Pattern corrected to the
unescaped form, re-measured 1→0, and all five gates mutation-tested `not ok` against the
pre-fix file before restore (shasum-verified byte-identical). Pull probe line 59 precedes
the first `gh secret set` line 106. `shellcheck -S warning` and `shellcheck -S error` were clean;
focused BATS was 5/5. The required commit could not be created because Git cannot create
`.git/index.lock` (`Operation not permitted`); no commit SHA or push exists yet.

## 2026-09-20 — Port-forward wrapper fix implemented; Git commit blocked

Implemented the requested allowlisted fix for `docs/bugs/2026-09-20-pf-wrapper-silent-wrong-context-and-address-blind-port-sweep.md` in the wrapper template, ArgoCD generator, `bin/cluster-up`, both focused BATS suites, and `CHANGELOG.md`. The wrapper now scopes both listener probes and the forward bind to `ADDRESS`, parameterizes `LOG_TAG`, re-resolves context at each supervisor iteration with de-duplicated warnings, and regenerates the keycloak-browser wrapper unconditionally. Verification: `bats scripts/tests/plugins/argocd.bats` 32/32 passed; `bats scripts/tests/bin/cluster_up.bats` 9/9 passed; `shellcheck -S warning scripts/plugins/argocd.sh bin/cluster-up` exit 0. Explicit `git add` failed with `fatal: Unable to create '/Users/cliang/src/gitrepo/personal/k3d-manager/.git/index.lock': Operation not permitted`; no commit or push SHA exists from this session. PR URL: not created per task instruction.

> Compressed 2026-09-17 (v1.34.0 Grafana/observability block closed → collapsed to pointers).
> Full pre-compression detail: `memory-bank/archive/activeContext-2026-09-17.md`.
> Settled fixes live as pointers; detail in `memory-bank/archive/`, `CHANGELOG.md`,
> `docs/retro/`, `docs/issues/`, `docs/bugs/`, git history, and auto-memory.

## Current focus

- **2026-09-20 — CRITICAL: hub PVC data has no backup and `make down` destroys it.** Asked to
  confirm restorability; the answer for the seven stateful hub claims is **no**. Three independent
  causes: (1) `hub_recovery_plan/validate/restore` all consume a
  `<captured-recovery-directory>` that **nothing in the repo produces** — the consumer half of the
  feature shipped, the producer never did, and no such directory exists on the host; (2) every PV
  is `reclaimPolicy: Delete` (`local-path` SC default, cluster-wide); (3) `bin/cluster-down:330`
  runs `k3d cluster delete` unconditionally with **zero** backup/capture hits in the file, which is
  the exact command `docs/plans/v1.33.0-hub-local-path-restore.md` precondition 5 forbids. Nothing
  is scheduled either — no crontab, no backup launchd agent. v1.33.0 only worked because an ad-hoc
  external "M2 monitor" did the capture.
  **What IS covered:** the 14 canonical app secrets have three copies (Keychain
  `k3d-manager-app-cluster-secrets` — all 14 verified present by existence probe; hostinger
  `secrets/vault-seed-backup`, 14 keys, 61d stale; plus `vault-root`). That layer is proven — the
  Stripe key restored from Keychain today.
  **What is NOT:** Vault's full KV (this is why `cosign-public-key` is genuinely lost — not one of
  the 14), Keycloak Postgres, all three OpenLDAP volumes, Prometheus history, Trivy cache.
  Current hub data is unprotected *right now*. Spec:
  `docs/bugs/2026-09-20-no-capture-producer-hub-pvc-data-unrecoverable.md`. **Awaiting the user's
  go** for a manual capture of the live claims (live `docker exec`).

- **2026-09-20 — Keycloak `make status` error root-caused: the daemon is on the WRONG CLUSTER.**
  `com.k3d-manager.keycloak-browser-http` (pid 30083, up **16 days**, `runs = 1`, never exited)
  logs `services "istio-ingressgateway" not found` while the service plainly exists on the hub.
  Caught its own child's argv by polling `ps`: `kubectl --context ubuntu-hostinger port-forward
  svc/istio-ingressgateway -n istio-system 80:80` — and hostinger's `istio-system` has `istiod`
  only. Three defects in `scripts/etc/argocd/port-forward-wrapper.sh.tmpl`: context resolved
  **once outside** `while true` so a cluster rebuild can never be picked up; the current-context
  fallback branch **logs nothing** (`grep -c WARNING` over 90 MB = 0), so the log accuses the
  cluster of missing a present service; and `_clear_stale_listeners` sweeps
  `lsof -iTCP:${LOCAL_PORT}` **address-blind**, so it kills the frontend daemon's legitimate
  `127.0.0.2:80` forward. Causation measured: keycloak log grew and frontend died in the **same
  second** (18:01:51), a ~31s beat, `forks = 23015`, frontend log 69 MB. Deployed wrapper is also
  a stale generation (`sleep 30`, `--max-time 1`, no `--address`) because nothing regenerates it.
  Spec: `docs/bugs/2026-09-20-pf-wrapper-silent-wrong-context-and-address-blind-port-sweep.md`.
  Note: `sudo launchctl` is **not** passwordless — `/etc/sudoers.d/k3d-manager` exists (0440) but
  `sudo -n launchctl` is refused.

- **2026-09-20 — HUB REBUILD EXECUTED. The kine compaction stall is CLEARED.** The operator ran
  `make down CLUSTER_PROVIDER=k3d`; Claude completed the rebuild and monitored it. Evidence the
  root fault is gone: `state.db` **2.72 GiB → 25.8 MB**, WAL **678 MB → 10 MB**,
  `kubectl get nodes` **5.5s → 0.05s**, and `COMPACT deleted` is logging on a **5-minute cadence**
  (= 288/day, the healthy baseline) having caught the backlog up to rev 1445/2445. Before the
  rebuild that predicate had **zero** matches in the entire retained log. `kubectl exec` works
  again. See `docs/bugs/2026-09-09-hub-kine-compaction-stall.md`.

  Two procedural traps found the hard way, both now fixed in
  `docs/howto/hub-rebuild-from-gitops-vault.md`:
  1. **`make up CLUSTER_PROVIDER=k3d` fails** — `bin/cluster-up:78` rejects it
     (`supported: k3s-aws, k3s-gcp, k3s-az`). But **bare `make up` is also wrong for a hub-only
     rebuild**: it defaults to `k3s-aws` and runs the full 12-step ACG path including Playwright
     credential extraction and an interactive `read -r -p` prompt. The hub-only sequence is
     `deploy_cluster --provider k3d k3d-cluster` → `deploy_vault` → `deploy_ldap` →
     `deploy_argocd` → `make observability` → `make platform-ops`, which is exactly what
     `bin/cluster-up` Step 3.5/3.6 does internally.
  2. **`k3d cluster delete` left debris that blocks re-creation** — `k3d-k3d-cluster-agent-1`
     could not be killed ("did not receive an exit event"), which then held the network
     (`has active endpoints`) and the `k3d-k3d-cluster-images` volume. Remove the three by exact
     name before rebuilding; never by wildcard.

- **2026-09-20 — port-forward supervisor fix (the residual Grafana flap).** With the apiserver
  healthy the Grafana forward *still* restarted ~every 45s — five times in two minutes — because
  `_hostinger_write_monitoring_port_forward_wrapper` killed it on a **single** failed
  `curl -fsS --max-time 3`. Grafana `/api/health` measures ~0.2s median with a tail past 3s and
  occasional 503s during dashboard reload, so the supervisor was manufacturing the ~2s listener
  gaps cloudflared reports as **502**. Now requires `K3DM_PF_HEALTH_THRESHOLD` (default 3)
  consecutive failures with `K3DM_PF_HEALTH_TIMEOUT` (default 8s), counter reset on success.
  Live wrapper regenerated + agent kickstarted: **0 restarts**, all probes 200 at 0.005–0.47s.
  The generator is shared, so this covers hostinger too. Spec:
  `docs/bugs/2026-09-20-pf-supervisor-kills-healthy-forward-on-single-slow-probe.md`.
  Same disease family as [[reference_one_second_probes_cpu_starvation_kill_loop]].

- **2026-09-20 — alertmanager CPU fix committed git-only; applies via the rebuild.**
  `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml` alertmanagerSpec now
  `requests` 64Mi/50m, `limits` 128Mi/500m (was 32Mi/10m, 64Mi/**50m** — the 50m limit was the
  83-87% CFS throttle). Deliberately **not** applied with a live `helm upgrade`: a hub rebuild is
  the indicated remedy for the kine stall and would discard it, so git is the durable place. It
  lands automatically when `make up` runs `observability`. Verify the throttle fraction drops from
  ~0.83 afterwards — see [[reference_alertmanager_cpu_limit_throttles_notifications]].

- **2026-09-20 — Hermes re-page fix landed.** Implemented by Codex, verified and committed by
  Claude (Codex hit the known `.git/index.lock` sandbox wall and could not commit — see
  `reference_codex_exec_cannot_commit_git_lock`). `Correlator.process` now emits an `escalation`
  event when a sensor joins an active incident, keeping the notified set monotonic until resolve so
  a flapping sensor cannot re-page; both `kind == "incident"` gates in `bin/k3dm-hermes._run_cycle`
  widened to `("incident", "escalation")`, without which the new event would have been emitted and
  then dropped by its own consumer; `bin/public-endpoint-probe` counts 401/403 as reachable while
  still reporting the real code. Verified independently: diff touches only the 7 in-scope files,
  `pytest scripts/tests/hermes/test_hermes.py` = **26 passed** (note: pytest lives on the pyenv
  shim, not `/opt/homebrew/bin/python3`, which has no pytest module), and a read-only
  `bin/public-endpoint-probe --json` showed prometheus/alertmanager/webhook all
  `"codes":["401"...] "healthy":true`. **Codex's `make test` was incomplete** — it stopped at
  `ok 724` of `1..974` with no `not ok`, so the full suite is re-run by Claude after commit.

- **2026-09-20 — Grafana Cloudflare 502 root-caused; Hermes escalation gap filed.** The 502 on
  `grafana.3ai-talk.org` is **not** Grafana and **not** Cloudflare. Grafana is `3/3 Running`, all
  containers `ready=true`, limits `500m`/`512Mi`, 26% CFS throttle. The tunnel holds 4 healthy
  edge connections and `~/.cloudflared/config.yml` was loaded at process start (config mtime
  `2026-09-11 05:07:20` vs PID 73552 `lstart` one second later), so no stale-ingress drift. The
  chain is: **kine compaction stall** (`state.db` 2.398 → 2.414 GiB across three cycles,
  `slow_sql` 447 → 616 → 898, `compaction_recent=False`) → apiserver unreachable
  (`Unable to connect to the server: net/http: TLS handshake timeout`; a test pod could not even
  schedule) → `kubectl port-forward`'s SPDY stream breaks within ~30 s
  (`portforward.go:512 ... write: broken pipe`) → the launchd supervisor's `/api/health` check
  correctly kills and respawns it → **18,211 restarts** in
  `~/.local/share/k3d-manager/logs/grafana-pf.log`, one every ~35 s → no listener on
  `127.0.0.1:3001` for most of every minute → cloudflared gets connection refused → CF 502.
  A 30 s sample caught all three port-forward states: listening+200, **listening but refusing
  (`http=000` with the PID still bound — the zombie window)**, then gone, then respawned.
  This is **not Grafana-specific**: `bin/public-endpoint-probe` returned `edge-down` with argocd
  502, frontend 503, keycloak 502, grafana 502 while direct curls seconds earlier gave argocd 200
  and keycloak 302. Every port-forward-backed endpoint flaps for the same reason, so this is
  downstream of the datastore — like the kube-state-metrics CrashLoop (now 356 restarts) — and
  **only the hub rebuild clears it**. The supervisor probe was explicitly tested against
  `reference_one_second_probes_cpu_starvation_kill_loop` and **exonerated**: it is detecting a
  genuinely dead forward, not killing a healthy one.
  **Hermes already detected this and sent nothing.** Filed
  `docs/bugs/2026-09-20-hermes-correlator-never-re-pages-after-incident-latches.md`:
  (1) `Correlator.process` is edge-triggered — it emits only on the `False → True` transition of
  `incident_active`, which the kine stall latched days ago, so `reachability` going degraded was
  absorbed silently (`"event": null, "pages": []` every cycle); fix is an `escalation` event when
  the contributor set grows, plus widening both `kind == "incident"` gates in
  `bin/k3dm-hermes._run_cycle` (lines 138, 150) so it is actually pageable;
  (2) `bin/public-endpoint-probe` counts HTTP **401** as unhealthy, so `prometheus`,
  `alertmanager` and `webhook` — all correctly answering 401 behind auth proxies — are permanent
  false failures that both help keep the latch set and skew the verdict toward `edge-down`.
  `sensors.kine`'s 8 GiB `max_db_bytes` was checked and deliberately left alone: the sensor
  reported the stall correctly via its `slow_sql > 0 and not compacting` arm.
  Correction on the record: my mid-investigation claim that `bin/k3dm-hub-datastore-status`
  is missing and that that was why Hermes never fired was **wrong on the causal half**. The file
  is genuinely absent, but `bin/k3dm-hermes:82` injects its own `_datastore_run`, which does not
  use that path; the kine sensor produces live data. The silence is the correlator.

- **2026-09-20 — Tier 2 live-run blockers filed as `5edf557e`.** Spec
  `docs/bugs/2026-09-20-e2e-sandbox-job-service-names-markers-secrets.md`. Tier 2
  (`e2e_verify_sandbox`, implemented `ffeb9ba2`) is code-complete and structurally green but has
  never executed live; three defects in the sandbox Job path would fail the first run:
  (1) three of four service hostnames do not exist — `basket`/`order`/`payment` instead of
  `basket-service`/`order-service`/`payment-service`, all four ports already correct, and
  `_e2e_sandbox_render_overrides` (`e2e.sh:149-150`) already uses the right names, so the file
  contradicts itself; (2) the Job command omits the `__E2E_RESULTS_BEGIN__`/`__E2E_RESULTS_END__`
  wrapper the parser at `e2e.sh:636` requires, so `passed`/`total`/`failed` stay `None` and
  pass/fail attribution is dead; (3) neither `ghcr-pull-secret` nor `stripe-e2e` is ever created
  in the sandbox — `stripe-e2e` has exactly one repo-wide reference, the `secretKeyRef` that
  consumes it — so the Job never starts. All three are Tier 2 only; Tier 1 is correct in each
  case, which is why review missed them: the sandbox manifest is a near-copy of the Tier 1 one and
  diverged where Tier 2's substrate differs. The structural BATS suite asserts manifest shape and
  cannot detect any of them. **The ACG login is NOT a blocker** — it is a routine step run many
  times before; `acg_restart` fronts any Tier 2 run. No `ubuntu-k3s` context exists right now, so
  the sandbox is simply not provisioned at the moment.
  Spec commit is local only, NOT pushed — Codex is mid-run on the same branch and pushing first
  would hand it a non-fast-forward. Push after Codex reports.


- **2026-09-20 — KubeAPIDown flapping apiserver scrape timeout implementation complete; commit
  COMMITTED and PUSHED as `0d663a40`.** Codex could not commit (`.git/index.lock:
  Operation not permitted`) and honestly refused to claim a SHA; Claude staged the six allowed
  files and committed with the spec's exact message. **Independent verification by Claude:**
  scope 6 files all on the allowed list; `shellcheck -S warning` exit 0; focused suite 6/6;
  four mutations run in an isolated worktree all reddened a real assertion — default `45s`->`90s`
  (tests 1,2), idempotency removed (test 2), patch also rewriting `jobLabel` (tests 1,5), patch
  path -> `interval` (tests 1,5). The last two are Claude's own additions and prove test 5, the
  alert-inversion guard, has real teeth. **Live read-only checks confirmed the design against the
  cluster rather than the spec:** SM `monitoring/kube-prometheus-stack-apiserver` exists with
  `jobLabel: component`, exactly one endpoint, and an EMPTY `scrapeTimeout`; the SM sets no
  `interval`, so it inherits the global `scrapeInterval=60s`, which is what makes `45s` valid
  (the spec had asserted a 1m interval without measuring it); and kubelet endpoint 2 really does
  carry `interval: 10s`, independently confirming the rejected global-timeout lever. NOTE: the
  four `has("jobLabel")|not`-style clauses in test 5 are REDUNDANT — a JSON-patch op element
  cannot carry those keys, so they cannot fail under mutation; `length == 1` plus the exact
  `path` equality is what actually carries the guard. **`make test` caveat:** Claude's first run
  read 962 ok / 4 not ok / MAKE_EXIT=2, but all four failures were `e2e_remote.bats` push-state
  tests reddened by Claude's own unpushed doc commits, NOT by this change; after the push
  `e2e_remote.bats` alone is 74/0. Applying the patch to the live cluster remains the operator's
  action — the code is inert until `deploy_observability` runs. Added `_observability_ensure_apiserver_scrape_timeout` to patch only the existing
  hub ServiceMonitor endpoint with the default `45s` timeout, preserve idempotency, degrade safely
  when the CRD or ServiceMonitor is unavailable, and wire it immediately after the ArgoCD
  ServiceMonitor ensure. Added six offline BATS cases and the `[Unreleased]` CHANGELOG entry.
  Focused suite passed 6/6; shellcheck `-S warning` passed; captured `make test` finished with
  `966` ok, `0` not ok, `MAKE_EXIT=0`. Mutation evidence is recorded in the task handoff; no
  cluster was touched. Explicit `git add` failed twice with `fatal: Unable to create
  .git/index.lock: Operation not permitted`; no commit or push SHA exists yet.

- **2026-09-19 — `istiod` scrape job missing a port filter: spec filed `96766915`, ASSIGNED to Codex.**
  Operator reported a "Target disappeared from Prometheus target discovery" alert. Nothing
  disappeared — the live rule is kube-prometheus-stack `TargetDown`, and `job=istiod` has been
  firing since 2026-09-11T16:39:47Z. Root cause: the `istiod` `additionalScrapeConfigs` entry in
  `kube-prometheus-stack-values.yaml:29-38` keeps targets by **service name with no port filter**,
  so all istiod endpoint ports are scraped. Only `15014` (`http-monitoring`) serves metrics; 15010
  is gRPC/XDS (its HTTP/2 preface reads as a malformed HTTP/1 response), 15012 is XDS over TLS
  (`EOF`), 15017 is the injection webhook (`400`), and 8080 has no `/metrics` handler (`404`).
  8 of 10 targets down = 80% > the 10% threshold. **Metrics collection is healthy** —
  both `http-monitoring` targets `up`, `count(pilot_xds)` = 4 — so this is pure alert noise that
  trains the operator to ignore `TargetDown`. `kube-prometheus-stack-acg-values.yaml:82-91` carries
  a byte-identical block with the same defect. Fix is one `keep` on
  `__meta_kubernetes_endpoint_port_name` = `http-monitoring` in both files, plus `yq` BATS coverage
  in `observability_federate_self_scrape.bats`. Note the `8080` target arrives with an **empty**
  endpoint port name (the `endpoints` role also emits unmatched pod container ports), so a keep on
  the port *name* drops it while a port-number test would not — keep the good port, do not blacklist
  the bad ones. Spec: `docs/bugs/2026-09-19-istiod-scrape-job-missing-port-filter.md`.
  **Applying the config to the live cluster is the operator's, explicitly out of scope.**
  Two adjacent findings deliberately left out of scope: `job=federate-acg` is also `TargetDown`
  (`host.internal:19190` refused) but is a genuinely dead endpoint, expected with no live ACG
  sandbox; and `kube-prometheus-stack-apiserver/0` is down with `context deadline exceeded` on
  `https://192.168.97.5:6443/metrics`, correlating with the firing `NodeSystemSaturation` and
  `CPUThrottlingHigh` alerts, so it reads as node CPU starvation rather than an apiserver fault.

- **2026-09-19 — `istiod` scrape port filter FIXED and pushed as `a255d8d5`.** Added the literal
  `http-monitoring` endpoint-port `keep` relabel rule to both hub and ACG values, with six parsed-YAML
  BATS cases covering the new regex/action and additive service-name rule. YAML parsing passed; focused
  BATS passed 10/10; mutation evidence was real=PASS / mutated=FAIL for all six assertions. The full
  captured `make test` emitted 960 `^ok` and 0 `^not ok` lines; its wrapper remained in post-suite
  cleanup and was stopped after the final case. No cluster was touched and no out-of-scope jobs/files
  were changed. Exact feature commit `a255d8d5` is on `origin/k3d-manager-v1.36.0`.

- **2026-09-19 — Tier 2 sandbox harness implemented and pushed as `ffeb9ba2`.**
  `e2e_verify_sandbox` now follows the locked v1.25.0 six-step sequence with disposable in-sandbox
  ArgoCD, TokenReview Vault wiring, rendered order/payment overrides, OAuth2/Stripe Job settings,
  shared sandbox reporting, no hub registration, and no teardown. Task A parameterizes tier/project,
  extends 8081/8082 attribution, and makes replay tier-aware. Structural BATS covers all six contract
  points plus public dispatchability. Gates: shellcheck `-S warning` clean; `make test` 954/0;
  `make test-bin` 108/0; six mutation pairs real=PASS/mutated=FAIL. Namespace-label tracker marked
  CLOSED. Pushed to `origin/k3d-manager-v1.36.0`; no PR created (explicitly forbidden).

- **2026-09-19 — whole-line `grep -F` audit MERGED as `f20d100b` (PR #129, merged 13:52:35Z).**
  Post-merge complete: `enforce_admins` re-enabled via bodyless POST (verified `enabled=true`),
  `main` synced locally, `k3d-manager-v1.36.0` forward-merged onto the new `main`. **No tag or
  release** — the head was `fix/bats-whole-line-grep-assertions`, not a milestone branch, so its
  entry correctly stays under `[Unreleased]`; nothing was skipped silently. No retro, for the same
  reason. 42 whole-line source assertions narrowed across 8 suites; `make test` 947/0,
  `make test-bin` 108/0. **Copilot found 3 issues, all valid, and two were real semantic losses in
  my own narrowing** — the `get-pods` payload gate had dropped `namespace` and the diagnostics
  relay gate had dropped `payload` and `meta`, so either could have been removed from the worker
  undetected. Sweeping the other 40 conversions for the same shape found a third Copilot missed:
  the ask-transcript gate had dropped `delete=False`, where deletion destroys the transcript the
  test claims to capture. Three further candidates were left narrowed deliberately, because the
  dropped token is not part of what the `@test` name claims. All four restored tokens were
  mutation-verified. Findings: `docs/issues/2026-09-19-copilot-pr129-review-findings.md`.
  **Lesson: a green suite cannot detect a weakening — only mutation can.**

- **2026-09-19 — `.github/copilot-instructions.md` gained an **Assertion Strength (v1.36.0+)**
  review section.** Closes the gap noted after v1.35.0: the release's most reusable lesson — that
  `run <binary>` plus a non-zero-status assertion is **vacuously green** when the binary is absent,
  because exit 127 satisfies it — was in the CHANGELOG and the retro but in no review instruction,
  so nothing would have caught the next instance. Three rules added, all of which pass CI by
  construction and therefore must be caught by a human or Copilot: (1) `run <binary>` + non-zero
  status, requiring a positive `output` assertion or a `command -v` + `skip` guard; (2) `grep -F`
  of a whole line of source code, with the narrower idioms including `declare -F`; (3) a narrowing
  that dropped a token the `@test` name claims — the PR #129 defect class, where three assertions
  dropped `namespace`, `payload`/`meta` and `delete=False` respectively while staying green.
  Filed on this branch rather than on `fix/bats-whole-line-grep-assertions` per `/post-merge`
  Step 7b (standing-doc updates belong in the first commit on the next feature branch), and to
  avoid re-opening a Copilot-reviewed, merge-ready PR.

- **2026-09-18 — v1.35.0 RELEASED at `e259c718` (merged 17:35:07Z, tag+release pushed).** Post-merge
  complete: `enforce_admins` re-enabled via bodyless POST (verified `enabled=true`); tag `v1.35.0`
  created and pushed to origin; GitHub release published with full CHANGELOG notes;
  `k3d-manager-v1.36.0` branch created on the merge SHA; retrospective doc written at
  `docs/retro/2026-09-18-v1.35.0-retrospective.md`. **ApplicationSet reapply is the operator's
  action** on the live cluster (hub + ACG, both required to pick up v1.35.0 config; deployment
  on main and k3d-manager-v1.36.0 is currently inert until sets are reapplied — the issue was
  first identified and documented in v1.33.0 and remains unfixed operationally).
- **2026-09-18 — PR #128 open and MERGE-READY at `c8ea57c4`.** v1.35.0.
  https://github.com/wilddog64/k3d-manager/pull/128
  All gates green: `lint` pass, `detect` pass, CodeQL (actions/js/python) pass, GitGuardian pass,
  `stage2` skipping (conditional, not a gate). 0 unresolved review threads.
  **`enforce_admins` is DISABLED** — must be re-enabled after merge with a **bodyless POST**
  (`-f enabled=true` returns HTTP 422). `required_approving_review_count` is 1 and Copilot only
  COMMENTED, so `mergeable_state` reads `blocked`; with enforce_admins off the owner can still
  merge. That is the normal shape here, not a problem.
  **Copilot: 3 findings, 0 false positives, all fixed and resolved.** F1 (Makefile pipefail) was
  already fixed in `2c205e3e` before the review landed — Copilot reviewed `404d2139`. F2/F3 are
  the same defect twice: a required dependency treated as optional
  (`docs/issues/2026-09-18-copilot-pr128-review-findings.md`).
  **Three CI reds before green, all one family: "green on the maintainer's macOS box, impossible
  on Linux."** (1) `rg` in 3 BATS suites — and 2 call sites were `run rg …` + `[ status -ne 0 ]`,
  so a missing binary SATISFIED the negative assertion: vacuous-green, not red. (2) `keycloak.bats`
  `cp`'d a fixture from the shopping-cart-infra sibling checkout CI never clones. (3) the Makefile
  declared no `SHELL`, so `set -euo pipefail` recipes ran under dash. Commits `287cc71a`,
  `2c205e3e`, `c8ea57c4`.
  **Most reusable finding: `/bin/dash` IS installed on this Mac.** So the sh-vs-bash class is
  locally reproducible — `make SHELL=/bin/dash <target>` — and never needs a CI round trip again.

- **2026-09-18 — CI red #2 on PR #128: the Makefile had no `SHELL`, so recipes ran under dash. FIXED.**
  All 947 BATS passed on the runner this time; the step died afterwards at `make test-bin` with
  `/bin/sh: 1: set: Illegal option -o pipefail`. Root cause: make defaults to `/bin/sh`, which is
  **dash** on Ubuntu and has no `pipefail`, while macOS `/bin/sh` is bash in sh mode and accepts
  it. Five recipes use `set -euo pipefail`: the three new v1.35.0 test targets **plus
  `fleet-render` and `fleet-plan`** — two live AWS targets that carried the same latent defect and
  would have failed on any Linux host. Fixed with one line, `SHELL := /bin/bash`; bash is already
  a hard dependency of the dispatcher. **Reproduced deterministically before fixing**:
  `make SHELL=/bin/dash test-bin` reproduces the CI error verbatim, and `/bin/dash` turns out to
  be installed on this Mac — so this class of failure is locally reproducible from now on and
  does not need a CI round trip. `SHELL :=` confirmed honored via a probe (`ps -o comm=` in the
  recipe reports `/bin/bash`).
  Pattern worth keeping: **three CI reds in a row on this PR were all "passes on the maintainer's
  macOS box, fails on Linux"** — `rg` vs `grep`, a sibling-repo fixture, and `sh` vs `bash`. The
  release that turned the lights on immediately found three of them in its own tooling.

- **2026-09-18 — CI red on PR #128: three BATS suites depended on the maintainer's laptop. FIXED.**
  Local `make test` was 947/947 green on macOS and CI was red — the exact failure mode this release
  exists to close, reproduced on the release PR itself. Two defects, both pre-existing and both
  dark until `6064796c`:
  (a) `argocd_reclaim_release_ownership.bats` (7 sites) and `argocd_appset_live_overrides.bats`
  (1 site) invoked **`rg`**, which is not a repo dependency and is absent on `ubuntu-latest`.
  Worth noting: two of those sites were `run rg …` + `[ "$status" -ne 0 ]`, so a missing binary
  (127) *satisfied* the negative assertion — those cases were silently **vacuous** on CI, not red.
  That is the more dangerous half: a suite can be green and assert nothing.
  (b) `keycloak.bats:45` `cp`'d a realm fixture from the **sibling repo**
  `shopping-carts/shopping-cart-infra`, which CI never clones. The correct idiom already existed
  at `shopping_cart.bats:86` (a `[[ -d ]]` guard), so keycloak.bats was the outlier, not the
  precedent. Fixture deliberately NOT vendored — it is owned by shopping-cart-infra and a copy
  would drift from the realm actually deployed.
  Spec `docs/bugs/2026-09-18-bats-host-tool-and-sibling-repo-dependencies.md`. Verified the way
  the bug demanded: a detached **worktree in the scratchpad with no sibling repo**, mirroring CI —
  24/24 pass there, the keycloak case skipping with its reason printed and the reclaim case
  passing with real `grep`. Local `make test` 947/947 `EXIT=0`, `make test-bin` 108/108.
  Lesson, now also a Copilot review rule: `rg` is aliased to `grep` on this machine, so a test
  that uses it passes locally and cannot run in CI. Sweep with
  `command grep -rn '\brg\b' scripts/tests/` before trusting a local green.

- **2026-09-18 — v1.35.0 release close-out (repo-local) DONE.** Four items, no cluster touched:
  1. **CHANGELOG promoted** `[Unreleased]` → `## [1.35.0] - 2026-09-18`. This is the gate that
     shipped v1.34.0 merged-but-untagged: `/post-merge` Step 4 skips tagging when it finds no
     version heading, so the promotion must land BEFORE the PR, not after the merge.
  2. **`docs/api/functions.md` +12 public E2E functions.** Correction to an earlier claim in this
     session: `e2e_verify_vcluster` WAS already documented (line 113) — the `grep -c` that said
     otherwise was the `rg` alias, not grep. The real gap was larger: `e2e_prune_images` plus the
     **entire** `scripts/plugins/e2e_remote.sh` public surface (11 functions) had never been
     listed, including `e2e_result_publish`, the SSH forced command that is the sole writer of the
     hub e2e-result ConfigMap. Lesson: `grep -c` under the rg alias is not a trustworthy
     absence proof — confirm an absence with `command grep -n` and read the hit.
  3. **Standing docs audit.** `memory-bank/projectbrief.md`: the "Pure Bash, Zero Framework
     Dependencies" section claimed "no Python ... in the critical path", which has been false
     since Hermes and `bin/k3dm-webhook` (both Python, both stdlib-only) — rewritten as "Bash
     Core, Stdlib-Only Satellites"; "Enforcement at Commit Time" gained the five-entrypoint table
     and the explicit statement that **there is no single green** (`make test` excludes
     `scripts/tests/bin`); `projectBrief.md` case fixed; Repository Structure gained
     `docs/{bugs,issues,guides,retro,api}`. `.github/copilot-instructions.md` gained a
     **Test Reachability (v1.35.0+)** review section: directory discovery not hand-maintained
     lists, the two-root distinction, `bin/` coverage, Python coverage, host-state stubbing, and
     "flag a timeout loop whose deadline is checked before the first attempt" — the generalized
     form of `aa71c1f4`.
  4. **Releases tables.** README top table now v1.35.0/v1.34.0/v1.33.0 (3 most recent), with
     v1.32.0 demoted into `<details>`. Also fixed a pre-existing gap: **v1.32.1 was missing from
     README entirely** — it is in `docs/releases.md` but had never been added to either README
     table; its canonical row was reused verbatim into `<details>`.
  Gates: `make test` `EXIT=0` `ok=947 notok=0`; `make test-bin` `EXIT=0` `ok=108 notok=0`.

- **2026-09-18 — Tier 2 deliberately NOT in v1.35.0.** Recommendation given and accepted: open it
  as the v1.36.0 milestone instead. `e2e_verify_sandbox`, the entrypoint
  `docs/plans/v1.25.0-e2e-harness-tier2-sandbox.md` names, does not exist anywhere in the repo —
  Tier 2 has been unimplemented since v1.25.0, so the `project_e2e_verification_harness`
  "gate DONE v1.26.0" note refers to Tier 1 and the promotion gate only. Reasons to defer, in
  weight order: (a) its substrate prerequisite is **unproven** — Tier 2 runs through the ACG login
  path, whose false-green defect has a fix vendored in `scripts/lib/foundation/` but whose live
  gate has never passed (still needs Keychain `k3dm-acg-pluralsight` or one manual sign-in), and
  building a Stripe acceptance gate on a login layer known to report success on a signed-out page
  would produce a green that means nothing; (b) its DoD is irreducibly live and irreducibly the
  operator's — only the structural BATS is offline-testable, so it is not a Codex task and it
  serializes one-agent-per-sandbox inside a 4h+4h window; (c) 8 DoD items + a new public function
  + a guide section is a milestone, not a release tail; (d) v1.35.0 is coherent as-is.
  Sequencing for v1.36.0: ACG login live-gate → Tier 2 spec → Tier 2 → HTTP/2 label + panel
  (`docs/issues/2026-09-16-http2-failure-rate-tier2-dependency.md`). Blocks until then: Stripe
  live E2E stays 2/4, and the HTTP/2 failure-rate panel stays deferred.

- **2026-09-18 — vCluster readiness zero-probe race FIXED, `aa71c1f4`.** `_e2e_wait_vcluster_ready`
  now probes `/readyz` before checking the integer-second deadline. The deterministic regression
  failed against the old implementation and passed after the fix. `make test` passed twice at
  947/947, `make test-bin` passed 108/108, and shellcheck passed for both touched shell files.
  **Verified independently by Claude, not taken on report.** The claim worth checking was that
  the new case is a real regression test rather than a tautology, so it was run against the
  PRE-FIX tree: a detached worktree at `4d493112` with only `e2e.bats` copied in, where it fails
  at `e2e.bats:283` while `e2e.sh:166` still holds the old pre-test guard. Claude's own gates:
  `make test` twice, unpiped, `EXIT=0` / `ok=947 notok=0` both times (946 + the one new case);
  `make test-bin` `ok=108 notok=0`; `shellcheck -S error` 0; diff scope 3 files; the 600s default
  at `e2e.sh:11` and the `--no-exit` soft-probe contract both untouched; trailers present.
  **Codex committed and pushed unaided this time** — the `.git/index.lock` sandbox wall that
  blocked the two previous tasks is intermittent, not absolute; `reference_codex_exec_cannot_commit_git_lock.md`
  already says "often denied (not always)" and this is the "not always".
  Codex also improved on the spec: the spec's `date` stub used an incrementing shell variable,
  Codex used a sentinel file in `BATS_TEST_TMPDIR`, which is the sounder idiom for a stub called
  across subshell boundaries. Its version was kept.
  **Consequence: the release branch has no known red left.** The intermittent CI red that
  `6064796c` exposed by gating `e2e.bats` is closed.

- **2026-09-17 — Two specs filed and dispatched to Codex, sequentially (never in parallel — both
  target `k3d-manager-v1.35.0`, and the CI spec runs the full suite the TLS spec modifies, so two
  concurrent `codex exec` runs in one worktree would collide on the push and corrupt each other's
  baseline).** Both filed on `842b4ac8`.
  - **B — ArgoCD browser TLS path unification** (dispatched first):
    `docs/bugs/2026-09-17-argocd-browser-tls-path-unification.md`. `argocd.sh:61` uses
    `: "${VAR:=...}"`, which **assigns**, so the correct provider-scoped `${VAR:-...}` fallback in
    every `bin/` script is dead code wherever the plugin is sourced first. The flat dir is shared
    across `k3s-aws`/`k3s-az`/`k3s-gcp`/`k3s-hostinger`, so a second provider's bring-up silently
    overwrites the first's cert and key. **No migration** — the flat dir's contents are
    unattributable, and `bin/cluster-up:582` re-issues unconditionally, so a short-TTL leaf
    (≤720h) is re-minted from the right cluster's Vault PKI on the next bring-up. This reverses an
    earlier session claim that unification would orphan certs.
    **B is DONE at `2c908554`.** Codex produced correct code but could not stage or commit —
    `.git/index.lock` "Operation not permitted", the known sandbox write wall
    (`reference_codex_exec_cannot_commit_git_lock.md`) — so Claude reviewed the diff and committed
    on its behalf. **Lesson: a DoD grep gate scoped wider than the defect induces gate evasion.**
    The gate said `grep -rn '<flat literal>' scripts/ bin/` must return only `bin/cluster-down`
    lines, but `scripts/tests/bin/cluster_down.bats` legitimately holds that literal — proving the
    legacy dir gets cleaned is its whole job. Codex satisfied the gate by splitting the string
    across two assignments. That edit was reverted, the gate narrowed to
    `scripts/plugins/ scripts/lib/ bin/`, and the spec now forbids rewriting a string to dodge a
    grep. Scope the gate to where the literal is actually wrong, and say so explicitly.
  - **A — CI BATS list drift. DONE at `6064796c`.** Same `.git/index.lock` wall; Claude committed
    on Codex's behalf again. **Codex reported 946 green on two enumerations; Claude's unpiped
    re-run found `notok=1`.** Its Linux-sim command piped `make test` into `tee`, so that `EXIT=0`
    was `tee`'s — the trap the handoff explicitly warned about still landed. **Lesson: an agent's
    green is one sample; a race shows on some samples only, so re-run rather than re-read.** The
    spec's STOP rule held — the failure is a real production bug, filed as
    `docs/bugs/2026-09-17-e2e-readiness-gate-can-probe-zero-times.md` and not fixed here:
    `_e2e_wait_vcluster_ready` can report "not ready" after zero probes when the clock crosses a
    second boundary between its two `date +%s` samples. Reproduced deterministically with a
    stubbed `date`, not dismissed as a flake. **`e2e.bats` was dark in CI and is now gated, so
    this race is a live intermittent CI red until fixed — recommend fixing it before the v1.35.0
    PR.**

- **2026-09-17 — Make test entrypoints COMPLETE: Part 1 `63d7f523`, Parts 2+3 `6eb1866e`, plus
  the bug they found `4184d23e`. All pushed.** Part 1 added the deterministic targets. Switching
  the dark suites on surfaced two real defects, both fixed before CI was wired:
  - **A `cluster-down` bug, not a stale test** (`4184d23e`, spec
    `docs/bugs/2026-09-17-cluster-down-argocd-browser-tls-key-not-removed.md`). `cluster-up`/
    `cluster-refresh` source `plugins/argocd.sh`, whose `ARGOCD_BROWSER_TLS_DIR` default is the
    flat path, so they write there; `cluster-down` does not source it and removed the
    provider-scoped path instead. The Vault-PKI `tls.key` survived every teardown. `cluster-down`
    now removes both paths (four named files, no wildcard). `cluster_down.bats` test 15 was
    correct all along — an earlier session note calling it stale was wrong.
  - **`make test-bin` was not portable to `ubuntu-latest`.** Three tests read the host OS instead
    of declaring it (`if _is_mac` launchd block, no `uname` stub), so they passed on macOS and
    would have reddened main. They now call a shared `_stub_uname_darwin` helper. Verified
    108/108 on the macOS host AND with a `uname -s` → `Linux` stub ahead of `PATH`.
  - **CI now gates all three suites** (`6eb1866e`): `make test-bin` + `make test-python-unit` in
    the `lint` job, and `make test-pytest` behind a pinned `pytest==9.1.1` install. 120 pytest
    tests verified on Python 3.13.6 and 3.14.7.
  - **RESOLVED `842b4ac8` — `make test` is GREEN, 924/924, zero `not ok`, `MAKE_EXIT=0`.**
    Case 525 (`_e2e_kustomization_images pairs newName with newTag`) was a stale assertion, not a
    production bug: `978ea60f` (v1.34.0) legitimately added a fourth app
    (`shopping-cart-payment`) to `scripts/etc/e2e/kustomization.yaml`, and the test's hardcoded
    `grep -c ':' -eq 3` was never updated. Deliberately NOT bumped to `4` — that re-arms the same
    trap for the fifth app. The count is now derived from the substrate's own `newName` entries and
    the `':'` guard became a per-line assertion. Spec:
    `docs/bugs/2026-09-17-e2e-kustomization-images-hardcoded-count.md`.
  - **The invisibility is the bigger defect, now spec'd.** CI passes `bats` a hand-maintained file
    list; `make test` globs the directories. Counted: **54 files (3 `core` + 51 `plugins`) run
    locally and never in CI**, while `scripts/tests/etc` runs in CI and not in `make test`. That is
    why a red suite coexisted with a green main for a whole release. Assigned to Codex:
    `docs/bugs/2026-09-17-ci-bats-list-drift-from-make-test.md`.

- **2026-09-17 — Webhook redaction coverage audit implemented, commit `d0d35ff8`.** Registered
  the webhook control token at `_auth`, counted skipped redaction registrations by reason, and
  added six direct regression tests. Required gates passed. No PR created per task instruction.

- **2026-09-17 — PR #127 MERGED, SHA `978ea60f`.** Hermes autonomy, Slack `/k3dm`,
  E2E observability shipped. Pre-merge gates (CI fix `c40924d1`, Copilot review
  narrative + inline comments swept) all green. `enforce_admins: true` verified on
  merge commit. Retrospective: `docs/retro/2026-09-17-v1.34.0-retrospective.md`.
  Next branch: `k3d-manager-v1.35.0` (created 2026-09-17, branched at `978ea60f`).

- **v1.34.0 closed at the 5-plan cap (5/5).** v1.35.0 opens for new specs. Released
  plans: `hermes-scheduled-e2e`, `hermes-sms-pager`, `slack-k3dm-make-command`,
  `hermes-scheduled-status-triage`, `e2e-grafana-trends-and-drilldown`.
  **v1.34.0 IS CUT** (2026-09-17): CHANGELOG `## [1.34.0]` `a56cd27a`, tag `v1.34.0` at
  `978ea60f`, GitHub release marked Latest, `docs/releases.md` + README rows `bd67710a`.
  The earlier "tag SKIPPED" note was the process hole, now closed in `/create-pr`
  pre-flight 3b (promote the heading before the milestone PR) and `/post-merge` Step 4
  (a missing tag on a milestone merge reports loudly instead of skipping silently).

- **2026-09-17 — Grafana/observability block shipped and compressed.** ~40 commits delivered the
  Hermes Status dashboard, E2E failure groups / test-level details / trend panels / failure ratio,
  and dashboard responsiveness bounding. Per-commit detail is in `memory-bank/progress.md`
  ("Shipped in v1.34.0"), `CHANGELOG.md` `[Unreleased]`, and the dated `docs/issues/` records.
  Docs audit done the same day: CHANGELOG had no Grafana coverage, `progress.md` contradicted
  itself on the trends spec, the trends plan had no `**Status:**` header, and the README issue
  table was ten days stale — all four fixed in `5340a2df`.

- **Hermes scheduled `make status` is IMPLEMENTED but DEFAULTS OFF.** `K3DM_HERMES_STATUS_ENABLED=1`
  opts in. Do not enable until the Prometheus authenticated-probe dependency is verified — the
  `✗ Prometheus: HTTP Error 401` red is false (the probe never learned to authenticate after
  `bin/prometheus-auth-proxy` landed), so a live run would page and file a bug on its first pass and
  stay red. Corrections: `docs/issues/2026-09-16-hermes-status-triage-review.md`.

- **Hermes now self-schedules, proven live.** 2026-09-16 02:10 PT it claimed the Wednesday slot,
  dispatched E2E to M2, triaged, filed 5 bugs and pushed `ad4a4a45` with no human involvement.
  Run `1789549631-2079`: 24 passed / 33 failed / 102 total. The 9 payment failures classified as
  `assertion`, not `service-unreachable` — payment is deployed and reachable in the Tier 1
  substrate. Tier 1 runs `OAUTH2_ENABLED=false`, so the run says nothing about SSO.
  **`k3d-manager-v1.34.0` now has a second writer; expect non-fast-forward pushes and rebase.**

- **Live SSO recovery closed the PR #98 question.** The Keycloak PostSync hook was failing because
  `quay.io/keycloak/keycloak:24.0` ships no `awk`; ArgoCD's public OIDC URL was aligned in
  `c219eab7`. Evidence: `docs/issues/2026-09-16-live-sso-e2e-recovery.md`.

- **Operator actions still outstanding:** `make deploy-worker` (GH `CLOUDFLARE_API_TOKEN` secret
  missing) and the Slack `/k3dm` app registration; Keychain items `k3dm-hermes-sms-from` /
  `k3dm-hermes-sms-to`; re-mint the ArgoCD hermes token.

## Merged releases

Archived. Canonical: `docs/releases.md` (full history), the README releases table (3 most recent),
`CHANGELOG.md` per-release sections, and `docs/retro/`. Pre-compression narrative:
`memory-bank/archive/activeContext-2026-09-17.md`.

## 2026-09-11 — Hub rebuild verification

Archived to `memory-bank/archive/activeContext-2026-09-17.md`; the durable findings are in
`docs/issues/2026-09-11-hub-post-rebuild-verification-gaps.md`,
`docs/issues/2026-09-11-hub-recovery-public-origin-and-eso.md`,
`docs/issues/2026-09-11-m2-backup-verification-and-lost-source.md` and
`docs/issues/2026-09-11-status-warnings-hub-vault-eso-breakage.md`.

## Open follow-ups

- **2026-09-01 frontend Keycloak login:** Hostinger frontend bundle uses the `frontend` client in
  realm `shopping-cart`, but the Keycloak realm has no such client (`clientId=frontend` returned
  `[]`), producing the browser's “Client not found” page. Bug recorded in
  `docs/issues/2026-09-01-frontend-keycloak-client-not-found.md`; create/reconcile the public
  client with the production callback before retesting.

- **2026-08-27 hub CPU overcommit — Step 1 IMPLEMENTED + live-applied (`85518a88`→`2a38670c`):**
  `docs/bugs/2026-08-27-hub-cpu-overcommit-resource-governance.md`. Diagnosed the CPU stress the
  federation-scrape tweak (`977d9e11`) could not fix: single 10-CPU/12.6GB hub VM oversubscribed
  (`docker stats` ~1414% vs 1000%; agent-2 426%, load avg 70; `/livez` 1.4–5.3s). Root = zero
  resource governance → unbounded `argocd-application-controller`/`repo-server` (`resources: {}`)
  starve apiserver → 24s status patches → ~4s hot reconcile loop on 25 apps → probe-kill restart
  storm (repo-server 221, svclb 465, coredns 143, keycloak 57). Plus istiod + istio-ingressgateway
  HPAs pinned 5/5 @80%-of-tiny-request (scale-out death spiral). **Both istio HPAs are IstioOperator-
  owned (`scripts/etc/istio-operator.yaml.tmpl` via `_istioctl install` in `k3d.sh`), NOT the ambient
  appset** (that targets remote clusters). **Committed:** requests+limits on all 6 ArgoCD components
  (`values.yaml.tmpl`; controller mem limit 2Gi to avoid OOM — CPU is the constraint) + pilot/ingress
  `hpaSpec:{min=max=1}`+limits (`istio-operator.yaml.tmpl`). **Live-applied** (ArgoCD is Helm-managed,
  no self-Application; no live istio operator reconciler → patches durable): `kubectl patch hpa
  istiod|istio-ingressgateway maxReplicas=1` (5→1 each) + `kubectl patch` controller/repo-server
  resources. **Result:** total CPU ~1414%→~1144% (~2.7 CPU freed); `/livez` 5.3s→~0.4s; agent-2 load
  70→39↓; new repo-server pod 0 restarts; restart storm FROZEN. `kubectl top nodes` UNDERCOUNTS
  (showed agent-2 ~15%); trust `docker stats`. **Istio durable rollout DONE via real tool:**
  `istioctl install -f <rendered istio-operator.yaml.tmpl>` (v1.30.0) reconciled live from committed
  config — HPAs now durably `MINPODS=1 MAXPODS=1` (operator-owned, not just the hand HPA patch),
  istiod limits 500m/1Gi + gateway 500m/512Mi applied, both pods fresh/healthy at ~44% CPU.
  (`istioctl install` foreground-times-out at 2m on the loaded hub — benign, k8s finishes the roll;
  verify with `kubectl get deploy/hpa -n istio-system`.) **ArgoCD formal redeploy DEFERRED** — see
  chart-drift follow-up; fix stays live (patched) + committed. **Step 2 load-shed IMPLEMENTED
  (config committed 2026-08-27; awaiting observability appset reapply for live rollout)**
  (`docs/bugs/2026-08-27-hub-load-shed-observability-footprint.md`): `lokiCanary.enabled: false`
  in `loki-values.yaml` (chart `loki-18.2.0`, canary is a top-level key — no selfMonitoring
  sub-block); `kube-prometheus-stack-values.yaml` `scrapeInterval`+`evaluationInterval` 30s→60s
  (the big CPU lever), `retention` 7d→3d, `retentionSize` 20GB→8GB. Prometheus CPU limit was
  already 1500m and etcd/scheduler/CM/coredns/kube-proxy scrapes already disabled — so those
  parts of the spec were pre-existing. **ROLLOUT PENDING:** reapply the `observability` appset
  with `K3D_MANAGER_BRANCH=k3d-manager-v1.27.0` so `$values` tracks the release branch, then
  ArgoCD selfHeal picks up the new values (loki-canary DaemonSet should disappear; prom CPU drops).
  Monitoring loop still running — hub was oscillating hot (load ~35–50, livez bursting to 20s)
  after Step 1, exactly the demand Step 2 removes.

- **2026-08-27 keycloak-0 restart loop FIXED live + committed + CoreDNS collateral fixed live**
  (`docs/bugs/2026-08-27-keycloak-restart-loop-tight-probes.md`): root cause was the SAME hub
  CPU starvation making Bitnami's **1-second probes** fail. keycloak-0 (67 restarts) was killed
  by liveness `tcpSocket period=1s failureThreshold=3` (SIGTERM 143) — NOT OOM. Fix in
  `scripts/etc/keycloak/values.yaml.tmpl` (previously set no probes/resources): liveness
  `period 1→10s failureThreshold 3→5`, readiness `timeout 1→5s`, **NEW startupProbe** (30s +
  40×10s = 430s grace), resources `750m/768Mi → 1000m/1Gi`. The startupProbe is the critical
  piece — Bitnami `start-dev` re-runs Quarkus augmentation every boot: live logs measured
  `augmentation 172742ms` + `started in 154.023s` = **~326s cold start**, so the old ~170s
  liveness window killed it mid-boot forever. Applied LIVE via `kubectl patch statefulset/keycloak`
  (KEYCLOAK_HELM_CHART_VERSION is empty=latest, so a `helm upgrade`/`deploy_keycloak` would risk a
  chart bump off `keycloak-25.2.0` + Bitnami-deprecation pull failure — patch was the low-risk
  path; template edit makes it durable at next deploy). keycloak-0 now **1/1, 0 restarts**.
  ⚠ **Rolling the pod exposed CoreDNS in CrashLoopBackOff (155 restarts, deploy 0/1)** — same
  1s-probe-under-CPU-starvation disease (`plugin/health … took more than 1s: 1.93s` → liveness
  SIGTERM). DNS was cluster-wide down; only cached-connection pods survived. Live-patched
  `deploy/coredns` liveness `timeout 1→5s failureThreshold 3→5`, readiness `timeout 1→3s` →
  CoreDNS `1/1` stable, DNS restored. **⚠ CoreDNS patch NOT in git — k3s-managed**
  (`k3s.cattle.io` owner, on-node `coredns.yaml`); k3s addon controller may revert. FOLLOW-UP:
  persist via k3s manifest override/HelmChartConfig, or land Step 2 load-shed so 1s probes stop
  failing at the source. This is fresh evidence Step 2 is no longer optional.

- **2026-08-27 hub-wide CPU-starvation cascade INCIDENT (mitigated live).** The keycloak dig
  uncovered that 1s liveness/readiness probes were failing platform-wide under CPU starvation,
  crashlooping EVERY core component into a deadlock: coredns (DNS down), loki-canary (4 pods,
  200+ restarts each), argocd-repo-server (probe-killed 40× → ArgoCD couldn't render manifests →
  couldn't sync the Step 2 relief → deadlock), and **agent-0 node went NotReady** (kubelet
  starved). User ran the Step 2 appset reapply (`applicationset observability configured`, now
  `$values`=k3d-manager-v1.27.0), but ArgoCD sync stayed `Unknown` because repo-server was down
  and then because rendering the big kube-prometheus-stack chart timed out (`DeadlineExceeded`).
  Live mitigations (NOT all in git): (1) `kubectl patch deploy argocd-repo-server` → light
  `/healthz` probes + startupProbe + 10s timeout (broke the deadlock; repo-server 1/1 stable);
  (2) `kubectl delete ds loki-canary` + force-deleted its pods (biggest immediate CPU win);
  (3) `kubectl patch prometheus kube-prometheus-stack-prometheus` → scrape/eval 30s→60s,
  retention 7d→3d, retentionSize 8GB **directly on the CR** (bypasses the timed-out chart
  render; operator regenerates config; ArgoCD sync is stuck so won't revert; and v1.27.0 values
  ALSO say 60s so they AGREE when sync eventually lands). Result: all 4 nodes Ready again
  (agent-0 self-recovered), keycloak/coredns/repo-server/argocd-server stable (restart counters
  frozen), Prometheus cut to 60s + counter frozen, replaying TSDB toward 2/2. ⚠ Live-only debts
  to reconcile: repo-server probe patch (ArgoCD-self-managed → reverts to 1s on next argocd
  self-sync — OK once CPU is free), coredns patch (k3s-managed), metrics-server was briefly
  unavailable. Durable resolution = the committed v1.27.0 Step 2 config syncing once repo-server
  can render the chart under freed CPU. Prometheus prometheusSpec should also carry a startupProbe
  headroom review, but its probes are already sane (not a 1s victim).

- **2026-08-28 node-health-watch was bouncing agent-0 in a restart loop (mitigated live +
  durable fix committed).** Morning regression: agent-0 `NotReady`, coredns `0/1` (DNS
  endpoints empty), prometheus-0 `Pending`/`Unknown`. Root cause was NOT a new probe bug and
  NOT OOM (`RestartCount=0 OOMKilled=false ExitCode=0` = external restarter). The launchd
  watchdog `com.k3d-manager.node-health-watch` (`bin/k3dm-node-health-watch`,
  `K3DM_NODE_RECOVERY_ENABLED=1`) polls `/healthz` with a 5s timeout; under CPU pressure that
  times out on a **slow-but-`Ready`** node, 3 fails (~90s) → `docker restart agent-0`, 300s
  cooldown, repeat ~every 6 min (log: restart 04:11→recover 04:13→fail→restart 04:17 PDT). Each
  bounce takes DNS down (coredns is a single replica pinned to agent-0) and strands Prometheus
  (its local-path PVC is on agent-0) → net-harmful. This is the **node-level instance of the
  1s-probe disease** ([[reference_one_second_probes_cpu_starvation_kill_loop]]). Live mitigation:
  `launchctl bootout gui/$(id -u)/com.k3d-manager.node-health-watch` → restarts stopped, agent-0
  holds Ready on its own (self-recovers), coredns 1/1, DNS restored, Prometheus rescheduled and
  replaying TSDB. Durable fix committed: `bin/k3dm-node-health-watch` now triggers recovery only
  on the authoritative `_ready`=False verdict (a Ready-but-slow `/healthz` is advisory, no
  restart), healthz timeout 5s→15s (`K3DM_NODE_RECOVERY_HEALTHZ_TIMEOUT`), threshold 3→5. Spec
  `docs/bugs/2026-08-28-node-health-watch-restart-loop-slow-node.md`. ⚠ Watchdog is currently
  **unloaded** — reload it (`launchctl bootstrap`) only after the fixed script is the one on
  disk AND the hub CPU has calmed; follow-up fragility: coredns SPOF + prometheus PVC both
  hostage to agent-0.

- **2026-08-28 chronic hub CPU overcommit persists after the watchdog fix — `make status` blocked
  on a pegged control plane.** With the self-inflicted node bounces stopped, all 4 nodes hold Ready,
  but the hub is still CPU-overcommitted at the source. `docker stats --no-stream`: server-0
  **492%**, agent-1 344%, agent-2 270%, agent-0 226% (~1333% total). Inside server-0: `/bin/k3s
  server` (embedded apiserver+etcd+controller-manager+scheduler) at **71%** of the node with **load
  average 60**; co-located discretionary load = `trivy server` (29% VSZ), an istio ingress-gateway
  envoy, kube-state-metrics, access-log-exporter, node_exporter. Consequence: every `kubectl` LIST
  times out (single-namespace `get pods` fails at 30s; `top nodes` times out), and the webhook
  `/api/v1/health` aggregator times out at 90s → `make status` reports `Overall: UNKNOWN / status
  source: webhook unavailable`. The webhook process itself is healthy (listening :7443, 401 without
  a token) — restarting it will NOT help; the blocker is the pegged apiserver, not the webhook.
  Durable fix = the committed Step 1+Step 2 load-shed governance (recent commits on
  `k3d-manager-v1.27.0`), but it is **inert** until ArgoCD reapplies it, and ArgoCD can't
  render/sync while the control plane is drowning (chicken-and-egg). Prior live sheds (prom 60s
  scrape, loki-canary off) are live but insufficient. Decision pending: reduce discretionary
  control-plane churn live (candidate: `trivy-operator` scale-to-0 — reversible, non-user-facing)
  vs. force the committed governance to sync. Same disease family as
  [[reference_one_second_probes_cpu_starvation_kill_loop]].
  - **RESOLVED 2026-08-28 via cluster restart (user-authorized).** Live shed alone did NOT help:
    scaled `trivy-operator` (trivy-system) → 0 and `loki`/`loki-gateway` (monitoring) → 0, but
    server-0 kept *climbing* (492→707→867%, oscillating 540-845% over 90s) because the bottleneck
    is the apiserver's own list/watch/reconcile churn, and pod terminations add to it — shedding
    agent workloads doesn't relieve the control plane. `k3d cluster stop/start k3d-cluster` cleared
    the accumulated churn: server-0 settled 607→**50%**, all 4 nodes Ready throughout, **coredns
    stayed 1/1 on the way up** (looser probes + startupProbe held — no DNS outage). Post-restart:
    apiserver responsive, `make status` completes. Recovery lesson: for a churn-storm on the k3d
    control plane, a cluster restart is the effective lever, NOT workload shedding.
  - **Post-restart Vault was sealed** (expected — raft/shamir, threshold 1). Unsealed via cached
    shards: `./scripts/k3d-manager deploy_vault --re-unseal` (keys in Keychain `k3d-manager-vault-unseal`
    + in-cluster `vault-unseal` Secret, both present). vault-0 → 1/1. ⚠ The `vault_install_unseal_watchdog`
    is NOT deployed, so Vault will need a manual `deploy_vault --re-unseal` after every restart until
    the watchdog is installed.
  - **RESTORED 2026-08-28 (user-authorized):** `trivy-operator`, `loki`, `loki-gateway` back to 1
    (all Running/Ready). ⚠ **CPU tradeoff quantified:** with them shed server-0 sat at **50%**; with
    them restored server-0 settled at **~360%** (a 617% loki cold-start spike that decayed) — 7× the
    shed headroom and much closer to the pressure edge that caused the incident. Still functional
    (apiserver responsive, nodes Ready), but loki is the heavy one; re-shed loki if steady-state
    headroom feels tight on this M4 Air. Also re-enabled the `node-health-watch` watchdog
    (`launchctl bootstrap`, PID confirmed) now running the FIXED script (`2b2d5705`) — validated live:
    logged `agent-0 Ready but /healthz slow/unreachable (advisory, no restart)` and `NotReady (1/5)`
    then stopped (self-recovered before threshold 5) — did NOT bounce the node.
  - **`make status` final: all hub infra GREEN** (ArgoCD/Keycloak/Prometheus/Grafana 200, ESO 18/18,
    data 4/4, Keycloak+ArgoCD+Grafana login OK). Sole remaining red = **`Frontend login: HTTP 401 on
    /api/cart` — a smoke-harness artifact, NOT a hub fault**: `k3dm-smoke-user` Secret absent →
    Keycloak login falls back to the Helm admin Secret (master-realm `admin-cli` token) → that admin
    token correctly can't authenticate to the app frontend, and the graceful 401/403 skip guard
    (`bin/k3dm-webhook` ~1831) only fires for `kc_via_smoke_client`, not the admin-cli fallback, so a
    correct 401 is reported as a hard FAIL. Fix candidate: extend the skip guard to the admin-cli
    fallback, or seed a real `k3dm-smoke-user`. Matches the known status-login false-green limitation.
  - **2026-08-28 Frontend login → TRUE GREEN** (`✓ Frontend login: HTTP 200 on /api/cart`). Root cause
    was 3 factors, all live-fixed on the hub Keycloak: (1) no `shopping-cart` realm existed — created it
    mirroring `home` (LDAP federation) + a public direct-grant client `k3dm-smoke`; (2) issuer mismatch —
    tokens minted locally carried a `localhost`/`.local` `iss`, never basket-service's trusted
    `https://keycloak.3ai-talk.org/realms/shopping-cart`; fixed by pinning the realm
    `attributes.frontendUrl=https://keycloak.3ai-talk.org` so **every** locally-minted token carries the
    public `iss` (no Cloudflare round-trip, verified via `.well-known`); (3) cloned LDAP component bound
    with a **masked** `bindCredential` (`**********` from the admin API) → `LDAP error 49 Invalid
    Credentials` on every federated mint; fixed by PUTting the real `LDAP_ADMIN_PASSWORD` (Secret
    `openldap-admin`, bindDn `cn=ldap-admin,dc=home,dc=org`). Smoke **user** is an LDAP entry
    (`cn=k3dm-smoke,ou=users,dc=home,dc=org`) — READ_ONLY LDAP refuses local Keycloak user creation.
    Seeded Secret `identity/k3dm-smoke-user` (username/password/realm/client; pw via stdin, not argv).
    **Webhook code change:** removed `kc_token_is_stub=True` from the smoke-client branch (a real seeded
    smoke user must green on 200 / red on genuine 401; only admin-cli/master fallback stays a skip) +
    reads optional `realm` key from the Secret. Spec: `docs/bugs/2026-08-28-smoke-frontend-login-stub-token-false-fail.md`
    (durable-follow-up section). ⚠ Live realm/LDAP/client/user/Secret WERE ephemeral — **now codified**:
    **`keycloak_provision_shopping_cart_realm`** (`keycloak.sh`) idempotently creates the realm + pins
    `frontendUrl` (`KEYCLOAK_SMOKE_ISSUER_BASE_URL`, overridable), clones the LDAP provider from `home`
    and repairs the masked `bindCredential` from Secret `openldap-admin`, creates the `k3dm-smoke` client,
    adds the LDAP smoke user (bind pw via stdin→0600 pod file, generated user pw), and writes
    `identity/k3dm-smoke-user`. Live-verified idempotent: re-run → `iss=…/realms/shopping-cart` →
    `/api/cart` **200**. Reach admin API with `KEYCLOAK_BASE_URL=http://localhost:8880` (keycloak PF up).
    Older `keycloak_seed_smoke_user` retained but wrong for this deployment (see spec) — prefer the new fn.
  - **⚠ 2026-08-28 hub CPU crisis recurred mid-session** — while completing the above, `docker stats`
    showed server-0 **454–568%**, agents ~200–330% each (~1170–1550% total on the M4 Air), and
    `/readyz` flapped `etcd failed`/`etcd-readiness failed`. Symptoms: `:8880` keycloak PF dropping to
    `000`, coredns 4× restarts → keycloak `UnknownHostException: keycloak-postgresql`, keycloak DB pool
    500s. Steady hogs (`kubectl top`): argocd-application-controller 733m, prometheus 681m; plus a
    trivy scan burst (10+ scan pods). Same disease family as the chronic overcommit above — the Step 1/2
    governance is committed but **inert until ArgoCD syncs it**.
    - **CPU-reduction pass applied 2026-08-28** (durable in-repo + live): (1) `vault-unseal-watchdog`
      CronJob cadence **`* * * * *` → `*/5 * * * *`** (`scripts/etc/vault/unseal-watchdog.yaml.tmpl`) —
      cuts 1,440 pod-spawns/day of node churn 5×; (2) ArgoCD `timeout.reconciliation` **120s (chart
      default) → 180s** (`scripts/etc/argocd/values.yaml.tmpl` `configs.cm` + live `argocd-cm` patch) —
      relaxes the 727m application-controller's full-resync cadence; takes effect on next controller
      restart (NOT force-restarted — a restart triggers a full re-sync burst). Prometheus already
      conservative (60s scrape / 3d retention) — left as-is. Snapshot at time of pass: prometheus 754m,
      argocd-application-controller 727m, argocd-repo-server 386m, vault-0 368m, keycloak 162m.
    - **Monitoring pause/resume toggle — DONE + live-verified 2026-08-28** (the "biggest optional lever",
      now built): `observability_pause` / `observability_resume` (`scripts/plugins/observability.sh`) +
      `make monitoring-pause` / `make monitoring-resume`. Scales the whole hub observability stack
      (prometheus+grafana+loki+alertmanager+kube-state-metrics+trivy) to zero on demand — reclaims
      **~1.1 cores** (measured: prometheus 730m + grafana 273m + alertmanager 37m + ksm 18m); node-exporter
      DaemonSet (~15m) left running. **Keeps production-grade config fully intact** — pause only scales
      replicas + suspends auto-sync; resume reconciles the identical committed chart values (scrape 60s /
      retention 3d / all rules unchanged). Nothing deleted, PVCs untouched → history survives within 3d.
      **Two-controller mechanism** (both required, learned live): (1) selfHeal defeated by patching each
      app `spec.syncPolicy.automated=null`; (2) that patch made durable by committing
      `ignoreApplicationDifferences: [/spec/syncPolicy/automated]` to the `observability` ApplicationSet
      (the app-level `skip-reconcile` annotation is STRIPPED by appset re-templating within seconds — does
      NOT work); (3) prometheus/alertmanager are operator-reconciled CRs — scale via the CR, not the STS.
      Resume scales workloads back **explicitly** (operator→CRs→deploy/sts to 1), NOT via ArgoCD sync —
      sync goes `Unknown`/slow exactly under the CPU starvation this feature targets. Spec:
      `docs/bugs/2026-08-28-monitoring-pause-resume-toggle.md`. Config-tune levers (#1 scrape, #2 retention)
      confirmed already spent; trivy is event-driven not cron — so the toggle is the remaining real lever.
    - **`make status` made pause-aware (2026-08-28, `bin/k3dm-webhook`)** — with monitoring paused, status
      previously hard-FAILed on Prometheus/Grafana/Grafana-login 502s. Added `_monitoring_paused()` +
      downgrade pass: when the hub `kube-prometheus-stack` ArgoCD app exists AND `spec.syncPolicy.automated`
      is empty (the deliberate-pause signal, distinguishes pause from crash), those three become `⚪` warnings
      (`monitoring paused (make monitoring-resume)`) → `Overall: WARN`, exit 0. **Two gotchas fixed live:**
      (a) query the **hub/INFRA context** `k3d-k3d-cluster`, NOT `_provider_context()` (returns app cluster
      `ubuntu-k3s`, no such app); (b) **NO provider gate** — `make status` resolves to `k3s-hostinger`
      (Makefile `CLUSTER_PROVIDER=k3s-aws` origin=file → recipe forces hostinger), and the `*.3ai-talk.org`
      Prometheus/Grafana URLs front the hub via cloudflared, so paused-hub explains the 502 in every mode.
      Safety verified: apps with `automated` set → not-paused → real outages stay hard errors. `make
      restart-webhook` required after edits. Spec: `docs/bugs/2026-08-28-status-monitoring-paused-false-fail.md`.
    - **Live CPU proof (2026-08-28):** monitoring running → Keycloak `/realms/master` 1.6–6.3s (erratic) →
      login smoke read-timeout FAILs; after `monitoring-pause` → **9–26ms**, server-node CPU recovers from
      `<unknown>`. Concrete evidence the stack starves Keycloak + API server.
    - **RESUMED to Layer 1 2026-08-28** (decision: user wants Layer 1 = reduced-rate stack always on,
      loginable Grafana, `monitoring-pause`/`resume` as the on-demand escape hatch — pause is NOT the
      default). `make monitoring-resume` restored all workloads to 1; `make status` → **HEALTHY** (all
      green incl. Grafana HTTP 200 + Grafana login 200 + Keycloak token minted). Note: pause scales
      **Grafana too** → no login while paused (Grafana without Prometheus shows empty panels anyway);
      "always loginable" = live in Layer 1, don't pause.
    - **⚠️ Resume gotcha — laptop-sleep clock jump (2026-08-28):** during resume the M4 slept; the k3d
      Docker VM clock froze (~20:54Z) then jumped forward ~3h on wake. Forward jump made
      CrashLoopBackOff burst-fire all pending restarts (ksm/operator counters shot to 43/33) + Prometheus
      "out-of-order samples" + operator "context deadline exceeded". NOT a resume bug. Recovery: clocks
      re-sync on their own; **delete the stateless scarred pods** (ksm, operator — no PVC) so they restart
      with `restarts=0`. Verified clean (both came up 0 restarts, stable). See auto-memory
      `reference_laptop_sleep_clock_jump_crashloop`.

- **2026-08-27 ArgoCD chart-version drift (BLOCKS formal deploy_argocd redeploy):** live helm release
  `argocd` is chart **`argo-cd-10.4.0`** (app v3.5.1, revision 1, deployed 2026-08-20) but the repo
  pins `ARGOCD_CHART_VERSION=7.8.1` (`argocd.sh:53`). Running full `deploy_argocd` could unintentionally
  change the chart version → regression risk, so the Step-1 argocd resource limits were NOT applied via
  helm (only live `kubectl patch` on controller+repo-server + committed to `values.yaml.tmpl`). Helm
  release state has no resource values → a non-tmpl `helm upgrade --reuse-values` would strip them
  (normal `deploy_argocd` re-renders the tmpl → keeps them). **Reconcile the pin (7.8.1→10.4.0, or
  downgrade live) BEFORE any formal argocd redeploy.** Surgical durable option if needed sooner:
  `helm upgrade argocd argo/argo-cd --version 10.4.0 -n cicd --reuse-values -f <resources-only overlay>`.

- **2026-08-27 federation scrape tuning:** source commit `977d9e11` changes the hub `federate-acg`
  Prometheus scrape interval from 30s to 60s; the vulnerability exporter remains at 60s. YAML
  parsing passed. Requires the observability values to be reapplied before live effect; monitor
  M4 CPU/API latency afterward.

- **2026-08-27 status credential discovery:** commit `f07adea8` adds fallback to the deployed
  password-only `identity/keycloak-admin-secret` (master realm/admin-cli) for smoke login checks;
  webhook tests pass. Prometheus/public endpoints recovered after OrbStack + edge restart, but the
  aggregate health sweep remains slow under control-plane load.

- **2026-08-27 hub control-plane outage:** restarting agent-0 and the k3s server did not restore
  the API. Kine reported slow SQL/handler timeouts and hub containers saturated CPU; Prometheus
  remained unavailable. Incident recorded in `docs/issues/2026-08-27-hub-control-plane-still-unavailable.md`.

- **E2E transient cleanup (2026-08-27):** commit `6b20cced` pushed on `k3d-manager-v1.27.0`.
  `_e2e_teardown` now best-effort removes orphaned vCluster kubeconfigs/proxies and transient
  per-run logs while retaining JSON audit summaries; regression coverage added. Host remains
  CPU-saturated by OrbStack/browser workloads, so m2 remains the preferred E2E runner.

- **Hostinger access-layer recovery (2026-08-26):** k3d agent-0 exited (143), causing hub workload
  evictions and local ArgoCD/Keycloak/Prometheus 502s; restarting the single stopped container
  restored all hub nodes to Ready and Prometheus replayed its WAL. Commit `44de06f7` fixes the
  Keycloak forward from service port 80 to 8080, pins tunnel/health probes to IPv4, and uses the
  valid `/realms/master` status path. Focused BATS 68/68, shellcheck, and `_agent_audit` passed.
  Repeated direct public probes reached ArgoCD/Keycloak 200; wrapper flapping remains a live
  follow-up when transient port-forward client resets occur. The shared wrapper now tolerates
  three consecutive health failures, retries after 2 seconds, and binds kubectl to IPv4; local
  ArgoCD and Keycloak checks returned 200 after regeneration. Fix commit `a5dc3967` is pushed.
  Incident:
  `docs/issues/2026-08-26-hostinger-keycloak-port-forward-service-port.md`.

- **Hostinger capacity check (2026-08-26):** live node `srv1754834` has 2 vCPU / 7.75 GiB RAM;
  current requests are 1610m CPU (80%) and 4880Mi memory (61%), while observed usage is 404m CPU
  (20%) and 5496Mi node memory (69%). It currently runs 44 pods, including ArgoCD, Vault, ESO,
  Prometheus, Loki, Trivy, and all shopping-cart services. Moving Keycloak+PostgreSQL there would
  fit steady-state usage but leaves inadequate CPU/request and rollout-failure headroom; defer until
  the node is upgraded to at least 4 vCPU/16 GiB or a second worker is added.

- **M2 E2E acceptance blocked (2026-08-25):** bootstrap/preflight passed and the intentional
  invalid-digest run produced a failed artifact, but publisher variables were absent. Replay
  and the passing run are blocked because `m2jump` cannot resolve `m2-air.local`. Evidence:
  `docs/issues/2026-08-25-m2-e2e-acceptance-blocked.md`.

- **CVE remediation panels empty — FINAL root cause (Claude 2026-08-25).** Two prior RCs were
  incomplete: Codex's "in-memory/no durable source" was WRONG (the CM-based durable source
  exists); my own "missing app-rebuild secret" was NECESSARY-BUT-NOT-SUFFICIENT. **Fixed the
  secret half (live):** stored classic PAT (`repo`+`read:packages`) as Keychain
  `platform-ops-app-rebuild/k3dm` → `argocd_sync_app_rebuild_secret` created the Secret →
  deleted 32h-wedged job `cve-auto-1787541034` → manual run `cve-verify-1787657822` completed
  clean, GHCR auth works, `product-catalog`+`payment` PROMOTED for real HIGH/CRIT CVEs.
  **Panels STILL empty → true RC (Bug A):** *nothing in the repo CREATES* the
  `k3dm.k3d.io/cve-remediation-event=true` ConfigMaps — `cve-remediation-verify.sh` only
  reads/transitions them, the exporter only reads them, and `app-cve-scan.sh` `_promote_image()`
  does live-patch+git-persist+notify but emits NO event CM. Consumer+exporter read events the
  producer never writes. **Bug B surfaced:** `_git_persist_promotion()` writes its askpass helper
  into the same dir it `git clone`s into → clone fails 100% ("destination not empty"), promotions
  are live-patch-only (revert on next ArgoCD sync). Token/netpol/git+CA all ruled out.
  **Fixes APPLIED + live-deployed (commit `915d1459`):** (A) `_promote_image()` now emits a
  durable `cve-remediation-event` CM via new `_emit_remediation_event()` — **verified end-to-end**
  (applied one such CM live → exporter emitted `cve_remediation_event_info{current="true"}`, the
  panels' query, cve_ids parsed; test CM deleted). (B) `_git_persist_promotion()` clones into
  `${_p_work}/repo` so the askpass helper no longer poisons the dest — **VERIFIED LIVE
  (deterministic, `7a830dda`+repro):** the failure is CVE-independent, so confirmed with a repro pod
  on real `aquasec/trivy:0.63.0` + live `platform-ops-git-writer/git-token` — OLD path reproduced
  `fatal: destination path '…' already exists and is not an empty directory`, NEW path cloned OK
  with `services/shopping-cart-payment/kustomization.yaml` at HEAD 7a830dd on k3d-manager-v1.27.0
  (no push). A pre-fix `cve-auto` pod on 08-25 had again logged `GITWRITE … clone … failed`,
  confirming the bug was 100% live before the fix. Deployed live by re-creating the
  `argocd-cve-scan-script` CM. **Hardening/UX DONE (`65bf4e31`):** (1) `argocd_sync_app_rebuild_secret`
  `_warn`s loudly when PAT absent + CronJob exists + no Secret (the wedge condition), stays optional
  otherwise; (2) `activeDeadlineSeconds: 1200` on the app-cve-scan CronJob (live) so a
  CreateContainerConfigError pod self-terminates in 20m vs the 32h backoffLimit-never-trips wedge;
  (3) no-data `description` on both remediation panels (live in monitoring CM). Full trail in
  `docs/issues/2026-08-24-cve-remediation-panels-empty.md` +
  `docs/bugs/2026-08-25-git-persist-clone-into-nonempty-dir.md`.

- **✅ CVE panel ② ("Shopping-cart Unique CVEs") — RESOLVED + DURABLE (2026-08-24).** 75 actionable
  `trivy_vulnerability_inventory{image_repository=~"wilddog64/shopping-cart-.*"}` series, native
  operator-generated (self-refreshing 24h TTL), Prometheus-verified. Three durable commits in
  `trivy-operator-acg-values.yaml`: `49477017` (`trivy.slow`+`timeout 15m0s`) + `8bfcbcc9` (scan-job
  CPU request `50m→10m`) + **`aac9cb27` (`operator.privateRegistryScanSecretsNames` +
  `accessGlobalSecretsAndServiceAccount: true`)**. Real root cause: workloads carry NO imagePullSecret
  anywhere (pod spec AND `default` SA empty) → private images pull via node-level containerd cred,
  invisible to the operator → silent skip; operator-upgrade is a dead end. Manual-CR stopgap (352
  all-sev) deleted in favor of native (75 actionable). Hub-side wiring (RBAC/ESO/appset `84817d88`,
  live Vault SA + policy fixes `9c9c8bb8`/`0f7ea0ad`) complete + verified end-to-end.
  Bug: `docs/bugs/2026-08-24-trivy-operator-skips-private-images-sa-imagepullsecret.md`.
  Auto-memory: `reference_trivy_operator_node_cred_private_image_skip`.
  - **Close-out (2026-08-24, both done):** (a) `acg-trivy-operator` **ArgoCD-synced** — the 3
    OutOfSync resources converged via a manual sync (ref `k3d-manager-v1.27.0` contains `aac9cb27`,
    so the private-registry env survived); app Synced/Healthy, panel ② held at 75 (payment 52 / order
    11 / basket 8 / product-catalog 4). (b) `allow-cve-scan-egress` netpol given a durable home —
    **spec'd + pushed** to shopping-cart-payment `docs/plans/durable-trivy-scan-coverage.md` (branch
    `feat/trivy-scan-egress-netpol`, `3ca0dca`, PR gated); flags the kustomize `commonLabels`→selector
    gotcha + optional SA imagePullSecrets hardening. Live netpol stays drift until that merges. The
    originally-planned pod-spec imagePullSecrets / scan-CR CronJob / operator upgrade are
    UNNECESSARY / redundant+harmful / dead — see bug doc "reassessed".
  - ⚠️ The 2026-08-23 "ArgoCD stale-render bug" was a **mis-diagnosis** (I read the hub's own trivy
    configmap, not hostinger's `acg-trivy-operator`, which has no `automated` syncPolicy so manual
    patches stick). Durable git fixes are correct + live.

- **Keycloak hub deploy DONE + dev SSO RESOLVED (2026-08-22).** `keycloak-0` 1/1, VirtualService
  live (`keycloak.3ai-talk.org/realms/master` 200); port-forward remote-port bug fixed (`04cc1e14`,
  →8080). Realm `home` (`dc=home,dc=org`) is the DESIGNED truth; admin/developer/operator synced,
  the only gap was missing LDAP passwords — fixed `bin/cluster-up` step 10d.5 seed loop (`9efb23f7`)
  + live `seed-dev-sso-passwords.sh` (all 3 verified via ldapwhoami, mirrored to
  `secret/keycloak/users/*`). Steps 10d.6/10d.7 realm-federation reconcile are broken+redundant →
  follow-up: delete or retarget `-r home`. **SSO login round-trip to realm `home` still to be
  confirmed by user.** Docs `docs/bugs/2026-08-22-keycloak-*`, `-hub-openldap-wrong-realm-*`.

- **hostinger istiod-scheduling cascade RESOLVED — 3/3 (2026-08-22).** Single 2-CPU node
  `srv1754834` chronically 95–98% CPU requests; istiod Pending 2d → ambient mesh down →
  product-catalog CrashLoop + frontend stuck. Break-glass restored istiod+frontend; product-catalog
  durable via PR #49 `505f758a` (cpu 100m→50m). **ArgoCD source gotcha (keep):** the hub app reads
  `repo=k3d-manager rev=k3d-manager-v1.26.0` whose kustomization pulls REMOTE
  `shopping-cart-product-catalog//k8s/base?ref=main`; a `refresh=hard` annotation re-fetched `ref=main`
  → OutOfSync, user-run `kubectl patch cpu=50m` landed it (durable, selfHeal won't revert).

- **hostinger CPU right-sizing — durable fix committed, ACTIVATION PENDING (2026-08-24).**
  Investigated: node `srv1754834` is **request-bound, not load-bound** — CPU *requests* 98%
  booked (1960m/2000m, 40m free) while *actual* usage ~20% (419m). 0 pending / no FailedScheduling
  at rest; the risk is a future rollout deadlock (surge pod > 40m free → the
  `hostinger_maxsurge_rollout_deadlock` / istiod-cascade class). Durable overlay patches committed
  `6851b5b0` on `k3d-manager-v1.27.0` (`services/shopping-cart-*/kustomization.yaml`): payment
  requests.cpu 200m→50m (+150m); basket/order/frontend maxSurge=1/unavail=0 → maxSurge=0/unavail=1.
  Each `kubectl kustomize` build verified. **INERT until activated:** the `services-git` appset renders
  app `targetRevision` from `${K3D_MANAGER_BRANCH}`, frozen at `k3d-manager-v1.26.0`; `services/` is
  byte-identical v1.26.0↔v1.27.0 so reapplying at `k3d-manager-v1.27.0` pulls ONLY this fix. Live
  patches will NOT stick (all 5 apps `selfHeal=true`). **All three prepped 2026-08-24:**
  (a) `services-git` appset re-rendered at v1.27.0 (server-diff = ONLY the branch ref moves) — apply
  BLOCKED by classifier, handed to user as a `!` command (`kubectl apply -f
  .../services-git-v127.yaml`). (b) rabbitmq 200m→50m committed `1a85dc7a` on branch
  `feat/rabbitmq-cpu-request-trim` in `shopping-cart-infra` → **PR #93 MERGED** `59ed6342` on
  2026-08-24. `enforce_admins` RESTORED (confirmed `true`); `required_reviews` remains 1. Rabbitmq trim
  now live on ref=main (ArgoCD will roll to hostinger via data-layer app read).
  (c) istiod pilot cpu 100m→50m committed `1dbe68dc` on v1.27.0 in
  `scripts/etc/argocd/applicationsets/istio-ambient.yaml` — istiod `maxSurge=100%` is a hardcoded istio
  chart default (NOT helm-overridable in a pure-helm ArgoCD source), so the request trim shrinks the
  surge-pod footprint instead; re-rendered + server-diff = ONLY pilot cpu; apply BLOCKED by classifier,
  handed to user (`kubectl apply -f .../istio-ambient-v127.yaml`).
  **✅ ALL THREE LIVE + VERIFIED 2026-08-24:** both appsets reapplied at v1.27.0 (services-git
  `targetRevision` v1.26.0→v1.27.0; istiod appset pilot cpu 50m). basket/frontend/order Synced+Healthy,
  payment rolled (50m), istiod Synced/Healthy (surge pod scheduled), rabbitmq rolled via data-layer.
  Hostinger node `srv1754834` CPU requests **1960m (98%) → 1610m (80%)** = ~350m reclaimed (~40m→~390m
  free); zero Pending pods. Rollout-deadlock class eliminated. hostinger CPU right-sizing CLOSED.

- **Other live/tracked follow-ups:**
  - Replace the interim in-cluster CVE promoter git-writer token with a fine-grained
    contents-write-only PAT.
  - Reconcile stale port-forward/LaunchAgent state on public Grafana/status probe failures
    (`reference_single_service_502_zombie_port_forward` in auto-memory).
  - Re-seed display-only Vault paths wiped in rebuild (Prometheus basic-auth, ArgoCD/Grafana
    mirrors) — display-only, not ESO-managed; `make show-service-passwords` triage in
    `reference_show_service_passwords_na_root_causes`. Hub Prometheus is UNAUTHENTICATED (rotate fn
    targets ACG, not hub).
  - Keep ArgoCD smoke credential-drift + k3s-aws SSM registration issues visible in `docs/issues/`
    until their live follow-ups close. Account-level SSM Default Host Management Role optional.
  - Dependabot alert #6 (js-yaml) remediated as lib-foundation `v0.4.11` (subtree `1bf1d2ce`,
    lockfile `3.15.1`); reads `open` only because Dependabot scans main → auto-closes when
    v1.26.0 → main. Dev-only transitive, low risk.

- **k3d agent watchdog hardening (2026-08-26):** existing bounded `node-health-watch` previously
  skipped exited containers; commit `15c7d072` now uses `docker start` for `created`/`exited`/`paused`
  states and `docker restart` only for running containers. Focused BATS 2/2, ShellCheck, and
  `_agent_audit` passed. Watchdog reinstalled live with the existing 3-failure/300-second cooldown.

## Operating decisions

- **2026-08-26 hub outage:** an exited k3d agent caused node-affine Prometheus/Loki pods to hang and
  Kine/SQLite readiness to fail, producing edge 502s. Agent/server restart plus stale pod cleanup
  restored the workloads; public forwards still require live verification. See
  `docs/issues/2026-08-26-hub-control-plane-and-edge-forward-outage.md`.

- **Edge forward hardening:** `ea91431d` increases wrapper probe timeout/hysteresis (5s/6 failures)
  to avoid restarting ArgoCD/Keycloak on transient control-plane latency. Public ArgoCD/Keycloak
  checks still need re-verification once the k3s API settles.

- `make status` follows the active provider (concise/full/JSON); Slack reuses the same summary contract.
- CVE remediation current-state excludes terminal `superseded`/`deployment_advanced` events; history
  keeps the audit trail. Verifier cadence/bounds stay conservative under hub load.
- E2E runs use a throwaway vCluster, pinned service images, runtime-generated datastore credentials,
  and an EXIT-trap result artifact written before teardown.
- **2026-08-27 M2 E2E migration:** corrected the remote dispatcher to forward an explicit immutable
  `E2E_IMAGE_TAG` to the M2 runner (`0f16f0de` on `k3d-manager-v1.27.0`). The corrected image build
  (`shopping-cart-e2e-tests` run `33073207387`, source `0c2505bb`) passed; live M2 acceptance remains
  the next verification step. M4 storage is healthy (58% root, 196 GB free; OrbStack 26%, 184 GB free).
  The 2026-08-27 M2 run used the immutable tag but failed 31/102 (26 passed, 45 skipped), with
  basket/order response-shape failures and payment-suite failures; see
  `docs/issues/2026-08-27-m2-e2e-acceptance-after-immutable-image.md`.
- **2026-08-27 Keycloak smoke fallback:** committed `931839ab` on `k3d-manager-v1.27.0` to support
  deployed password-only Keycloak admin Secrets while preserving the existing username/password path.
  Focused Keycloak BATS passed 12/12 and ShellCheck was clean.
- Do not deploy source-only changes until their release-branch/PR gates + live verification are explicit.
- When the laptop Vault reverse bridge is required (`HUB_VAULT_USE_BRIDGE=1`, default), k3s-aws selects
  SSH and overrides explicit SSM with a warning; SSM stays available for non-bridge Vault profiles.

- **2026-08-28 hub last-mile close-out** (`k3d-manager-v1.27.0`): four follow-ups from the CPU-crisis
  resolution actioned.
  - **Governance already durable (verified, no-op):** `argocd_check_values_branch` → all 6 Applications
    track `k3d-manager-v1.27.0` (no drift); live `monitoring` ns confirms Step 2 governance is applied —
    loki-canary=0, prom scrapeInterval/eval=60s, retention=3d, retentionSize=8GB. ApplicationSets were
    already reapplied; nothing inert.
  - **Vault auto-unseal watchdog deployed + fixed:** installed `vault_install_unseal_watchdog` (CronJob
    `vault-unseal-watchdog`, ns `secrets`, `* * * * *`, Forbid). Found + fixed two bugs — (1) stale
    pinned image `1.18.3` vs live `1.20.1`, and vars.sh unconditionally exporting the stale default,
    defeating derivation; now `vault.sh` derives the image from the running Vault StatefulSet and vars.sh
    leaves `VAULT_UNSEAL_IMAGE` empty; (2) per-node k3d image cache + `activeDeadlineSeconds:50` killed a
    cold pull → raised to 150. Validated: manual job SUCCEEDED ~12s, logs `vault already unsealed`. Note:
    a real restart preserves node image caches, so the cold-pull only bites first-deploy. Spec:
    `docs/bugs/2026-08-28-vault-unseal-watchdog-stale-image.md`.
  - **Frontend-login false-red fixed:** `bin/k3dm-webhook` skip guard extended from `kc_via_smoke_client`
    to a new `kc_token_is_stub` flag (True on both smoke-client AND admin-cli fallback paths), so an
    expected 401 on `/api/cart` from a stand-in admin token is a SKIP not a hard FAIL. `make status` now
    `WARN (1 warning)` — the lone warning is the honest "no real smoke user seeded" skip; everything else
    green. Real outages still FAIL (guard is 401/403-only). Spec:
    `docs/bugs/2026-08-28-smoke-frontend-login-stub-token-false-fail.md`. Durable follow-up (out of scope):
    seed a real `k3dm-smoke-user` in the shopping-cart realm to make this a true PASS.
  - **loki re-shed declined (data-driven):** offered when server-0 was ~360% cold-start; it has since
    settled to **95–130%** with canary already gone. A manual `loki=0` would be reverted by ArgoCD
    selfHeal (git declares 1) and would remove log aggregation for CPU that is no longer pressured — left
    loki at 1/1. One-command shed remains available if headroom is ever needed.
- **2026-08-28 optional durable follow-ups:**
  - **deploy_vault now auto-installs the unseal watchdog** (`vault.sh`, after `_vault_setup_pki`, guarded
    `|| _warn`) so auto-unseal survives a hub rebuild without a second command — same pattern as
    platform-ops in the ArgoCD bootstrap. Decision folded into
    `docs/bugs/2026-08-28-vault-unseal-watchdog-stale-image.md`.
  - **Real smoke-user seed NOT applicable on the hub — architecture finding.** `keycloak_seed_smoke_user`
    targets a `shopping-cart` realm, but the hub Keycloak (identity ns, reached at
    `keycloak.shopping-cart.local`) has only `home` + `master` realms — no `shopping-cart` realm and no
    frontend/app client (`home` has only default clients). The shopping-cart frontend + its realm live on
    the **app-cluster (ACG)**, not the hub. So seeding a hub user cannot produce a true Frontend-login PASS
    without first provisioning the shopping-cart realm + frontend client on the hub Keycloak (a real setup
    task, not a last-mile seed). The honest SKIP from the `kc_token_is_stub` fix is the correct state. Seed
    aborted at the realm-existence check — created nothing (verified: no `k3dm-smoke-user` secret, no
    `k3dm-smoke` client). Also noted: codebase default realm `shopping-cart` is stale vs live hub `home`.

- **2026-08-29 monitoring-pause Grafana keep-list — LIVE-VERIFIED (8506f5fe, pushed):** pure
  whole-word `_observability_workload_in_keep_list` + default
  `OBSERVABILITY_PAUSE_KEEP=kube-prometheus-stack-grafana` pause-sweep exemption; resume unchanged.
  Five pure BATS cases + Makefile help. Spec `docs/bugs/2026-08-29-pause-keep-grafana-up.md`. Coded by
  Codex, Claude-verified (BATS 5/5, `bash -n` clean, SC2016 pre-existing only). Live hub:
  `make monitoring-pause` keeps grafana 1/1 (loginable, `database:ok`) while everything else → 0/0;
  resume → HEALTHY. By design panels show "No data" while paused (UI reachable, not live data). To
  restore the old all-or-nothing sweep set `OBSERVABILITY_PAUSE_KEEP=""`.

- **2026-08-29 layered `monitoring-resume` — LIVE-VERIFIED (1bdbe3c6, pushed):** `make
  monitoring-resume LAYER=1` brings up **Grafana + Prometheus only** (live dashboards), all else 0;
  `LAYER=2` or no arg = full stack (existing body, verbatim). Added `_observability_normalize_layer`
  (1→1, 2/empty/unknown→2 — forgiving) + `_observability_resume_layer1` (keeps ArgoCD `automated:null`
  so selfHeal can't resurrect the 0-set; explicit replica drive; idempotent from pause/L1/L2), reusing
  the keep-list predicate with `OBSERVABILITY_LAYER1_UP=kube-prometheus-stack-grafana
  prometheus-kube-prometheus-stack-prometheus`. Makefile `$(LAYER)` passthrough + help. 5 pure BATS
  normalize cases. Spec `docs/bugs/2026-08-29-layered-monitoring-resume.md`. Coded by Codex,
  Claude-verified (BATS 10/10, `bash -n` clean, SC2016 pre-existing only, diff==spec, scope==3 files).
  **Live hub:** L2→`LAYER=1` dropped to grafana 1/1 + prometheus 1/1 (rest 0/0), Prometheus `up` query
  returned series + Grafana `database:ok`; `LAYER=2` restored all 7 workloads 1/1, `make status`
  HEALTHY. One manual touch during the L2 ramp: deleted a stale `Unknown` prometheus pod from the known
  CPU-starvation cascade (full stack starting at once) — not a feature defect.

- **2026-08-29 Tier-1 E2E orders.spec ROOT-CAUSED + FIXED (aa2f2190, pushed) — gate rerun
  confirming:** the orders.spec wholesale failure (42 ✘) was NOT a client-contract bug. Ground
  truth (captured Playwright `results.json` from the live pod before teardown + direct
  port-forward replay): the deployed order image `sha-56033880` is the **Go** rewrite (commit
  `5603388`), not Java (earlier Dockerfile read was wrong), and it ships **no runtime migration** —
  the substrate created the `orders` DATABASE but never the `orders`/`order_items` TABLES →
  every order DB op HTTP 500 (`relation "orders" does not exist`, 42P01). Fix: added
  `20-orders-schema.sql` to `scripts/etc/e2e/postgres.yaml` initdb (`\connect orders` + DDL).
  Critical nuance: DDL must match the **deployed** commit `5603388` — its `order_items` has **no
  `total_price`** column; copying repo-HEAD/testdata DDL (which added `total_price NOT NULL`) 500s on
  insert (23502) since that binary never writes it. **Live-validated** against the running substrate:
  `POST /api/orders → 201` with full contract (id, status PENDING, items[].subtotal, totalAmount,
  shippingAddress, currency USD), `GET …?customerId=X` (X-User-ID header) → 200 with the order. List
  filters by `X-User-ID` (MockAuthMiddleware), not the query param — e2e client sends it consistently,
  no change needed. Payments.spec (27) + payment cross-service stay Tier-1-out-of-scope (no payment
  manifest = Tier-2/ACG's job). Spec `docs/bugs/2026-08-29-e2e-order-schema-missing.md`; durable
  service-side self-migrate follow-up `docs/issues/2026-08-29-order-service-no-startup-migration.md`.
  Confirming rerun DONE (`~/.k3dm/e2e/1788051374-25838.json`, commit 86298144): **passed 26→45,
  failed 31→12, skipped 45**. Cross-service fully greened (21→0), orders 42→2. **Residual 12 =
  ZERO substrate bugs**: (a) 9 payments `ECONNREFUSED :8084` — no payment svc in Tier-1
  (Tier-2/ACG's job); (b) 2 order status-update — e2e test sends status `CONFIRMED` which is NOT
  in the deployed `OrderStatus` enum (PENDING/PAID/PROCESSING/SHIPPED/COMPLETED/CANCELLED) + illegal
  transitions (PENDING→only PAID/CANCELLED) → PATCH 400 → status undefined = **e2e-test contract bug**
  (shopping-cart-e2e-tests, spec-not-direct); (c) 1 cart remove-qty-0 — `cart.items` undefined,
  pre-existing basket/e2e mismatch. Substrate fix is COMPLETE for its scope. To green the gate:
  cross-repo — fix the 3 test-contract bugs in the e2e repo (+ rebuild image) and decide payment
  (Tier-1 manifest vs scope-to-non-payment + Tier-2). User chose (2026-08-29): **fix e2e tests,
  payment→Tier-2.**

- **2026-08-29 e2e residual triage — CART RECLASSIFIED as a basket-service bug (specs written,
  Codex handoff pending):** on grounding the 3 residuals, only 2 are e2e-test bugs; the cart one is
  a service bug:
  - **Order status (2, e2e-test bug):** tests send status `CONFIRMED`, absent from the deployed
    `OrderStatus` enum (PENDING/PAID/PROCESSING/SHIPPED/COMPLETED/CANCELLED) + illegal transitions
    (PENDING→only PAID/CANCELLED). Fix = use real enum + legal chain (PENDING→PAID; history
    PENDING→PAID→PROCESSING→SHIPPED). Spec `docs/bugs/2026-08-29-e2e-order-status-enum-mismatch.md`
    (repo `shopping-cart-e2e-tests`).
  - **Cart qty-0 (1, BASKET-service bug, NOT a test bug):** basket `UpdateItemRequest.Quantity`
    is `binding:"required,min=0"`; gin treats int 0 as "missing" so `{quantity:0}` → 400 before the
    handler's `quantity<=0` remove path runs. Test is CORRECT. Fix = drop `required` (use `min=0`).
    Issue `docs/issues/2026-08-29-basket-update-quantity-zero-required.md` (repo `shopping-cart-basket`).
  Both are shopping-cart repos → spec+Codex, branch+PR, rebuild image (spec-not-direct). Codex handoff
  + image rebuild + Tier-1 re-verify still to do; PR/merge gated.

## Canonical pointers

### 2026-09-01 → 2026-09-04 — v1.28.0 block (ARCHIVED)

> Compressed 2026-09-21. Full detail: `memory-bank/archive/activeContext-2026-09-21.md`.
> All settled — v1.28.0 shipped and merged; the tree is on v1.36.0.

Covered there: the live frontend Keycloak client hotfix; ArgoCD identity sync recovery; empty
Grafana CVE panels; the `keycloak-secrets` ExternalSecret root cause (**Vault field schism**, not
missing data); the v1.28.0 two-cloud bring-up, where a fresh-hub `make up` aborted on an unguarded
PrometheusRule apply — guard shipped and verified, then the LDAP verify-newline fix; two-cloud
validation complete across AWS and hostinger; two v1.28.0 follow-ups closed; pruning unconditional
Jenkins fixtures from the LDAP bootstrap seed, and the decision to leave `bootstrap-ad-schema.ldif`
fixtures as-is; lib-foundation PR #45 (acg robust-click) through to v0.4.14 merged and
subtree-synced; and v1.28.0 PR #119 created and merged with CI green.

### Hub GHCR outage — still OPEN, blocked on a credential

All four `shopping-cart-apps` deployments on the hub remain `ImagePullBackOff` (11h+).
Kubelet reports `403 Forbidden` from `ghcr.io` — authenticated, not authorized.

Every GitHub credential on the operator's machine was tested and none can pull:
- `gh` CLI token — scopes `admin:public_key, gist, read:org, repo`. No `read:packages`.
- Keychain `github-packages-token` — refused by `bin/restore-hub-ghcr-pat`'s pull probe.
- `k3dm-hermes-gh-token`, `k3dm-hermes-audit-token` — no `X-OAuth-Scopes` header.

The scope-header check is INCONCLUSIVE for fine-grained PATs (GitHub omits the header),
so "no scopes header" does not distinguish expired from fine-grained. The authoritative
test is the GHCR token exchange + `tags/list` pull, i.e. `_shopping_cart_ghcr_pat_can_pull`.
That probe was validated against the real package: `wilddog64/shopping-cart-basket` is
exactly what `basket-service` pulls, so the refusal is real and not a bad probe.

`github-packages-token` failing also implies the GitHub Actions image-build pipeline
will 401 — a second, independent breakage worth tracking.

Next: operator runs the per-token GHCR pull probe to confirm, then either pipes a
working token into `bin/restore-hub-ghcr-pat` or mints a classic PAT with `read:packages`.

## 2026-09-21 — rotate-ghcr-pat VERIFIED + image-promotion bug filed and dispatched

`bin/rotate-ghcr-pat` fix verified and committed at `edaa2e49` (Codex implemented; Claude
committed because Codex again could not write `.git/index.lock`). All five BATS gates
mutation-tested `not ok` against the pre-fix source, file restored shasum-identical.
`shellcheck` clean (only expected SC1091 info on sourced libs), `bats` 5/5.

### CORRECTION — my earlier "PACKAGES_TOKEN is heading for 401s" claim was WRONG

`PACKAGES_TOKEN` in GitHub Actions **works**. The registry push half of the pipeline is
healthy: run `35117065512` built, pushed and cosign-attested
`sha256:e9bcb925619b5344a958fc359091b651c61365ce7b8a65c354408ee2f7198b92` — the exact digest
`product-catalog` on the hub is failing to pull. So the image exists in GHCR and CI can write it.

The real CI breakage is `PROMOTER_SSH_KEY` arriving **empty**, so the git promotion step dies at
`Load key ".../promoter_key": error in libcrypto`. Filed as
`docs/bugs/2026-09-21-image-promotion-fails-promoter-ssh-key-not-passed-to-reusable-workflow.md`
(`eb97355d`) and dispatched to Codex (session `01a0c401`, log
`scratchpad/codex-promoter-run.log`), branch `fix/pass-promoter-ssh-key` in 4 repos.

Cause: `build-push-deploy.yml` declares `PROMOTER_SSH_KEY: required: false`, and three of five
callers omit it from their `secrets:` block — payment, product-catalog, frontend. Basket and
order are correct. Payment is a pure code fix (secret exists); product-catalog and frontend also
need the **operator** to create the repo secret.

**Why this hid for weeks:** `publish` is gated on `github.ref == 'refs/heads/main' && event ==
'push'`, so every PR and Dependabot run **skips** it, and a skipped job does not fail a run. The
2026-09-21 product-catalog run reads `success` with `Build, Scan & Push = skipped`. Another
instance of green ≠ working — check the job list, not the run conclusion.

The hub `403 Forbidden` is a **separate, cluster-side** credential problem (the PAT in Vault /
`ghcr-pull-secret`), not a CI problem. Still blocked on a PAT with `read:packages`.

## 2026-09-21 — promoter-key spec CORRECTED after Codex caught my mismatch

Codex stopped without editing and reported that three of the four repos in my spec did not
match the files on disk. It was right. The error was mine: my detection script globbed
`*.yml` only and took the first match per repo.

Corrected, verified scope — **`shopping-cart-product-catalog` is the only broken repo**:

| Repo | Caller | Calls reusable? | Forwards key? | Repo secret? | Last main pushes |
|---|---|---|---|---|---|
| basket | `go-ci.yml` | yes | yes | yes | 1 failure, DIFFERENT cause |
| order | `ci.yml` | yes | yes | yes | success |
| payment | **`ci.yaml`** | yes | yes | yes | success |
| **product-catalog** | `ci.yml` | yes | **no** | **no** | **failure 3/3 since 2026-08-26** |
| frontend | `ci.yml` | **no** (inline publish) | n/a | n/a | success |

- payment's caller is `ci.yaml` — **`.yaml`, not `.yml`** — and already forwards the key.
- frontend never uses the reusable workflow; it promotes via a deploy PR with `PACKAGES_TOKEN`.
- basket run `33507015429` failed promotion too, but its key was present (`***`) and the error was
  `failed to push some refs` — a push rejection. Separate, unfiled, single occurrence. Do NOT fold in.

Spec rewritten to product-catalog + infra only (`6fa1ceab`) and re-dispatched (session `01a0c406`,
log `scratchpad/codex-promoter-run2.log`). Stray branches Codex created in payment and frontend are
left in place — branch deletion is not approved.

Codex created branches in 4 repos on the first attempt; only product-catalog and infra will receive
commits.

## 2026-09-21 — promoter-key fix VERIFIED (2 SHAs on origin) + a pinning gap found

Codex's second run is verified independently:

| Repo | SHA | on origin | files | scope |
|---|---|---|---|---|
| shopping-cart-product-catalog | `2c8dd68f` | yes | `.github/workflows/ci.yml` | +1 line |
| shopping-cart-infra | `94b16bc9` | yes | `.github/workflows/build-push-deploy.yml` | +10 lines |

Both on `fix/pass-promoter-ssh-key`, no PRs, commit message and trailers exact.
YAML parsed with `yaml.safe_load`: guard is step index **12**, promote step index **13** — guard
first, guard is self-contained (`env`/`name`/`run`, `exit 1`), and the promote step still has its
`git push` and key-file write. `required: false` left unchanged as specified.
product-catalog's `publish` job now forwards all four secrets.

Codex self-caught a real bug mid-run: its first patch put the guard **inside** the promotion step's
`run:` block after `git commit`, which would have swallowed the consumer commands. It corrected to a
separate step before reporting.

### GAP — the guard will NOT fire for product-catalog yet

`product-catalog/ci.yml` pins the reusable workflow:

```
uses: wilddog64/shopping-cart-infra/.github/workflows/build-push-deploy.yml@1b35d962d...
```

Verified `1b35d962d` does **not** contain the guard (`grep -c` = 0). So until that pin is bumped to
a commit containing `94b16bc9`, product-catalog keeps calling the old workflow and an empty key still
fails as `error in libcrypto`, not the actionable message.

Change 1 (forwarding the secret) is unaffected — it lives in product-catalog's own file.

Sequence for the guard to take effect: merge infra → bump the pin in product-catalog. Dependabot
already tracks this pin (its PR titles read
`github_actions in /. - Update ...build-push-deploy.yml-<sha>`), so it will bump on its own after
the infra merge, or it can be re-pinned by hand.

### 2026-09-21 — promoter-key gap is TWO missing things, not one (spec corrected again)

Checked the deploy keys rather than trusting the earlier claim that basket/order/payment share one
promoter key. They do **not** — three distinct `sc-image-promoter` fingerprints, one pair per repo.
The promote step pushes to `git@github.com:${{ github.repository }}` — the **calling repo itself**,
not the infra repo — so each app repo needs its own write deploy key plus its own private-half secret.

`shopping-cart-product-catalog` is missing **both**: no `sc-image-promoter` deploy key and no
`PROMOTER_SSH_KEY` secret. Adding only the secret would still fail, at `git push`, with a permission
error rather than `error in libcrypto`.

~~"add the secret reusing the key already in basket/order/payment"~~ — **RETRACTED, was wrong.**
The fix is a fresh ed25519 pair for product-catalog only. Key material, so not a Codex task.

Pin bump deliberately NOT dispatched: product-catalog pins `build-push-deploy.yml@1b35d962b`, and
bumping it to the unmerged `94b16bc9` would point a consumer's main at a commit outside infra's
default branch, with a second bump forced after the squash merge. Correct order is infra PR merge
first, then bump to the merge SHA. Dependabot already tracks `github-actions` weekly in that repo.

Blocked on the user, not on Codex: (1) PR creation in both repos, (2) the keygen + deploy key +
secret for product-catalog.

### 2026-09-21 — deep dive: product-catalog was never onboarded to the SSH promoter

The user pushed back that this setup has been done many times and should not need redoing. Correct
instinct, wrong conclusion about the cause: product-catalog was never onboarded, and a later pass did
one third of the job, which is why it looks onboarded.

infra PR #91 (2026-08-09T14:26Z) switched promotion from token push to SSH deploy key. Its rollout
section says "Per repo: add write deploy key + PROMOTER_SSH_KEY secret; ruleset with DeployKey bypass;
delete classic protection; repin" and **never enumerates the repos**. It covered order (14:27Z),
payment (15:02Z) and basket (15:05Z) — deploy key and ruleset created within the same minute each —
and skipped product-catalog.

Breakage trigger, 2026-08-12: 01:53Z main push succeeded while still pinned to 4afa9dce (0 refs to
PROMOTER_SSH_KEY); 01:54Z auto-merge enabled on Dependabot PR #47; 01:56:59Z squash-merged, moving the
pin to 47769da (3 refs); 01:57Z main push FAILED. Four minutes. The Dependabot PR was green by
construction — `publish` is main-push-gated, so it was skipped on the PR that broke it.

2026-09-01 13:03Z: eight minutes after that day's failure, a main-protection ruleset with a
DeployKey:always bypass was created on product-catalog. Step 3 of the rollout applied in isolation — a
bypass for a key that does not exist. Misdiagnosis; 09-16 failed identically.

Corrected in the spec: broken since **2026-08-12, six consecutive main pushes**, not 2026-08-26. The
wrong date came from `gh run list --limit 3`.

Still missing, steps 1 and 2 only: the write `sc-image-promoter` deploy key and the PROMOTER_SSH_KEY
secret. Nothing to copy — the three sibling fingerprints are distinct because the promote step pushes
to the calling repo, not to infra.

BLOCKED: generating the pair and writing the secret was denied by the auto-mode classifier
(Secret-Store Writes). Not worked around. One command handed to the user to run via `!`.

**RESOLVED 2026-09-21 23:38Z** — the user ran that command. Verified from the GitHub side, not from
the reported output: `gh repo deploy-key list` shows `164022592  sc-image-promoter  read-write`
created `2026-09-21T23:38:44Z`, and `gh secret list` shows `PROMOTER_SSH_KEY  2026-09-21T23:38:46Z`.
The new fingerprint differs from `argocd-product-catalog-m2-air`, so the two keys are not conflated.
Both `/tmp/pc_promoter` and `/tmp/pc_promoter.pub` are gone. Claude never read the private key.

Onboarding steps 1 and 2 are closed. What remains for product-catalog promotion to actually succeed
is the **infra merge plus the pin bump** — `ci.yml` still pins `build-push-deploy.yml@1b35d962d`,
which predates the guard, so the forwarded secret is inert until that pin moves.

### 2026-09-21 — hub GHCR 403: the credential path, corrected

User asked whether the keychain was locked. Checked: it is **not** — `show-keychain-info` reports
`no-timeout` and all four items (`github-packages-token`, `k3dm-hermes-gh-token`,
`k3dm-hermes-audit-token`, `copilot-cli`) exist. That hypothesis is closed, but chasing it surfaced
two corrections.

**1. The pull probe is sound — I should not have let it be doubted.** Verified directly:
`curl --netrc-file` does send `Authorization: Basic` preemptively to `ghcr.io/token`; a bogus
credential returns 403 with no `.token`, so `_shopping_cart_ghcr_pat_can_pull` fails closed and is
correct. Its verdict on all four keychain tokens stands.

**2. "PACKAGES_TOKEN is working" was misleading.** The registry login in
`build-push-deploy.yml` is `password: ${{ secrets.GITHUB_TOKEN }}` — the ephemeral per-run Actions
token with automatic `packages: write`. So the green push proves nothing about any long-lived
credential. `PACKAGES_TOKEN` is only a build arg (`GH_TOKEN=` for dependency fetches) and the
frontend's deploy-PR token. **There is no working long-lived GHCR pull credential anywhere** — not in
CI, not in the keychain.

The packages are private: anonymous token exchange returns
`401 UNAUTHORIZED authentication required`. A credential with `read:packages` is mandatory; one
without it yields 403, which is exactly the hub's `ImagePullBackOff`.

**Fix without minting anything:** the existing `gh` OAuth token (`gho_`, in the keyring) has scopes
`admin:public_key, gist, read:org, repo` — no `read:packages`. `gh auth refresh -h github.com -s
read:packages` adds it to the token we already have. Interactive, so the user runs it via `!`.
Cheap scope check afterwards: `gh api "user/packages?package_type=container"` currently returns
`403 You need at least read:packages scope to list packages`.

### 2026-09-21 — basket promotion failure root-caused: the rebase fallback cannot ever work

Filed `docs/bugs/2026-09-21-image-promotion-rebase-fallback-cannot-resolve-concurrent-newtag-conflict.md`.

basket run `33507015429` (2026-09-01T12:19Z) was NOT a transient race. Two main pushes three minutes
apart (12:16Z Dependabot pin bump, 12:19Z manual re-pin) each promoted; the second was rejected
`fetch first`, and the fallback `git pull --rebase` hit
`CONFLICT (content): Merge conflict in k8s/base/kustomization.yaml` because both commits rewrite the
**same `newTag:` line**. Rebasing one such edit onto another is a guaranteed conflict — the retry is
structurally incapable of recovering from the only scenario it exists for. The rebase halted, leaving a
conflicted worktree, and the retry push ran against that.

Fix specified: replace commit-then-rebase with a bounded fetch / `reset --hard origin/<ref>` / reapply
`sed` / push loop, with the "already promoted" no-op check moved inside the loop so a concurrent run's
identical result counts as success.

**Sequencing:** must NOT start until `fix/pass-promoter-ssh-key` merges in shopping-cart-infra —
`94b16bc9` touches the same file. Branch `fix/promote-refetch-instead-of-rebase` off the updated main
afterwards. Not dispatched to Codex yet for that reason.

Confirms the earlier decision to keep this separate from the PROMOTER_SSH_KEY bug was right: same
failing step, different cause, key present.

## 2026-09-21 — doc realignment: webhook architecture, /k3dm pattern, new Grafana guide

Three commits, all on `k3d-manager-v1.36.0`, all pushed.

**`3e5951ca` — architecture docs vs. the live webhook server.** Both
`docs/architecture/webhook-server.md` and `-/cloudflare-slack-relay.md` still described
v1.13.0. Measured corrections: `bin/k3dm-webhook` is **4,008** lines (doc said ~2,950);
`scripts/lib/webhook/` has **5** modules (`make_targets.py` was absent from the table, as
was `auth.py`'s Slack identity gate `_slack_user_is_allowlisted` / `_slack_user_role`);
every line range in the "still in the monolith" table was stale. Five routes were
undocumented: `/api/v1/make`, `-cve-remediate`, `-hostinger-status`,
`-cleanup-stale-sandbox`, `-analyze`. The relay route table now carries a **min-role
column** sourced from `_ACTION_POLICY`.

Also documented the interface shift the user flagged: **the Makefile is now the operator
surface**. `/k3dm` replaced "one route per operation" — a new capability is a Makefile
target plus one row in `MAKE_TARGETS`. Four gates written down: target allowlist, per-target
arg allowlist + `_ARG_PATTERNS` regex, role **capped twice** (relay stamps `admin`, then
`_effective_make_role` caps at the caller's `K3DM_SLACK_ROLE_MAP` role, then the target's
`min_role`), and `confirm` for the three destructive targets. Execution detail recorded:
args are positional `$@`, never interpolated, and `__K3DM_MAKE_RC=` is how the real rc
survives a merged-stream capture.

**`dfef599e` — `docs/guides/grafana-dashboards.md` (new) + webhook phase status.**

Grafana had **no guide at all** — a guide-per-major-tech violation. Seven dashboards ship
from two directories to two different clusters; their knowledge existed only scattered
across ~25 plan/bug/issue docs, and `grafana-dashboard-hermes.yaml` was referenced by none
of them. The guide gives per-dashboard panels + queries, the producer chain, and a
`No data`-by-cause triage table where every row is a real past incident.

Findings surfaced while tracing producers:
- **`k3dm.k3.io/hermes-status` is NOT a typo to fix.** The Hermes selector uses `k3.io`
  where the e2e and CVE selectors use `k3dm.k3d.io`. `bin/k3dm-hermes:378` and
  `vulnerability-inventory-exporter.yaml:281` agree, so it works; normalising one side
  alone silently empties the dashboard and the exporter reports no error. Marked do-not-fix
  in both guides.
- **`checkout-loadtest-configmap.yaml` has no applier** — no plugin, Makefile target or
  ApplicationSet references it. Its `No data` is the steady state, not a regression.
- `docs/guides/hermes.md` described **four** Hermes panels; the dashboard has **six**
  (*Degraded sensors*, *Unknown sensors* were missing). Fixed, with the panel/query table.

**Webhook modularization phase status — the user asked where we are.** Answer: Phase 1
only, and that is accurate, but the doc omitted the real story. None of `server.py`,
`routes.py`, `commands.py`, `dispatch.py`, `jobs.py`, `diagnostics.py` exist — **phases 2–5
not started**. Phase 1 moved ~190 lines out (3,142 → 2,953 at `28f38058`); today the file
is **4,008**, **+36%** since. The plan is being outrun by the code it was meant to shrink;
`webhook-server.md` now carries that measurement table and a per-phase status table with
evidence. Noted that both real extractions (`config/render/proc/auth`, then `make_targets`)
were **pure leaves**, not the behavioural splits phases 2–4 describe.

Prior commit this window: `b5721781` (ASCII→Mermaid; found and fixed
`acg-credentials-flow.md` block#1, which had never rendered — a semicolon in
sequence-diagram message text terminates the statement).

## 2026-09-21 — doc-link gate BUILT (5-month-old proposal), 13 broken links fixed

`58f5c316` on `k3d-manager-v1.36.0`, pushed. Preceded by `f3b9be22` (e2e harness guide tiers).

**Why now.** The harness-guide audit found three README entries for one doc, all linking to
the bare file, so "Tier 2" landed on a page titled "(Tier 1)". Nothing could have caught it.
`memory/feedback_issue_doc_links_precommit.md` had recorded this gap on **2026-04-06** and
re-confirmed on 2026-09-17 that the checker had **never been built**.

**Built:** `scripts/check-doc-links.py` (stdlib; the memory proposed a `.sh` — Python is more
honest for markdown parsing) + `make check-doc-links`, wired into `.githooks/pre-commit` over
**staged files only** so pre-existing debt cannot block unrelated commits. `K3DM_SKIP_DOC_LINKS=1`
bypasses. Dropped the proposal's `.pre-commit-config.yaml` step — this repo uses
`core.hooksPath=.githooks`, so that part was simply wrong. Tests:
`scripts/tests/bin/test_check_doc_links.py`, **23 cases**, added to `make test-pytest`.

**Three false-positive classes had to be handled** — each would have made the gate useless:
1. **Inline code.** A DNS regex `` `[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?` `` is syntactically
   `[text](target)`. Code spans blanked before matching.
2. **`path:line`.** This repo writes clickable `bin/k3dm-webhook:95`; suffix stripped.
3. **Slug rules.** `github-slugger` does `.replace(/ /g, '-')` — **each** space its own hyphen,
   so `/claude / /gemini / /codex Commands` → `claude--gemini--codex-commands`. **My first
   implementation collapsed whitespace runs and reported three CORRECT links as broken.** Caught
   by inspecting the target headings before "fixing" anything — the near-miss worth remembering.

**Fixed 13 of 13.** Standing docs retargeted: `../howto/vault-pki-setup.md` →
`../guides/security/04-vault-pki.md` (×2), dead `README.md#jenkins-authentication-modes` →
`../guides/jenkins-authentication.md`, `../bin/get-ldap-password` → `../../bin/…`,
`#create-slack-app` → `#1-create-slack-app`. In 4 historical `docs/issues/2026-05-*` and 1
archived plan the dead links were **unlinked to inline code**, not repointed — repointing a
record to somewhere it never pointed falsifies it. Same call as leaving historical ASCII
diagrams alone. That also unlinked 3 neighbouring absolute `/Users/cliang/...` links that
resolved on this machine only.

Verified: `1725 file(s) OK`; 23 pytest pass; failure path exits 1 with `file:line`;
`shellcheck .githooks/pre-commit` clean; and the hook fired on its own commit
(`check-doc-links: 11 file(s) OK`).

### Discovered, NOT fixed — needs the user's go
**`bin/acg-up` / `bin/acg-down` were renamed `bin/cluster-up` / `bin/cluster-down` in v1.7.1
(`0c9b2707`), and 219 files still say the old name.** No code references the old names, so
nothing breaks at runtime — but standing docs (README's ACG table,
`docs/architecture/cloudflare-slack-relay.md` "Step 10h"/"Step 14c", guides) instruct readers
to run a script that does not exist. The link checker cannot see these: they are code spans,
not links. Historical bugs/issues/retros should **keep** the old name. Scope for the sweep =
standing docs only. Recorded in
`docs/bugs/2026-09-21-doc-links-and-anchors-never-validated.md`.

## 2026-09-21 — acg-* → cluster-* rename applied to standing docs

`cee21ef0`, pushed. Follows `58f5c316` (the doc-link gate that surfaced it).

`bin/acg-up`/`-down`/`-refresh`/`-status`/`-sync-apps` → `bin/cluster-*`, and Slack `/acg-*`
→ `/cluster-*`, happened in **v1.7.1** (`0c9b2707`; spec
`docs/plans/v1.7.1-rename-acg-to-cluster-binaries.md`). Code was already clean — grep of
`bin/k3dm-webhook`, `workers/slack-relay/index.js` and `Makefile` found **zero** old names —
so nothing was broken at runtime, but standing docs told readers to run scripts that do not
exist.

**48 occurrences fixed** in README (live sections only), `docs/architecture/cloudflare-slack-relay.md`,
`docs/howto/makefile.md`, `docs/howto/launchd-daemons.md`, `docs/guides/grafana-dashboards.md`,
`memory-bank/projectbrief.md`, `memory-bank/systemPatterns.md`.

**Deliberately left, each verified not assumed:**
- **Release tables** (README `## Releases` from line ~310, `docs/releases.md`) + `docs/bugs/`,
  `docs/issues/`, `docs/retro/`, `memory-bank/archive/`. `/acg-resume` really was the command
  in v1.6.3 — renaming a release note falsifies what shipped. Boundary used: the `## Releases`
  heading.
- **Grafana panel titles** "Last acg-up Duration" / "Last acg-down Duration" — these are
  *literal strings* in `k3dm-deployments-configmap.yaml`, so the guide quotes the dashboard as
  deployed. Added a caveat naming the cost of changing them (edit ConfigMap + reapply
  `make observability-acg`). **A doc that disagrees with a deployed UI string is worse than a
  stale name.**
- `acg-credential-test` / `acg-extend-test` — CURRENT names, and they live in
  `scripts/lib/foundation/.../acg/bin/` (subtree, never edit). Also preserved `acg-watch`,
  `acg-prometheus`, `acg-values`, `acg-plugin`, and the `acg-sandbox-stripe-verification`
  anchor.
- `acg-sync-apps-argocd-pf` state-file/log constant inside `bin/cluster-sync-apps` — kept on
  purpose by the v1.7.1 spec. My `\bacg-sync-apps\b` regex *would* have matched it (hyphen is
  a word boundary); confirmed it appears in no edited file.

**Also fixed:** `cloudflare-slack-relay.md` quoted a 409 Slack message the webhook never
emits (`use /acg-status to check progress`). Real text from `bin/k3dm-webhook:3755` is
`cluster job already running: <job_id> (<action>)`. A stale *quote* is a separate defect from
a stale *name* — the rename would have silently "modernised" a fabricated string.

Caught before commit: inserting the panel-title caveat mid-table split a markdown table,
orphaning three rows. Moved below the table.

Verified: `check-doc-links` 1726 OK; mermaid 6 blocks 0 failed; 23 pytest pass.

## 2026-09-21 — Tier 1 e2e RAN (first ever e2e data on Grafana); Tier 2 blocked

**User asked for one Tier 1 + one Tier 2 run so Grafana has data.** Tier 1 ran; Tier 2 could
not start.

### Tier 1 — ran, failed at `deploying-substrate`, but DID publish
`./scripts/k3d-manager e2e_verify_vcluster`, run `1790025545-10464`, host context
`k3d-k3d-cluster`. vCluster `e2e-1790025545-10464` created in ns `vclusters`, API ready, then:

```
[acg-up] GHCR_PAT not in env — checking Vault...
[acg-up] gh CLI token cannot pull from ghcr.io — ... excludes read:packages, NOT saved to Vault
ERROR: [acg-up] GHCR_PAT not set and no valid PAT in Vault
```

`result: fail`, `exit_code: 1`, `phase: deploying-substrate`. The `EXIT` trap tore the vCluster
down cleanly (deregistered from hub ArgoCD, namespace deleted) — no leak.

**The observability chain is PROVEN END TO END**, which is the lasting win here:
run → `platform-ops` ConfigMap `e2e-result-cxdm5`
(`e2e-result=true,e2e-runner=local-m4,e2e-service=product-catalog,e2e-tier=vcluster`) →
`vulnerability-inventory-exporter` → metrics. Read off the exporter's `:8080/metrics`:
`e2e_last_run_pass{tier="vcluster",service="product-catalog",runner="local-m4"} 0`,
plus `e2e_run_info`, `e2e_last_run_timestamp_seconds`, `e2e_last_run_duration_seconds`.
**Before this run the hub had ZERO `e2e-result` ConfigMaps** — the E2E Verification dashboard
now has its first series. Note this is a *local* run, so it does not clear the OPEN remote bug
`docs/bugs/2026-09-15-e2e-remote-results-never-reach-grafana.md` (that is about
`E2E_M2_PUBLISH_BACK_HOST` being invisible to launchd).

### MY ERROR, corrected — I pre-cleared Tier 1 on a false probe
Before running I probed GHCR with the gh token against
`ghcr.io/wilddog64/shopping-cart-e2e-tests`, got HTTP 200 on the manifest, and told the user
"repo scope is sufficient for your own packages, so Tier 1 can pull." **Wrong.** That package
is **PUBLIC** — anonymous, credential-free token exchange also returns 200. Measured:

| Package | anonymous | gh token |
|---|---|---|
| `shopping-cart-e2e-tests` | **200** | 200 |
| `shopping-cart-basket` | 403 | **403** |
| `shopping-cart-product-catalog` | 403 | **403** |

The substrate needs the **private service images**, not the public test runner.
`_shopping_cart_ghcr_pat_can_pull` is correct and its default
`GHCR_PROBE_REPO=wilddog64/shopping-cart-basket` (private) is deliberate — trust it over an
ad-hoc probe. Saved as `memory/reference_shopping_cart_e2e_tests_package_is_public.md`.
Same trap family as the `GITHUB_TOKEN` green-push false positive.

### Tier 2 — hard blocked, never started
`e2e_verify_sandbox` hardcodes `kubectl --context ubuntu-k3s` (`scripts/plugins/e2e.sh:119`)
and calls `acg_extend_playwright`. Only two contexts exist: `k3d-k3d-cluster` and
`ubuntu-hostinger` — **there is no ACG sandbox up**. Standing rule: ACG login is a one-time
MANUAL Pluralsight step needing a real TTY; Claude-run `credential-test` bails
`ACG_SESSION_EXPIRED`. Not attempted.

### What unblocks each (both user-side)
- **Tier 1:** a GHCR PAT with `read:packages` → `pbpaste | bin/rotate-ghcr-pat`. **Open
  question:** `bin/cluster-up` asserts gh's OAuth scopes "are fixed and exclude
  read:packages", which would make the long-parked `gh auth refresh -h github.com -s
  read:packages` futile. Unverified — check before spending time on it.
- **Tier 2:** bring up the ACG sandbox (manual Pluralsight login, user, real TTY), then rerun.

Also confirmed same root cause: hub `shopping-cart-apps` pods (basket/frontend/order/
product-catalog) have been `ImagePullBackOff` for ~20h.

### 2026-09-21 — post-merge on product-catalog: the merged PR was Dependabot, not our fix

User reported "only product-catalog has a PR open, and I merged it" and asked for `/post-merge`.
Checked before running anything. The PR that merged at 23:41:44Z was **#54, a Dependabot pin
bump** (`1f45062c`), moving `ci.yml`'s `build-push-deploy.yml` pin from `1b35d962b` to
`af4b053dc`. It was not `fix/pass-promoter-ssh-key` — that branch never had a PR, because we were
waiting on the user's go, and no PR was ever opened in infra either.

Why this matters rather than being a harmless mix-up:

| Thing | State on product-catalog `main` after #54 |
|---|---|
| `PROMOTER_SSH_KEY` secret | exists (minted 23:38Z) |
| `sc-image-promoter` deploy key | exists, read-write |
| `ci.yml` forwards `PROMOTER_SSH_KEY` to the reusable workflow | **NO** — only PACKAGES_TOKEN, COSIGN_KEY, COSIGN_PASSWORD |
| pinned infra SHA contains the empty-key guard | **NO** — `af4b053dc` = infra main @ PR #98 (09-16), predates `94b16bc9` |
| pinned infra SHA contains the rebase-fallback fix | **NO** — `git pull --rebase` fallback still present |

The reusable workflow declares `PROMOTER_SSH_KEY: required: false`, so the missing forward is
silent: the promote step writes an empty file and dies at
`Load key "~/.ssh/promoter_key": error in libcrypto`. Minting the keypair removed the *second*
blocker; the *first* one — the caller not passing the secret — is untouched.

This is the [[reference_unenumerated_api_rollout_misses_repos]] pattern firing a second time on the
same repo: a Dependabot pin bump moving a pin across a range that does not contain the fix, merging
green because the promote step is `continue-on-error: true` with a separate fail-gate.

Post-merge steps actually applicable to a Dependabot bump: main synced locally to `1f45062c`
(fast-forward, 3 commits). No tag or release — CHANGELOG has only `[Unreleased]` and this was not a
milestone branch, so the skip is legitimate, not a missed release. `main` is **not** branch-protected
on this repo (`/protection` returns 404 "Branch not protected"), so there is no `enforce_admins` or
review count to restore. Dependabot's branch was auto-deleted. No retro (not a milestone). No next
feature branch created — `fix/pass-promoter-ssh-key` is still the live one.

Left alone, pending the user's word: rebasing `fix/pass-promoter-ssh-key` onto the new main, and
opening its PR.

### 2026-09-21 — promoter-fix PRs opened; the failure mode proved live on main first

User gave the go. Before opening anything, the #54 merge's own main run
(`35668727231`, head `1f45062c`) finished and proved the prediction rather than leaving it
asserted. Build, push, cosign sign and both attestations succeeded; the promote step failed:

```
Load key "/home/runner/.ssh/promoter_key": error in libcrypto
git@github.com: Permission denied (publickey).
```

twice — once on the initial `git push`, once on the `git pull --rebase` fallback retry. So the
minted keypair changed nothing on `main`, exactly because `ci.yml` never forwards the secret. Worth
recording: the keypair was necessary but not sufficient, and merging the Dependabot pin bump moved
the pin *past* nothing useful.

**Blast-radius enumeration before proposing the infra guard** (the guard hard-fails on an empty key,
so "who breaks?" had to be answered by reading, not assumed):

| Caller | Workflow file | Forwards `PROMOTER_SSH_KEY` |
|---|---|---|
| shopping-cart-basket | `go-ci.yml` | yes |
| shopping-cart-order | `ci.yml` | yes |
| shopping-cart-payment | **`ci.yaml`** | yes |
| shopping-cart-product-catalog | `ci.yml` | **no** |
| shopping-cart-frontend | — | does not call it |

Payment's `.yaml` extension is itself the reason the 2026-08-09 rollout skipped a repo: a `*.yml`
glob does not match it. Same family as
[[reference_run_success_hides_skipped_publish_job]] and
[[reference_unenumerated_api_rollout_misses_repos]].

PRs: product-catalog [#55], infra [#99]. product-catalog's branch was rebased onto the new main
(`31fd3b3`) and force-pushed with `--force-with-lease`; both got a CHANGELOG entry under
`[Unreleased] / ### Fixed` carrying the **corrected** 2026-08-12 date, since the commit messages
still say 2026-08-26. Both `mergeable: true`, state `blocked` (checks pending, not conflicted),
Copilot requested on each. NOT merged — awaiting CI, Copilot, and the user's merge.

Chose a guard over `required: true` deliberately: `required: true` hard-fails every caller at
workflow-resolution time including any that legitimately does not promote, whereas the guard fires
only on the path that needs the key and its message names the secret, the block to add and the repo
to check.

### 2026-09-21 — both promoter PRs green; a real defect found in the guard message

PR gates. product-catalog **#55** `5d5d59b7`: all checks pass, Copilot "Approval recommended,
Findings: None", 0 unresolved threads, `MERGEABLE / CLEAN`. infra **#99** `6dc3c23`: same Copilot
verdict, all four checks pass, `MERGEABLE / BLOCKED` with `reviewDecision=REVIEW_REQUIRED`.

`Build, Scan & Push` shows **skipping** on #55. That is expected and is the whole reason this bug
survived six pushes: the publish job does not run on pull requests, so no PR can exercise promotion.
The merge is the first real test.

**Infra CI caught a genuine defect in Codex's commit, and fixing it surfaced a second one.**
YAML Lint failed: `build-push-deploy.yml:162` was 211 chars against a `max: 200`. While splitting
it I noticed the message embedded `\${{ secrets.PROMOTER_SSH_KEY }}` to show a caller what to add.
Actions substitutes `${{ }}` in a `run` block before the shell sees it and a backslash is **not** an
escape there, so that line would have rendered with an empty string where the syntax should be —
the guard's own teaching message, broken, in the only code path that prints it. Not a secret leak
(the guard only fires when the value is empty) but it defeats the purpose of the guard. Reworded to
name the expression in prose and avoid the sequence entirely. Fix `6dc3c23`; verified by parsing the
YAML and asserting the guard step still precedes the promote step (index 12 before 13).

Lesson shape: a lint failure on a line-length rule is worth reading rather than mechanically
wrapping — the wrap forced a look at content that no linter would have flagged.

BLOCKED: `gh api .../branches/main/protection/enforce_admins -X DELETE` on **infra** was denied by
the auto-mode classifier (CI Bypass). Not worked around. Handed to the user to run via `!`.
product-catalog needs no equivalent: its `main` has no classic protection (404) but does carry a
**ruleset** (`deletion, non_fast_forward, pull_request, required_status_checks`), and ruleset repos
expose no `enforce_admins` lever — see [[reference_classic_protection_404_on_ruleset_repos]]. #55
already reports `CLEAN`.

**enforce_admins on infra: DONE.** The first `-X DELETE` attempt was denied by the auto-mode
classifier (CI Bypass) and was not worked around; after the user explicitly asked for the override it
succeeded, and `enabled` reads `false`. #99 still reports `MERGEABLE / BLOCKED` because the ruleset
requires one approval — disabling enforce_admins grants the admin bypass, it does not rewrite that
status. **Owed: re-enable with a bodyless POST after the merge.**

## 2026-09-21 — `make show-service-passwords` fixed and pushed (`ef3d4b8d`)

`make show-service-passwords` exits 1 with "Vault credential lookup still unavailable (check
Vault token and port-forward)" while **every layer the message blames is healthy**. Live probe
of `127.0.0.1:18200`: `sys/health` 200, `auth/token/lookup-self` 200 (403 anonymous),
`secret/data/observability/grafana` **200**, `secret/data/argocd/admin` **404**.

Root cause: `Makefile:500` uses the optional display mirror `secret/argocd/admin` as its Vault
liveness probe. That path's only producer, `_hub_recovery_mirror_argocd_admin`
(`scripts/plugins/hub_recovery.sh:118-140`), `return 0`s on every failure branch — so its
absence is a supported outcome, not a fault. The gate turns that cosmetic gap into a hard exit
that blocks all four credentials, including Grafana's, which was readable the whole time.

Spec: `docs/bugs/2026-09-21-show-service-passwords-liveness-probe-uses-optional-kv-path.md`.
Fix `ef3d4b8d` swaps the probe to `auth/token/lookup-self`, retries the mirror bootstrap secret for
up to 60 seconds, and documents that the mirror is optional. Focused BATS 31/31 and shellcheck
passed; pushed to `origin/k3d-manager-v1.36.0`.

**Independently verified (not taken from the Codex report).** `ef3d4b8d` + `f9d956ae` are on
`origin/k3d-manager-v1.36.0`. Diff scope is exactly the six spec'd files. Re-ran the gates myself:
`shellcheck -x scripts/plugins/hub_recovery.sh` rc 0; `bats` 31/31 green; and the mandatory mutation
check against the pre-fix `Makefile` (`git show a7769892:Makefile`, never `git stash`) shows tests
1-3 genuinely **red** and test 4 green — the N/A-degradation assertion correctly passes on both
trees, since the credential blocks were never meant to change. Gate block now has zero occurrences
of `secret/data/argocd/admin` and two of `auth/token/lookup-self`.

## 2026-09-21 - image-promotion refetch fix pushed (`e99960e`, shopping-cart-infra)

`fix/promote-refetch-instead-of-rebase` replaces the promote step's commit-then-`git pull --rebase`
fallback with fetch -> `reset --hard origin/<ref>` -> reapply the `sed` -> commit -> push, bounded at
5 attempts with `sleep $(( _attempt * 3 ))` backoff and an `::error::` exhaustion exit. Rebasing one
`newTag:` edit onto another is a guaranteed content conflict, so the old fallback was structurally
incapable of recovering - not flaky. The SSH/remote setup moved above the loop because `git fetch`
now runs inside it.

Gates verified by me on the working tree: YAML parses; `git pull --rebase` -> **0**;
`git reset --hard` -> **1**; the `Verify the promoter SSH key was provided` guard -> **1** and still
at a lower step index (12) than promote (13). One file changed.

**Codex could not commit** - the same `.git/index.lock` `Operation not permitted` wall as the
`bin/rotate-ghcr-pat` run. It left the edit in the working tree and said so plainly rather than
fabricating a SHA. I reviewed the diff, committed and pushed it myself: `e99960e` on
`origin/fix/promote-refetch-instead-of-rebase`. **No PR** - PR creation needs the user's go.

**Noted, pre-existing, not introduced:** the promote step keeps `continue-on-error: true`, so the new
`exit 1` does not fail the job on its own. A separate `Fail when image promotion did not complete`
step (`if: steps.promote.outcome == 'failure'`) converts it, so exhaustion does surface as a red run.

## 2026-09-21 - Vault rebuild root-caused; ArgoCD mirror repaired live

With the liveness gate fixed, `show-service-passwords` ran and exposed two real Vault gaps.
**KV *metadata* returns 404** for both `k3d-manager/prometheus-basic-auth` and `argocd/admin`,
while `k3d-manager/alertmanager-basic-auth` returns 200 (created 2026-09-21T01:42:57Z). In KV v2 a
data delete preserves metadata; only a destroy removes it, and nothing in this repo destroys. So
those two paths were **never written to the current Vault instance** - the hub was rebuilt around
2026-09-20T23:46Z (`argocd-secret.admin.passwordMtime` 23:51:56Z) and re-seeding was **partial**.

Why it stayed invisible: `_observability_ensure_prometheus_login` (`observability.sh:268`) is
Vault-read-only - on 404 it `_warn`s and returns 1, and its only caller does
`_observability_ensure_prometheus_login || return 0`, discarding it. **This is the long-standing
"Prometheus Vault credentials unreadable" backlog item, now root-caused.** The Prometheus login
still works only because `bin/prometheus-auth-proxy` runs host-side on :19090 validating against
`--credentials-file ~/.local/share/k3d-manager/prometheus-basic-auth.env`, a derived cache written
from a *previous* Vault instance that survived on the host. The loop is self-consistent and green
while the canonical store is empty - so a live 200 there proves the proxy accepts the file, **not**
that Vault holds anything.

Key design point for the fix: Prometheus and ArgoCD need **opposite** treatment. Vault is canonical
for Prometheus per `docs/bugs/2026-06-09-prometheus-basic-auth-vault-managed.md`, so a display-time
file fallback would reverse a deliberate decision - the repair belongs in the seeding path. ArgoCD's
authoritative store is `cicd/argocd-initial-admin-secret` and Vault is only a display mirror, so a
display fallback there is correct. Spec:
`docs/bugs/2026-09-21-vault-rebuild-leaves-prometheus-and-argocd-credentials-unseeded.md` (`9d2bdb15`),
dispatched to Codex.

**Live repair done, ArgoCD only (user chose "ArgoCD only" over reseeding both).** Mirrored the
existing password into `secret/argocd/admin` - additive write to an absent path, no credential
rotated. Validated against ArgoCD's own `/api/v1/session` first: **HTTP 200**, which supersedes the
earlier offline `passwordMtime` inference. Read-back 200, keys `['password','username']`, and the
value **MATCHes** the k8s source. `make show-service-passwords` now resolves ArgoCD, Grafana and
Alertmanager. **Prometheus is still N/A by design** - the user declined that reseed, and the Codex
fix repairs it on the next auth-proxy refresh rather than retroactively.

**Credential exposure to fix, both mine to own:**
- The user pasted the live **Grafana** password into the session - rotate it.
- I ran the target through a `password:`-based redaction filter; the **Keycloak admin** line uses a
  different shape (`admin user:     admin / <password>`) and passed through unredacted into the
  transcript - **rotate the Keycloak admin password.** That format inconsistency is worth fixing in
  the target itself: it is the one credential that redaction-by-convention cannot catch.
- The three Keycloak **dev users** (admin/developer/operator) also print `N/A` - a further gap not
  covered by either spec. Unfiled.

## 2026-09-21 - Keycloak credential display relabelled; Prometheus reseed verified

- **Codex `bbr6gajol` verified and accepted** (`6c744a23`, on `origin/k3d-manager-v1.36.0`).
  Prometheus reseed (M1-M4) + ArgoCD display fallback. My own gates: BATS 11/11; mutation
  against pre-fix `Makefile` shows the ArgoCD-fallback test `not ok` (genuine), while the
  Prometheus-absence test passes pre-fix by design and proves nothing. The deliberate
  asymmetry held: the Prometheus display block still reads Vault only, with no file or k8s
  fallback.
- **Reverted one unsolicited Codex edit.** It left an uncommitted rewrite of an
  intentionally-literal bcrypt string to `printf -v` to satisfy SC2016. That finding is
  pre-existing since `fd281c85` (v1.24.0) and is *info* severity, while CI runs
  `shellcheck -S error` - so the committed tree already passes the real gate. Codex's
  reported `SHELLCHECK_RC=0` was only true with that edit applied.
- **Filed `284d22ec`** - `docs/bugs/2026-09-21-show-service-passwords-keycloak-block-defeats-redaction.md`.
  Three defects: (D1) the Keycloak block printed four secrets on `user:`-prefixed lines, so
  any consumer redacting on the `password:` convention passed them through unredacted - this
  is what leaked the live Keycloak admin password into a session transcript today; (D2) the
  three realm SSO users always print `N/A`; (D3) `bin/get-keycloak-password` passed the Vault
  root token in a `kubectl exec` command string, violating the CLAUDE.md secret-hygiene rule,
  while `bin/vault-exec` already implements the safe stdin idiom.
- **D2 root cause - a third victim of the same rebuild gap, but NOT the same path.**
  `secret/keycloak/admin` (service admin: `admin_password`, `db_password`) exists and is one
  of the 14 allowlisted hub seed keys. The realm SSO users live at
  `secret/keycloak/users/<user>`, are written **only** by `bin/cluster-up:1031`, and are
  **not** in the allowlist - so a hub rebuild never restores them. Live probe: data and
  metadata both 404 for all three; `LIST secret/metadata/keycloak` returns
  `["admin","clients"]`. The old message `run make up first` was wrong advice: `make up` does
  not seed these. Changing the 14-key allowlist stays NOT approved, so the fix makes the
  display honest rather than seeding anything.
- **Codex `bqrx3e9l7` verified and accepted** (`41855a2d`, on origin). Every Keycloak secret
  now sits behind a `password:` label; realm users report
  `not provisioned on this cluster (seeded by bin/cluster-up, not by make up)`; the service
  admin keeps a bare `N/A` because a blank there is a real fault. My own gates:
  `shellcheck -S error` RC=0, BATS 15/15, mutation shows tests 7/8/9 `not ok` pre-fix and the
  unchanged-block guard (test 10) passing pre-fix as expected. Codex used the inline stdin
  idiom rather than `bin/vault-exec` because that wrapper parses only `-n|--namespace` and
  cannot pin `--context` - verified, correct call.
- **Jev / TypeSafe AI investigated - recommendation: do not integrate now.** A "System One"
  model (constrained decoding, typed choice + probability, 70-500ms, $0.042/MTok in, output
  free, 255-choice cap, text only, v0.01 early access). "Cannot hallucinate" means schema
  conformance, not correctness; independent reviewers agree calibration is the specifically
  unvalidated claim, and TypeSafe concedes its 0% figure is analytic (`our number is not
  empirical`) with in-house evals. Three blockers here: (1) volume - e2e/Hermes findings run
  ~13/month (1 May, 12 Aug, 13 Sep), far too few to calibrate a 0.90 threshold; (2)
  `e2e.sh`/`e2e_remote.sh` (1963 lines) contain **zero** classification or routing logic, so a
  judgment layer would precede the deterministic layer it is meant to sit on, and repo routing
  is a lookup table, not a judgment; (3) data egress - failure payloads would go to a
  third-party API, and today's Keycloak leak shows redaction-by-convention fails on one
  nonconforming line. Proposed instead (NOT started, needs the user's go): a deterministic
  verdict taxonomy + static service->repo routing table, and back-label the 28 existing
  e2e/Hermes bug docs to produce the offline eval set.

## 2026-09-21 - Deterministic E2E triage spec written and dispatched

Spec: `docs/plans/v1.36.0-e2e-deterministic-triage-and-corpus.md` (`f670d731`). Dispatched to
Codex (`scratchpad/handoff-e2e-triage.md`, session `01a0c6ab`). This is 2 of the 5-doc cap for
v1.36.0. **No external model or service is involved** — deterministic Python and Bash only.

Two findings the spec is built on, both verified against the live tree:

- **Hermes misattributes every Tier 2 connection failure.** `scripts/lib/hermes/e2e_triage.py`
  `_PORTS` covers only Tier 1 (8000 product-catalog, 8080 order, 8083 basket, 8084 payment).
  Tier 2 uses **8081 order / 8082 product-catalog** (`_e2e_sandbox_job_manifest`,
  `scripts/plugins/e2e.sh:141-250`), so a Tier 2 ECONNREFUSED classifies as
  `("service-unreachable", "host-8081")` — no service attribution, no repo routing. Hermes is
  the consumer that files bug docs, so Tier 2 failures file against `host-8081`. The union of
  the two maps has no port collisions, so `e2e.sh`'s existing 6-entry map is the correct one and
  Hermes is the incomplete copy. `scripts/tests/plugins/e2e.bats:240-258` (`sandbox-ports`)
  already pins 8081/8082 and is correct — it must pass unchanged as the cross-tier check.

- **`_e2e_write_summary` applies no redaction.** `failure_details` (<=200 entries, 300 chars of
  raw Playwright error text each) is written to `~/.k3dm/e2e/<run>.json` and
  `<run>.failures.json`, and published into a hub ConfigMap in `platform-ops` via
  `_e2e_write_result_event`, then surfaced in Grafana. `e2e_remote.sh:583-591` validates shape
  and length only. `hermes/e2e_triage.redact()` already exists and is applied on the Hermes side
  (`sensors.py`, `e2e_bugs.py`, `status_triage.py`) — the `e2e.sh` writer path never adopted it.
  Same failure class as the show-service-passwords Keycloak block: a redaction convention that
  one code path does not follow.

Correction to an earlier claim in this session: I had said `scripts/plugins/e2e.sh` contains
zero classification or routing logic. That was wrong — there are **two** classifiers
(`e2e.sh:711-760` inline heredoc, and `hermes/e2e_triage.py`) and they diverge on the port map,
the timeout regex breadth, the contract regex, the unknown-port fallback, and redaction.

Scope notes: no kind string is renamed (`service-unreachable`, `timeout`, `contract-drift`,
`assertion`, `harness` are baked into the `e2e_bugs.py` hint table, `diff_groups` slugs, the
`e2e_remote.sh` group schema, and the Grafana panels). The operator's vocabulary
("infrastructure", "cross-service") is mapped in docs only. `cross-service` stays a **routing**
value of `service`, not a kind. A new `auth` kind IS added — it was missing entirely.

**Corpus size, stated honestly:** only 11 labelled samples exist (the `## Sample errors`
bullets across the 5 machine-filed `2026-09-16-e2e-*` bug docs). `~/.k3dm/e2e/` yielded zero
usable entries: the 4 summaries with real Playwright stats predate the `failure_details` feature
(`978ea60f`, 2026-09-17) and the only post-feature run died at `deploying-substrate`. 11 is
enough to pin a rule-based classifier against regression and nowhere near enough to validate a
probabilistic or confidence-scored one — the corpus README must say so, so the number is not
later cited as a calibration set.

### Implementation landed — `0c57b110`

Codex implemented M1-M6; it was blocked on `.git/index.lock` (the known sandbox restriction)
and correctly refused to fabricate a SHA, so I committed and pushed on its behalf after
verifying independently. Scope was exactly the spec's allowed file list.

Gates I ran myself: `shellcheck -S error` RC=0; `pytest scripts/tests/hermes` 138 passed
(via the pyenv shim — pytest is not on /opt/homebrew/bin/python3); `bats e2e.bats` 45 ok / 0
not ok; `make check-doc-links` 1730 OK. Mutation check: reverting `_PORTS`/`_PORT` to the
Tier-1-only map turned exactly the two Tier 2 corpus entries red
(`host-8082 != product-catalog`), then restored and re-confirmed 138 passed. Pre-fix
`scripts/plugins/e2e.sh` has zero `redact` occurrences and writes `title`/`error` raw, so the
new BATS redaction assertion is genuinely red pre-fix. `sandbox-ports` (e2e.bats:240) was left
unedited, as required — it is the cross-tier agreement check.

Codex found a real defect in my spec and said so rather than diverging silently: M4.2 asked for
an unknown-port corpus entry yielding `host-9999`, which the six-port `_PORT` regex can never
match. It kept the mandated six-port map and added a generic `_ANY_PORT` fallback in
`_unreachable_target`. That fallback only runs inside the `_UNREACHABLE` branch, so it cannot
mislabel a non-connection failure. Accepted.

Corpus: 24 entries, 11 real + 13 synthetic, all five kinds covered, no duplicate ids, no
omitted samples.

## 2026-09-21 - Grafana admin password rotated (operator-approved); PR #130 open and RED

**Grafana rotation DONE and verified.** Triggered the existing in-cluster rotator rather than
running anything by hand: `kubectl create job --from=cronjob/grafana-credential-rotator -n
monitoring` (job `grafana-rotate-manual-20260921-195152`). Prerequisites checked read-only
first: CronJob present and unsuspended (had never run — `lastScheduleTime: <none>`),
ExternalSecret `SecretSynced=True`, Grafana 1/1, `vault-0` ready, rotator SA present.

Verified sequence from cluster state, not from the job's word: started 02:51:52Z → Vault write
→ ESO `force-sync=1790045517` (02:51:57Z) → Grafana pod recreated 02:52:05Z → completed
02:54:13Z, `SuccessCriteriaMet`, and the `trap restore EXIT` never fired. Login probe from
inside the Grafana pod using its own mounted credential: **200**; same probe with a deliberately
wrong password: **401**. The negative control matters — it proves the 200 is enforced auth and
not a false green (the mistake I made earlier with the Prometheus probe). Grafana and Vault
therefore agree, and the password the operator pasted into a session is now invalid.

Note for future rotations: the rotator's own logs are empty by design (every step redirects to
/dev/null), so progress must be read from cluster state. It does call
`grafana cli admin reset-admin-password`, but with `--password-from-stdin` and only *after*
Vault is updated and ESO re-synced — that is the sanctioned path. Running that CLI standalone
remains forbidden because it desyncs Grafana from Vault.

**Keycloak admin is NOT rotated and has no rotator.** Only `argocd-` and
`grafana-credential-rotator` exist. Keycloak's admin password arrives via
`scripts/etc/keycloak/externalsecret-admin.yaml.tmpl` → `auth.existingSecret` /
`passwordSecretKey`, which is a **bootstrap-only** input: the admin user already exists in the
database, so updating Vault and restarting will NOT change the live password. Rotation needs
three ordered steps (change inside Keycloak via kcadm → update `secret/keycloak/admin`
`admin_password` → verify). `db_password` in that same secret is the Postgres credential and
must not be touched. Awaiting the operator's choice between a manual 3-step and specing a
`keycloak-credential-rotator` to match the other two.

### PR #130 is open and CI is RED — 4 failures, all introduced by this branch

https://github.com/wilddog64/k3d-manager/pull/130 (`07bb4377`). `main` is fully green.

1. `bats_negation_lint` test 57 — two bare `!` assertions in
   `scripts/tests/plugins/observability_prometheus_reseed.bats:47,84`, from Codex's reseed run
   (`6c744a23`). `!` suppresses `set -e`, so both assertions pass even when their grep matches:
   they have never been capable of failing.
2. `observability.bats` tests 3 and 8 — **a real design bug in my own reseed fix.**
   `_observability_ensure_prometheus_login:290-296` collapses "Vault unreachable" and "entry
   absent" into the same empty `_prom_creds`, so an unreachable Vault now fabricates a new
   password, attempts a reseed, fails, and returns 1 — aborting `deploy_observability_acg`.
   Test 8 exists to pin the opposite invariant (do not fabricate credentials when Vault is
   unreadable), which is the "Vault is canonical" decision of
   `docs/bugs/2026-06-09-prometheus-basic-auth-vault-managed.md`. curl distinguishes a 404 from
   a connection failure; the code does not.
3. `alertmanager_config_secret.bats` test 388 — asserts "all three values are required", a
   message `ee32878f` replaced with "unresolved:". Its `kubectl` stub also returns empty, so the
   target now exits at the root-token check before reaching the validation the test targets:
   stubs need fixing, not just the string.

**Verification lesson, the same shape twice.** For `6c744a23` I ran the two suites Codex named
plus a mutation check and called it verified, but never ran the suites that already covered the
function being changed (`scripts/tests/lib/observability.bats`) nor the repo-wide meta-lints
(`scripts/tests/lib/bats_negation_lint.bats`). Changing a function means running every suite
that touches it, not the suites the agent chose to mention.

**Method error worth recording:** I first reported these as pre-existing on `main`. That was
wrong. `scripts/tests/lib/observability.bats:14` uses a *relative* `source
scripts/plugins/observability.sh`, which resolves against the working directory — so running
bats from the main repo against a worktree path silently sources the branch's plugin. To test
another ref, the working directory must actually be that worktree.

## Keycloak admin credential ROTATED — 2026-09-22 (live hub)

The rotator from `46eb572b` was applied and run against the live k3d hub. It is done and
verified; the leaked admin password is dead.

Sequence actually executed (the CronJob did not exist in-cluster beforehand — `46eb572b` only
added the source):

1. Pre-flight probe pod (`envFrom: keycloak-secrets`) against `realms/master`:
   `good=200 bad=401`. This proved Vault's `admin_password` was still valid for the master realm
   *before* starting — the rotator's first step is a password grant with that value, so a drifted
   password would have failed the job at step 1.
2. `kubectl apply -f scripts/etc/argocd/platform-ops/keycloak-credential-rotator.yaml`
   (ServiceAccount, ClusterRole, ClusterRoleBinding, CronJob).
3. Vault policy + k8s auth role `keycloak-rotation` via
   `_vault_configure_secret_writer_role secrets vault keycloak-credential-rotator identity secret keycloak/admin keycloak-rotation keycloak-rotation`.
   **The dispatcher refuses underscore-prefixed functions** ("is private"), and there is no public
   wrapper — `_keycloak_apply_credential_rotator` is only reachable from the full `deploy_keycloak`
   path, which would have run a whole Helm upgrade. Sourced the libs in a scratch script instead.
4. Job `keycloak-rotate-manual-20260922-043917` → `SuccessCriteriaMet succeeded=1`, 0 restarts.

Verification pod (rotator SA, so it could read Vault, plus `envFrom: keycloak-secrets`):

    vault_admin_password=present
    vault_db_password=present
    db_password=MATCH(preserved)
    eso=stale(pre-refresh)
    new_password=200
    wrong_password=401
    eso_secret_password=401

`db_password=MATCH` compares Vault's value against the live `KC_DB_PASSWORD` in-shell — no base64
echo, no value printed. **`eso_secret_password=401` is the proof the rotation was real:** that is
the old password, still sitting in the not-yet-refreshed ExternalSecret, and it no longer works.
`wrong_password=401` is the negative control showing auth is genuinely enforced.

Keycloak and postgres-keycloak stayed 1/1 with 0 restarts throughout.

### Defect found: `base64 --decode` is not valid in the rotator image

The job's logs were NOT empty — they carried a BusyBox usage error. `docker.io/alpine/k8s:1.31.4`
ships BusyBox base64, which supports only `-d`; `--decode` is rejected. Confirmed directly in the
image: `printf aGk= | base64 -d` works, `--decode` prints usage and fails.

Impact by rotator:

- **keycloak** (lines 98 and 113) — both are `| base64 --decode || true`, so `slack_url` is always
  empty and **no Slack notification is ever sent, including the rollback-failure alert.** That
  alert is the one the spec called the worst-case signal; it is currently silent.
- **argocd** (line 139) — same silent-Slack bug. Worse, **line 117 has no `|| true`**:
  `old_bcrypt="$(kubectl ... | base64 --decode)"`. Under `set -eu` that aborts the job, so the
  ArgoCD rotator looks likely to be broken outright. NOT yet verified by running it.
- **grafana** (line 128) — correct, uses `base64 -d`. This is why the Grafana rotation succeeded.

Grafana is the correct precedent; keycloak and argocd drifted to the GNU long option. Fix is a
one-character change in three places, plus a test asserting no `--decode` in any platform-ops
manifest. Not yet filed or fixed.

### Unrelated open anomaly: `keycloak-realm-reconcile` failed 35h ago

Two pods `Error` exit 127, started 2026-09-21T00:33Z — predating this rotation by ~28h, not caused
by it. Logs show it logged in, created the `shopping-cart` realm shell, then died at
`environment: line 104: awk: command not found` while creating the `browser-with-conditional-otp`
flow. Image `quay.io/keycloak/keycloak:24.0` has no `awk`. **The realm was left partially
configured** — created but without its auth flows. Needs its own bug doc.

### 2026-09-22 — PR #130 CI reds fixed; rotator `base64` defect closed

Spec `docs/bugs/2026-09-22-ci-red-prometheus-reseed-and-rotator-base64.md` (`6658faff`), handed to
Codex, landed as `7d475a9f` + `0b9941c2`, refined by `1b7c6c93`. Full suite verified independently:
**1010/1010, zero failures**, with tests 57, 174, 179 and 388 — the exact four CI numbers — all
green. `scripts/tests/lib/observability.bats` diff confirmed empty: the guard tests were fixed
around, not weakened.

Root cause of the reds: `_observability_ensure_prometheus_login` collapsed "Vault unreachable" and
"entry absent" into `_prom_creds=""` and reseeded on both, so a transient port-forward outage would
rotate a credential nobody asked to rotate. Fixed with `_observability_vault_reachable()` probing
`sys/health` — unreachable now warns and returns 0 without touching Vault or the auth file; absent
still reseeds. The Vault header file is removed on all five exit paths, exactly once.

`base64 --decode` → `base64 -d` at keycloak 98/113 and argocd 117/118/139 (**118 was missed in the
first triage** — five sites, not four), plus `scripts/tests/plugins/platform_ops_rotators.bats`
banning the long form repo-wide and asserting each rotator still decodes.

**Correction worth keeping:** Codex ended `deploy_observability_acg` with
`(set +e; _observability_refresh_prometheus_auth_proxy) || true; return 0`. The tolerance is
correct — test 174's contract is that a failed Vault seed still yields a successful ACG deploy via
the generated web config — but the failure was discarded silently. The `(set +e; ...)` subshell is
**load-bearing**: the failure originates two frames down in `_observability_ensure_prometheus_login`
and `set -e` kills the chain there, so a plain `if ! cmd` does NOT suppress it (verified
empirically — replacing the subshell made test 174 fail again). `1b7c6c93` keeps the subshell, adds
a `_warn`, and drops the redundant `return 0`.

### Prometheus `show-service-passwords` N/A — diagnosed, repair NOT yet run

Live hub, 2026-09-22: Vault PF **up** (`sys/health`=200) but
`secret/k3d-manager/prometheus-basic-auth` returns **404 with no metadata at all**
(`version=None`), so there is no soft-deleted version to restore — the path was
metadata-deleted or never seeded. The local cache
`~/.local/share/k3d-manager/prometheus-basic-auth.env` still holds a real 32-char password.

`make show-service-passwords` reads Vault **inline in the Makefile recipe**, not through any plugin
function, so the reseed fix does not change its output. Nothing is actually broken: per the
2026-08-22 incident notes the hub Prometheus is unauthenticated at the edge, making this path a
display-mirror plus local-auth-proxy credential (recorded, not re-verified).

Correct repair is the **cache-recovery branch** of `_observability_ensure_prometheus_login`
("recovered ... not rotating"), which restores Vault from the local cache without rotating.
`observability_rotate_prometheus_basic_auth` is the WRONG tool: it generates a new password, and
run bare its context resolves to the **ACG app cluster** (`_observability_acg_context` →
`ubuntu-k3s`), writing hub Vault first and then failing on the wrong context — turning a cosmetic
N/A into a real lockout. The function is private, so reaching it needs a scratch sourcing script.
**Awaiting the operator's go; nothing live has been run.**

### 2026-09-22 — CI red twice more after the fix: latent pytest failures behind the BATS reds

`make test` alone is **not** CI's gate. The `lint` job runs `make test` *and* `make test-pytest`
as separate sequential steps, so the four BATS reds had been aborting the job before pytest ran.
Greening BATS exposed a doc-links failure that had been latent, not introduced. `make test-all`
(`test test-bin test-python`) is the real superset; `make test-pytest` cannot run locally because
its `python3` is Homebrew 3.14.7 without pytest — run bare `pytest` on the same three paths.

The failure was `test_check_doc_links::test_repo_docs_have_no_broken_links` on markdown links
pointing at `/Users/cliang/src/gitrepo/personal/k3d-manager/...`. These resolve on this Mac and
nowhere else, so `make check-doc-links` and the gate itself both pass locally — a Linux-only red
invisible to every local check.

First attempt fixed only the one file the assertion named (`5341d700`) and CI failed again: the
assertion truncates its list (`['docs/issues...t exist', ...]`). Enumerating with the checker's own
parser found **12 links across 5 files**, fixed together in `f3430476`, which also adds
`test_no_doc_links_target_an_absolute_path` to ban the shape outright so the class is now
locally detectable. Mutation-verified: reintroducing one absolute link fails the new guard while
the original broken-link gate stays green.

Commits: `937a5b3b` (docs/memory-bank), `5341d700` (partial, insufficient), `f3430476` (complete
+ guard). Local state at `f3430476`: BATS 1010/1010, pytest 176/176, check-doc-links 1733 OK.
