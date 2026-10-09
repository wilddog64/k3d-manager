# SMS pages never say "resolved", and nothing tests deduplication, repeats or recovery

**Filed:** 2026-10-08, Claude (operator: "let's do that at v1.44.0. text is free so that's fine")
**Branch:** target **v1.44.0**. Bug docs are exempt from the 5-plan cap; v1.44.0 already has 5 plan files.
**Status:** IMPLEMENTED — items 1–5 on k3d-manager-v1.42.0; live verification pending (operator)
**Priority:** P2 — a page with no "all clear" means checking a dashboard to learn a problem ended
**Severity:** Medium
**Component:** `scripts/etc/prometheus/alertmanager.yaml.tmpl`, new behaviour test, `scripts/plugins/observability.sh` (apply path)
**Related:** `docs/bugs/2026-09-20-sms-alert-body-is-unidentifiable.md` (made the SMS body legible; iterates `.Alerts.Firing`), `docs/plans/v1.42.0-host-disk-space-sensor.md` (the SMS proof)

## Symptom

The 2026-10-08 SMS proof (fake `host="smstest"` disk) showed what is and is not covered:

| Behaviour | Today |
|---|---|
| Deduplication | Works live. Prometheus re-sent the firing alert every evaluation; exactly one text went out (`alertmanager_notifications_total{integration="email"}` 21 → 22). There is no automated test for it. |
| Repeat | Configured as a 24h `repeat_interval` on the root route, which `sms-critical` inherits. It was never observed until the week-long `smstest` run (until 2026-10-15). Not tested. |
| Recovery | **Off.** `sms-critical` has `send_resolved: false` (`alertmanager.yaml.tmpl:42`, since v1.5.0 `faa00331`, with no recorded reason). `platform-warning` emails have `send_resolved: true`. Not tested. |

The existing BATS (`alertmanager_config_secret.bats`, `e2e_observability.bats`) only checks the
rendered configuration and its routing. Nothing exercises Alertmanager's actual behaviour.

## Root cause

1. `send_resolved: false` on `sms-critical`. The likely reason was text cost, but texts are free on
   the operator's plan (operator, 2026-10-08).
2. **A latent second bug that appears as soon as (1) is flipped.** The SMS `text:` body only ranges
   over `.Alerts.Firing`. That was correct for the 2026-09-20 legibility fix, but in a resolved
   notification `.Alerts.Firing` is empty. So the "all clear" text would carry only the subject,
   `[RESOLVED] … (0)`, with an empty body that names nothing. The `platform-warning` email has the
   same template shape, so its resolved emails are blank today too.

## Fix (spec for Codex)

### 1. Turn on SMS recovery

In `alertmanager.yaml.tmpl`, under `sms-critical`, change `send_resolved: false` to `send_resolved: true`.

### 2. Make resolved notifications name what recovered (both receivers)

Keep the firing block exactly as it is. After it, append a resolved block to both `text:` bodies:

```
{{ range .Alerts.Resolved }}RESOLVED {{ .Labels.alertname }}{{ if .Labels.severity }} [{{ .Labels.severity }}]{{ end }} on {{ if .Labels.cluster }}{{ .Labels.cluster }}{{ else }}unknown-cluster{{ end }}
where:{{ if .Labels.namespace }} ns={{ .Labels.namespace }}{{ end }}{{ if .Labels.instance }} instance={{ .Labels.instance }}{{ end }}{{ if .Labels.job }} job={{ .Labels.job }}{{ end }}
since: {{ .StartsAt.UTC.Format "2006-01-02 15:04 UTC" }} ended: {{ .EndsAt.UTC.Format "2006-01-02 15:04 UTC" }}
{{ end }}
```

Keep the SMS body short: no description line in the resolved block, because the firing text already
carried it. Follow the inline-template constraints in
`reference_alertmanager_inline_templates_no_sprig`: no Sprig functions such as `default`.

### 3. Behaviour test: real Alertmanager, fake receiver

Add a new test `scripts/tests/observability/test_alertmanager_notify_behaviour.py` (pytest).

**Setup:**
- Run the pinned image `quay.io/prometheus/alertmanager:v0.27.0`, the same one the hub runs.
  Keep the tag in one variable.
- Render the **real** template with dummy envsubst values.
- Rewrite only the delivery and the timers in Python:
  - Each receiver's `email_configs` becomes `webhook_configs` pointing at a local HTTP sink, keeping
    that receiver's `send_resolved` value.
  - Scale the timers down: `group_wait` 1s, `group_interval` 2s, `repeat_interval` 6s.
- Leave the route tree, the matchers and `inhibit_rules` untouched. Those are what the test is
  checking.
- Post alerts through `POST /api/v2/alerts`.

**Assertions:**

| Test | Steps | Expect |
|---|---|---|
| dedup | Post the same `severity=critical, cluster=hub` alert 5 times within 1s | exactly **1** firing notification at the `sms-critical` sink |
| repeat | Keep re-posting it (as Prometheus does) for about 15s | a **second** firing notification after `repeat_interval`, and no more than `ceil(15/6)+1` in total |
| recovery (SMS) | Post it with `endsAt` in the past | a notification with `status: resolved` at the `sms-critical` sink |
| recovery (email) | Same steps with a `severity=warning` alert | `status: resolved` at the `platform-warning` sink |
| routing guard | A critical alert with `cluster=acg` | goes to `platform-warning`, **not** `sms-critical` (sandbox alerts stay email-only, per `feedback_sandbox_alerts_email_only`) |
| Trivy guard | `alertname=TrivyCriticalVulnerabilityDetected, severity=critical` | no notification at any sink (`null`) |

Separately, add a template test: render both receivers' `text:` with a resolved-only alert using
`amtool template render` (available in Alertmanager v0.27.0 and later). The output must contain
`RESOLVED` and the alert name. **RED:** this must fail against the pre-fix template, where the body
renders empty.

**Running it:**
- The test needs Docker, so it is skipped when Docker is unavailable. The skip names the reason.
- Add `make test-alertmanager-behaviour` and a CI job on `ubuntu-latest`, which has Docker. Pin the
  actions, and set the workflow to `permissions: contents: read`.
- **RED:** the recovery (SMS) test and the template test must fail on the pre-fix template. Paste
  the failure names.

### 4. A lightweight apply path (optional, same release)

Today the template only reaches the hub through `make observability`, which is the full stack
redeploy, or through its ACG twin. Add `make alertmanager-config`, mirroring
`make prometheus-rules`. It re-renders the template with the same `envsubst` variable list and
applies the `alertmanager-smtp-secret` Secret, reusing the code at `observability.sh:81` by
extracting a helper rather than copying it.
- The operator runs it, because it reads credentials.
- It must never echo the rendered config, which contains the Gmail app password.

### 5. Docs

- `docs/guides/` (the Alertmanager or observability guide): SMS now sends a resolved text; how to
  run the behaviour test.
- CHANGELOG.

## Live verification (operator)

1. Run `make alertmanager-config`, or `make observability`.
2. Confirm the live config reads back `send_resolved: true` for `sms-critical`, using
   `amtool config show` filtered to `send_resolved`. Don't print anything else.
3. Fire a test alert, using the `k3dm-disk-smstest` Pushgateway job method from the disk-sensor plan.
   Expect a firing text.
4. Delete the job. Expect a `[RESOLVED]` text naming `HostDiskSpaceCritical` and `smstest`.

## Timing note

The `smstest` series pushed on 2026-10-08 is kept firing until **2026-10-15** on purpose. If
v1.44.0 is not live by then, deleting it on 10/15 resolves **silently**: no text, as today. If
recovery should be demonstrated on that delete, ship item 1 and item 2 first, as a bug fix.

## What NOT to do

- Do not lower `repeat_interval` or `group_wait` in the real config. The scaled timers exist only
  in the test copy.
- Do not send real email or SMS from any test.
- Do not print, log or commit the rendered config with real credentials.
- Do not change the route tree or matchers in this fix.

---

## Item 4 implementation spec (Codex, 2026-10-09)

**Branch:** `k3d-manager-v1.42.0`. **Files:** `scripts/plugins/observability.sh`, `Makefile`,
`scripts/tests/plugins/alertmanager_config_secret.bats`, the Alertmanager section of the guide that
item 5 updated, `CHANGELOG.md` (under the existing `[Unreleased]` SMS entry), and this doc's
`**Status:**` line. Nothing else.

### 4a. Extract one helper from the two copies

`deploy_observability` (hub, around line 54) and `deploy_observability_acg` (around line 644) each
carry an identical copy of "read `secret/k3d-manager/alertmanager` from Vault → render
`alertmanager.yaml.tmpl` → apply `alertmanager-smtp-secret`". The hub copy also `export`s the three
credentials, so they leak into the environment of every later command in that run. Replace **both**
blocks, from the `_info "[observability] Reading Alertmanager credentials from Vault..."` line
through the closing `fi` of the `if [[ -z "${_am_creds}" ]]` block, with a call to this new
function. Place the function right after `deploy_observability`:

```bash
function _observability_apply_alertmanager_config() {
  local _context="$1" _label="${2:-}"
  _info "[observability] Reading Alertmanager credentials from Vault..."
  local _vault_addr="http://127.0.0.1:18200"
  local _vault_token
  _vault_token=$(_kubectl get secret vault-root -n secrets \
    --context k3d-k3d-cluster -o jsonpath='{.data.root_token}' | base64 --decode)

  local _am_creds _vault_hdr
  _vault_hdr=$(mktemp)
  printf 'X-Vault-Token: %s\n' "${_vault_token}" > "${_vault_hdr}"
  if ! _am_creds=$(curl -sf \
      --header "@${_vault_hdr}" \
      "${_vault_addr}/v1/secret/data/k3d-manager/alertmanager" 2>/dev/null \
      | python3 -c "import json,sys; d=json.load(sys.stdin)['data']['data']; \
        v=[d['gmail_from'],d['gmail_app_pw'],d['sms_gateway']]; all(v) or sys.exit(1); print('|'.join(v))" 2>/dev/null); then
    _am_creds=""
  fi
  rm -f "${_vault_hdr}"

  if [[ -z "${_am_creds}" ]]; then
    _warn "[observability] Alertmanager Vault secret not found — skipping SMS config${_label}"
    _warn "[observability] Run: make alertmanager-secret to configure"
    return 1
  fi

  local _gmail_from _gmail_app_pw _sms_gateway _rest
  _gmail_from="${_am_creds%%|*}"
  _rest="${_am_creds#*|}"
  _gmail_app_pw="${_rest%%|*}"
  _sms_gateway="${_rest##*|}"

  local _am_tmpl="${SCRIPT_DIR}/etc/prometheus/alertmanager.yaml.tmpl"
  local _am_config
  # shellcheck disable=SC2016
  _am_config=$(ALERTMANAGER_GMAIL_FROM="${_gmail_from}" \
    ALERTMANAGER_GMAIL_APP_PW="${_gmail_app_pw}" \
    ALERTMANAGER_SMS_GATEWAY="${_sms_gateway}" \
    envsubst '${ALERTMANAGER_GMAIL_FROM} ${ALERTMANAGER_GMAIL_APP_PW} ${ALERTMANAGER_SMS_GATEWAY}' \
    < "${_am_tmpl}")
  local _am_tmpfile
  _am_tmpfile=$(mktemp)
  printf '%s' "${_am_config}" > "${_am_tmpfile}"
  _kubectl create secret generic alertmanager-smtp-secret \
    --context "${_context}" \
    -n monitoring \
    --from-file=alertmanager.yaml="${_am_tmpfile}" \
    --dry-run=client -o yaml | _kubectl apply --context "${_context}" -f - >/dev/null
  rm -f "${_am_tmpfile}"
  _info "[observability] Alertmanager config secret applied${_label} (${_context})"
}
```

Call sites. The `|| true` keeps today's behaviour, where a missing Vault secret is a warning and
the deploy continues:

- `deploy_observability`: `_observability_apply_alertmanager_config "${_hub_context}" || true`
- `deploy_observability_acg`: `_observability_apply_alertmanager_config "${_app_context}" " on ACG" || true`

The pipe into `apply` gains `>/dev/null`. `kubectl apply` prints only `secret/... configured` and
never the data, but nothing in this path should write stdout that could ever carry the config.

### 4b. Public entry point and make target

In `observability.sh`, directly after the helper:

```bash
function observability_alertmanager_config() {
  _observability_apply_alertmanager_config "k3d-k3d-cluster"
}
```

This function returns non-zero when the Vault secret is missing. Unlike the deploy paths, the
operator asked for exactly this one thing, so a skip must fail.

In `Makefile`, add `alertmanager-config` to `.PHONY`. Add the target directly after
`prometheus-rules`:

```make
## Re-render and apply the hub Alertmanager config (alertmanager-smtp-secret) only — no full observability redeploy
alertmanager-config:
	./scripts/k3d-manager observability_alertmanager_config
```

Add a row to the README make-target table if `prometheus-rules` has one; put it next to that row.

### 4c. Tests (`scripts/tests/plugins/alertmanager_config_secret.bats`)

Use stubs only: no cluster, no Vault, and no network.
1. Source `observability.sh` with `_kubectl`, `curl`, `_info` and `_warn` stubbed.
   - `curl` returns `{"data":{"data":{"gmail_from":"a@example.invalid","gmail_app_pw":"SENTINEL-PW","sms_gateway":"s@example.invalid"}}}`.
   - `_kubectl` records its args, and its stdin when the args contain `apply`.

   Run `_observability_apply_alertmanager_config ctx-x`. Assert:
   - status is 0;
   - the recorded `create secret` call contains `--context ctx-x`;
   - `SENTINEL-PW` does **not** appear in `$output`.
2. Same stubs, with `curl` exiting 22. Assert that the helper returns non-zero and that
   `observability_alertmanager_config` returns non-zero.
3. After test 1, `ALERTMANAGER_GMAIL_APP_PW` is unset in the calling shell:
   `[ -z "${ALERTMANAGER_GMAIL_APP_PW+x}" ]`. This is the leak the hub copy had.
4. Disappearance gate: `grep -c 'alertmanager.yaml.tmpl' scripts/plugins/observability.sh`
   returns `1`, so only one render site is left.
5. `make -n alertmanager-config` prints `observability_alertmanager_config`. This is safe because
   the target is not a lifecycle target.

Show test 3 and test 4 RED against the pre-change `observability.sh`, run on a temp copy.

### 4d. Gates

- `shellcheck scripts/plugins/observability.sh`: no new warnings.
- `bats scripts/tests/plugins/alertmanager_config_secret.bats` and every
  `scripts/tests/plugins/observability_*.bats` file: all green.
- `make check-doc-links`.

### Definition of Done

- [ ] 4a–4c implemented; the gates in 4d pass, with output pasted in your report.
- [ ] This doc's `**Status:**` reads: `IMPLEMENTED — items 1–5 on k3d-manager-v1.42.0; live verification pending (operator)`.
- [ ] One commit, message exactly:
  ```
  feat(observability): add make alertmanager-config and dedupe the Alertmanager secret apply

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- [ ] `git push origin k3d-manager-v1.42.0`; `git ls-remote origin k3d-manager-v1.42.0` equals `git rev-parse HEAD`.

### What NOT to do (item 4)

- Do NOT run `make alertmanager-config`, `make observability` or any target that reaches the cluster or Vault.
- Do NOT read Keychain items or any real credential, and do NOT print the rendered config.
- Do NOT change `alertmanager.yaml.tmpl`, the route tree or the envsubst variable list.
- Do NOT create a PR, commit to `main`, use `--no-verify`, or update memory-bank.
