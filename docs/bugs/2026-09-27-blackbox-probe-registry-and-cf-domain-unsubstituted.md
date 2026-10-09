# Blackbox probes never work: doubled image registry + an unsubstituted `${CF_DOMAIN}`

**Filed:** 2026-09-27
**Branch:** `k3d-manager-v1.39.0`
**Introduced by:** `ba2a01e1 feat(observability): add public endpoint blackbox probes` (this release —
never merged to `main`, so no released version is affected)
**Blocks:** every operator-owned verification gate in
`docs/plans/v1.39.0-public-endpoint-blackbox-probes.md`
**Status:** FIXED in `cc4d634b` — evidence: `scripts/plugins/observability.sh:98-112` (triaged 2026-10-08, Codex)

## Symptom

The hub blackbox exporter has never pulled its image, and the Probe CRs it would serve carry a
literal `${CF_DOMAIN}` in every target. Live hub, before the fix:

```
blackbox-exporter-prometheus-blackbox-exporter-6997c7db64-js8mx   0/1   ImagePullBackOff   137m
  Image:  quay.io/quay.io/prometheus/blackbox-exporter:v0.27.0
  Events: BackOff ... (x593 over 137m)
```

Because every alert in `scripts/etc/prometheus/rules/public-endpoints.yaml` is written against
`probe_success{job=~".*blackbox.*"}`, the whole feature is inert: `PublicEndpointDown`,
`CloudflareTunnelDown` and `PublicEndpointProbeAbsent` cannot evaluate against real data.

## Defect 1 — the image registry is prefixed twice

`prometheus-blackbox-exporter` chart 11.3.1 splits the image across two keys and concatenates
them:

```yaml
image:
  registry: quay.io
  repository: prometheus/blackbox-exporter
```

`scripts/etc/helm/observability/blackbox-exporter-values.yaml` overrides `repository` with a
*fully-qualified* path, so the chart renders `quay.io/quay.io/prometheus/blackbox-exporter`.

## Defect 2 — `${CF_DOMAIN}` is substituted by nothing

`scripts/etc/prometheus/rules/public-endpoint-probes.yaml` contains seven `${CF_DOMAIN}`
placeholders. Three facts make them permanent:

1. `CF_DOMAIN` is never assigned or exported anywhere in the repo. It is only ever *read*, in
   `bin/cluster-up:1887-1889` and `2008-2012`, each time with a `:-3ai-talk.org` fallback that
   makes the unset variable invisible.
2. The apply path is a raw directory apply — `scripts/plugins/observability.sh:92-96` runs
   `_kubectl apply -f "${_rules_dir}/"` with no `envsubst`, while that same plugin calls
   `envsubst` correctly at six other sites (lines 27, 36, 78, 605, 614, 659).
3. `kubectl apply` does not validate `spec.targets.staticConfig.static` as a URL, so the literal
   string is accepted. The failure therefore surfaces at *probe* time as `probe_success 0`
   attributed to a DNS error — a green apply producing a red metric for a fabricated reason.

This is the same defect class as the `{{HOME}}` placeholder in the cloud-bridge launchd template
caught earlier the same day: **a placeholder is only as good as the renderer that substitutes
it.** `docs/howto/public-endpoint-alerts.md:4-6` already asserts the suffix "is supplied by the
deployment environment" — that sentence was aspirational, not descriptive.

## Defect 3 — no test covers any of it

`command grep -rln 'public-endpoint\|probe_success\|blackbox' scripts/tests` returns nothing.
Defects 1 and 2 are both statically detectable from the tree alone; zero coverage is why both
shipped in one commit.

---

## Before You Start

1. `git pull origin k3d-manager-v1.39.0`
2. Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
3. Read these files in full before editing any of them:
   - `scripts/etc/helm/observability/blackbox-exporter-values.yaml`
   - `scripts/etc/prometheus/rules/public-endpoint-probes.yaml`
   - `scripts/plugins/observability.sh` (at minimum lines 1-20 and 85-100)
   - `scripts/plugins/tunnel.sh` lines 1-12 — the repo's existing pattern for sourcing an
     `etc/<area>/vars.sh` from a plugin
   - `docs/howto/public-endpoint-alerts.md`

**Branch:** `k3d-manager-v1.39.0` (already checked out; do NOT create a new branch, do NOT
touch `main`).

---

## M1 — drop the duplicated registry from the values file

`scripts/etc/helm/observability/blackbox-exporter-values.yaml`, line 2.

OLD:
```yaml
image:
  repository: quay.io/prometheus/blackbox-exporter
  tag: v0.27.0
  pullPolicy: IfNotPresent
```

NEW:
```yaml
image:
  repository: prometheus/blackbox-exporter
  tag: v0.27.0
  pullPolicy: IfNotPresent
```

Do NOT add an `image.registry` key — the chart already defaults it to `quay.io`, and pinning it
here would be a second place to keep in sync. Do not change `tag` or `pullPolicy`.

## M2 — create `scripts/etc/vars.sh` as the home for `CF_DOMAIN`

This file does not exist yet. Create it with exactly this content:

```bash
# Shared cross-plugin configuration — override via the environment.
#
# CF_DOMAIN is the public DNS suffix fronted by the Cloudflare tunnel. Every public hostname
# (argocd, frontend, keycloak, grafana, prometheus, alertmanager, webhook) is CF_DOMAIN-suffixed,
# and the monitoring manifests in scripts/etc/prometheus/rules/ are rendered against it.
export CF_DOMAIN="${CF_DOMAIN:-3ai-talk.org}"
```

The `${CF_DOMAIN:-...}` form is required: an operator-exported value must win over the default.
This matches the style of `scripts/etc/cluster_var.sh` and `scripts/etc/tunnel/vars.sh`.

## M3 — source `scripts/etc/vars.sh` from the observability plugin

`scripts/plugins/observability.sh`, top of file. The existing block is:

OLD:
```bash
#!/usr/bin/env bash
# scripts/plugins/observability.sh

# Source Vault plugin so _vault_exec/_vault_exec_stream/_vault_configure_secret_writer_role
# are available during deploy_observability (the dispatcher lazy-loads only this plugin).
VAULT_PLUGIN="$PLUGINS_DIR/vault.sh"
if [[ -r "$VAULT_PLUGIN" ]]; then
   # shellcheck disable=SC1090
   source "$VAULT_PLUGIN"
fi
```

NEW:
```bash
#!/usr/bin/env bash
# scripts/plugins/observability.sh

# Source Vault plugin so _vault_exec/_vault_exec_stream/_vault_configure_secret_writer_role
# are available during deploy_observability (the dispatcher lazy-loads only this plugin).
VAULT_PLUGIN="$PLUGINS_DIR/vault.sh"
if [[ -r "$VAULT_PLUGIN" ]]; then
   # shellcheck disable=SC1090
   source "$VAULT_PLUGIN"
fi

_OBSERVABILITY_ETC_VARS="${SCRIPT_DIR}/etc/vars.sh"
if [[ -r "${_OBSERVABILITY_ETC_VARS}" ]]; then
   # shellcheck disable=SC1090
   source "${_OBSERVABILITY_ETC_VARS}"
fi
```

## M4 — render the rules directory through `envsubst`

`scripts/plugins/observability.sh`, the PrometheusRules apply block (around line 92).

OLD:
```bash
  local _rules_dir="${SCRIPT_DIR}/etc/prometheus/rules"
  if [[ -d "${_rules_dir}" ]]; then
    _kubectl apply -f "${_rules_dir}/" >/dev/null \
      && _info "[observability] PrometheusRules applied from ${_rules_dir}/"
  fi
```

NEW:
```bash
  local _rules_dir="${SCRIPT_DIR}/etc/prometheus/rules"
  if [[ -d "${_rules_dir}" ]]; then
    : "${CF_DOMAIN:=3ai-talk.org}"
    export CF_DOMAIN
    local _rule_file
    local _rules_applied=0
    for _rule_file in "${_rules_dir}"/*.yaml; do
      [[ -f "${_rule_file}" ]] || continue
      # shellcheck disable=SC2016
      if envsubst '$CF_DOMAIN' < "${_rule_file}" | _kubectl apply -f - >/dev/null; then
        _rules_applied=$((_rules_applied + 1))
      else
        _err "[observability] Failed to apply PrometheusRule ${_rule_file}"
        return 1
      fi
    done
    _info "[observability] ${_rules_applied} PrometheusRule file(s) applied from ${_rules_dir}/"
  fi
```

Three properties this must preserve, and the reasons:

- **The `envsubst` allowlist is explicit (`'$CF_DOMAIN'`).** A bare `envsubst` would eat every
  `$`-sigil in the directory. Do not widen it.
- **A failed apply now returns 1.** The old form swallowed failures because `&&` only gated the
  `_info`. Keep the explicit `return 1`.
- **The `: "${CF_DOMAIN:=3ai-talk.org}"` line stays even though M2/M3 supply it.** `deploy_observability`
  must not depend on source ordering for a value that silently degrades to an empty suffix.

## M5 — a BATS suite that would have caught all three

Create `scripts/tests/plugins/observability_public_endpoint_probes.bats`. It must assert against
the real source files, never an inline copy, and each assertion must fail on the pre-fix tree.

Required tests:

1. **The values file does not fully qualify the repository.** Assert
   `scripts/etc/helm/observability/blackbox-exporter-values.yaml` contains
   `repository: prometheus/blackbox-exporter` and contains no `repository: quay.io/` line. Phrase
   the negative as a disappearance gate — `quay.io/prometheus` must not appear in the file at all.
2. **`scripts/etc/vars.sh` exports `CF_DOMAIN` with an environment override.** Assert the file
   exists and contains `export CF_DOMAIN="${CF_DOMAIN:-`.
3. **The rules apply path runs `envsubst`.** Assert `scripts/plugins/observability.sh` contains
   `envsubst '$CF_DOMAIN'` and that the bare `_kubectl apply -f "${_rules_dir}/"` form is gone.
4. **The defect-class guard — every placeholder in the rules directory is in the allowlist.**
   This is the test that matters; the others only pin today's two bugs. Extract every distinct
   `${NAME}` placeholder from every file under `scripts/etc/prometheus/rules/`, and for each one
   assert that `observability.sh` names it inside an `envsubst '...'` allowlist. A new rule file
   introducing `${FOO}` must fail this test until `$FOO` is added to the allowlist.
5. **Every Probe target is CF_DOMAIN-suffixed, not hardcoded.** Assert
   `scripts/etc/prometheus/rules/public-endpoint-probes.yaml` contains no literal `3ai-talk`
   (a disappearance gate) and that it still contains seven `${CF_DOMAIN}` occurrences.

BATS constraints for this repo:
- No bare `!` for negation — use `run ...` plus an explicit `[ "${status}" -ne 0 ]`.
- No whole-line `grep -F` of a source line — assert meaningful tokens only.
- Prove each test can fail: before committing, temporarily revert one hunk at a time and confirm
  the matching test goes red. Paste that evidence in your report.

## M6 — documentation

`docs/howto/public-endpoint-alerts.md`. The opening paragraph currently claims the suffix "is
supplied by the deployment environment", which was not true before M2-M4. After the fix it is
true but incomplete — it does not say where the default comes from or how to override it. Add a
short paragraph after the existing one naming:

- `scripts/etc/vars.sh` as the default source of `CF_DOMAIN`,
- that exporting `CF_DOMAIN` overrides it,
- that `deploy_observability` renders `scripts/etc/prometheus/rules/*.yaml` through `envsubst`,
  so a new rule file may use `${CF_DOMAIN}` but any *other* new placeholder must be added to the
  allowlist in `scripts/plugins/observability.sh`.

Do NOT add a `### Fixed` entry to `CHANGELOG.md`. These defects were introduced and corrected on
the same unmerged release branch, so no released version ever carried them and a `Fixed` entry
would document a regression that never reached a user. Leave the existing `### Added` blackbox
bullet under `## [1.39.0]` alone.

---

## Rules

- `shellcheck scripts/plugins/observability.sh scripts/etc/vars.sh` — zero new warnings.
- `bats scripts/tests/plugins/observability_public_endpoint_probes.bats` — all green.
- `bats -r scripts/tests/plugins/` takes roughly six minutes; run it and confirm no regression in
  the other observability suites. Do not abandon it as a hang.
- Double-quote every variable expansion. LF endings only. No inline comments inside shell blocks
  beyond the ones written literally above.
- Do not reformat, reorder or refactor anything the M-items do not name.

## Definition of Done

- [ ] M1 — `blackbox-exporter-values.yaml` repository de-qualified
- [ ] M2 — `scripts/etc/vars.sh` created, exporting `CF_DOMAIN` with an override
- [ ] M3 — `observability.sh` sources `scripts/etc/vars.sh`
- [ ] M4 — the rules directory is applied through `envsubst '$CF_DOMAIN'`, per-file, failing loudly
- [ ] M5 — `scripts/tests/plugins/observability_public_endpoint_probes.bats` created, all five
      tests green, each one proven to fail against the pre-fix source
- [ ] M6 — `docs/howto/public-endpoint-alerts.md` documents the `CF_DOMAIN` source, the override,
      and the allowlist obligation
- [ ] `shellcheck` clean; the new suite green; `bats -r scripts/tests/plugins/` shows no regression
- [ ] Committed with exactly this message:

```
fix(observability): render blackbox probe targets and de-qualify the exporter image

The exporter never pulled: chart 11.3.1 concatenates image.registry with
image.repository, so a fully-qualified repository rendered
quay.io/quay.io/prometheus/blackbox-exporter. And every Probe target carried a
literal ${CF_DOMAIN}, because the rules directory was applied raw while
CF_DOMAIN was never assigned anywhere in the repo — kubectl accepts the string,
so the failure surfaced as probe_success 0 blamed on DNS.

CF_DOMAIN now lives in scripts/etc/vars.sh and the rules directory is rendered
per-file through an explicit envsubst allowlist. The new BATS suite pins both
fixes and adds a defect-class guard: any placeholder appearing in the rules
directory must be named in that allowlist.
```

- [ ] Pushed to `origin/k3d-manager-v1.39.0`; confirm with `git rev-parse origin/k3d-manager-v1.39.0`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with the SHA and status
- [ ] Report: the SHA, `git show <sha> --stat`, the BATS output, the mutation-test evidence for M5,
      and the memory-bank lines you wrote

## What NOT to Do

- Do NOT create a PR. Do NOT merge anything.
- Do NOT commit to `main`. Work only on `k3d-manager-v1.39.0`.
- Do NOT use `--no-verify`.
- Do NOT touch any file outside the six named in the M-items plus the two memory-bank files.
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/` — they are subtrees.
- Do NOT run `kubectl`, `helm`, `docker` or `make up` against any live cluster. This task is
  static-tree only; redeploying the corrected chart is the operator's step.
- Do NOT widen the `envsubst` allowlist to a bare `envsubst`.
- Do NOT hardcode `3ai-talk.org` into any manifest under `scripts/etc/prometheus/rules/`.
