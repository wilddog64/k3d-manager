# Bug: ACG sandbox critical alerts text the operator; email is enough

**Branch:** `k3d-manager-v1.41.0`
**Filed:** 2026-10-03, Claude
**Status:** FIXED. The ACG email-only route is live on the hub Alertmanager (recorded in `d2ad5098`). Status line updated 2026-10-04.
**Files:** `scripts/etc/prometheus/alertmanager.yaml.tmpl`, `scripts/tests/plugins/alertmanager_config_secret.bats`, `docs/guides/grafana-dashboards.md` or the Alertmanager routing section that documents SMS vs email, `CHANGELOG.md`

## What the operator asked for

> "email alert for ACG sandbox are good enough. no need to send text message. only hub and hostinger have to"

## Root cause

- **One template serves both clusters.** The hub and the ACG sandbox both render the same Alertmanager config, `scripts/etc/prometheus/alertmanager.yaml.tmpl`:
  - the hub renders it in `scripts/plugins/observability.sh` at about line 81;
  - the ACG sandbox renders it at about line 672.
- **The template has no cluster matcher.** It routes every `severity = critical` alert to `sms-critical`, which emails the carrier SMS gateway. So the sandbox's own Alertmanager texts the operator for every critical sandbox alert.
- **Sandbox alerts can be told apart by their `cluster` label.** Prometheus copies its `externalLabels` onto every alert it sends to Alertmanager:
  - **ACG sandbox Prometheus:** `cluster: ubuntu-k3s` (`kube-prometheus-stack-acg-values.yaml`);
  - **hub Prometheus:** `cluster: hub`;
  - **hub's `federate-acg` scrape job:** labels sandbox series it pulls in with `cluster: acg`.
- **Hostinger is not affected.** It has no Prometheus or Alertmanager in this repo. Its paging comes from Hermes (`bin/k3dm-hermes` SMS pager), which this fix does not touch.

## Fix

### A1 — `alertmanager.yaml.tmpl`: route sandbox criticals to email

Insert a new route directly after the Trivy `null` route, before the `severity = critical` → `sms-critical` route. Old:

```yaml
    - matchers:
        - alertname = TrivyCriticalVulnerabilityDetected
      receiver: 'null'
    - matchers:
        - severity = critical
      receiver: sms-critical
```

New:

```yaml
    - matchers:
        - alertname = TrivyCriticalVulnerabilityDetected
      receiver: 'null'
    - matchers:
        - severity = critical
        - cluster =~ "acg|ubuntu-k3s"
      receiver: platform-warning
    - matchers:
        - severity = critical
      receiver: sms-critical
```

- **This one route covers both delivery paths:**
  - the sandbox's own Alertmanager, where alerts carry `cluster=ubuntu-k3s`;
  - any hub rule that fires on federated sandbox series, which carry `cluster=acg`.
- **Hub criticals still text.** They carry `cluster=hub`, or no `cluster` label at all, and fall through to `sms-critical` exactly as before.
- **Reuse `platform-warning`; do not add a receiver.** It already emails `ALERTMANAGER_GMAIL_FROM` with `send_resolved: true` and identifies the cluster in its Subject.
- **Do not set per-route timings** on the new route. It inherits the root `group_wait` / `group_interval` / `repeat_interval`, the same as `sms-critical` does today.
- **Change nothing else** in the template.

### A2 — tests: `scripts/tests/plugins/alertmanager_config_secret.bats`

- **Shift the existing index-based assertions by one.** The inserted route moves every later route, so `routes[1]` → `routes[2]`, `routes[2]` → `routes[3]`, and so on. Change only the indices; every asserted value stays the same. Also fix any `route.routes[N]` index in `scripts/tests/plugins/e2e_observability.bats` that the insert shifts.
- **Add a test, "Alertmanager sends ACG sandbox criticals to email, not SMS",** asserting:
  - `routes[1].receiver` is `platform-warning`;
  - `routes[1].matchers` contains `severity = critical`;
  - `routes[1].matchers` contains a `cluster =~` matcher that matches both `acg` and `ubuntu-k3s`;
  - `routes[2].matchers[0]` is `severity = critical`, and `routes[2].receiver` is `sms-critical`. That proves the hub fallthrough still exists.
- **Add a routing test with `amtool` if it is installed:**
  - render the template with `envsubst`, using placeholder values `a@example.com`, `x` and `1234567890@example.com` (never real values);
  - run `amtool config routes test --config.file=<rendered> severity=critical cluster=ubuntu-k3s` → `platform-warning`;
  - the same with `cluster=acg` → `platform-warning`;
  - the same with `cluster=hub` → `sms-critical`;
  - `alertname=TrivyCriticalVulnerabilityDetected severity=critical cluster=hub` → `null`;
  - if `amtool` is absent, `skip` with a message rather than fail.

### A3 — docs

- **Routing doc:** find the doc that describes SMS-vs-email routing; `git grep -n "sms-critical" -- docs/guides docs/howto docs/architecture` finds it. Add one sentence saying ACG sandbox criticals email, and that only hub criticals text. If no such doc exists, add that sentence to the Alertmanager section of `docs/guides/grafana-dashboards.md`.
- **`CHANGELOG.md` `[Unreleased]` → `### Changed`:** one prose bullet.

## Gates (offline; paste actual output)

1. **The new and shifted assertions pass:** `bats scripts/tests/plugins/alertmanager_config_secret.bats scripts/tests/plugins/e2e_observability.bats`.
2. **`amtool` routes:** run the four `amtool` route checks and paste the output. If `amtool` is not installed, say so.
3. **Mutations.** For each one, `cp` a snapshot, mutate, show the BATS red, restore from the snapshot, and show `cmp` equality. Never restore with `git checkout`.
   - (a) delete the new route → the new test is red;
   - (b) change its receiver to `sms-critical` → the new test is red;
   - (c) move it after the `sms-critical` route → the new test is red.
4. **Validity:** `yq` parses the template, and `envsubst`-rendered output passes `amtool check-config` (if installed).
5. **Docs:** `python3 scripts/check-doc-links.py` passes.
6. **Scope:** `git diff --stat` shows only the files named above.

## Definition of Done

- [ ] A1–A3 complete; gates 1–6 pass, with output pasted.
- [ ] Commit message, exactly (trailers on consecutive lines):

  ```
  fix(alertmanager): email ACG sandbox critical alerts instead of texting them

  Co-Authored-By: Codex <noreply@openai.com>
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- [ ] `git push origin k3d-manager-v1.41.0`; report `git rev-parse origin/k3d-manager-v1.41.0`.
- [ ] Takes effect the next time `make observability` renders the secret: on the hub, and on the next sandbox `make up`. The operator decides when to run the hub one.

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, or use `--no-verify`.
- Do NOT edit `memory-bank/`.
- Do NOT change the `sms-critical` or `platform-warning` receivers, `observability.sh`, the Helm values, `Makefile` or `bin/k3dm-hermes`. The Hermes pager covers Hostinger and is out of scope.
- Do NOT read Vault, Keychain or the live `alertmanager-smtp-secret`. Do NOT run `make observability` or touch any cluster.
- Do NOT put a real email address or SMS gateway in a test or fixture.
