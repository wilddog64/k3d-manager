# E2E exporter emits empty-valued `e2e_last_run_duration_seconds`

**Date:** 2026-08-21 (severity corrected 2026-08-21 with live evidence)
**Branch found on:** `k3d-manager-v1.26.0`; re-observed live on `k3d-manager-v1.27.0`
**Severity:** ~~Minor / cosmetic~~ **HIGH / BLOCKING** — the invalid line breaks the entire
exporter scrape, not just this one metric.
**Status:** ✅ FIXED + LIVE-VERIFIED 2026-08-21 (`5cd67228`)
**Origin:** Finding 1a of `docs/bugs/2026-08-21-lifecycle-e2e-live-acceptance-findings.md`

## Resolution (2026-08-21, `5cd67228`)

Added a `num()` helper next to `esc()` that coerces `None`/empty/non-numeric to `"0"` and
preserves integer display for timestamps (`str(int(f)) if f.is_integer() else repr(f)`).
Routed **every** numeric gauge emission through it — `e2e_last_run_timestamp_seconds`,
`e2e_last_run_duration_seconds`, `e2e_last_success_timestamp_seconds`,
`cve_remediation_requested_timestamp_seconds`, `cve_remediation_applied_timestamp_seconds` —
so no single malformed value can ever zero out the whole scrape again.

Verified: `py_compile` clean; `num()` unit cases pass (`''`/`None`/garbage → `0`, timestamps
stay integer-formatted, fractional durations preserved). Redeployed via `kubectl apply` +
`rollout restart` (argocd.sh path). Live confirmation:

```
up{job="vulnerability-inventory-exporter"} = 1   (new pod, 3711 samples scraped)
e2e_last_run_duration_seconds{tier="vcluster",service="product-catalog",project="api+flows"} 0
e2e_run_info                    -> 2 series (back)
trivy_vulnerability_inventory   -> 3706 series (back — CVE dashboard restored)
```

No metric line ends with an empty value. Both the E2E and CVE/vulnerability dashboards are
receiving data again.

## Symptom

When an E2E run has an empty/null `duration_seconds` (the Job failed before a duration was
computed — e.g. phase `running-playwright`), the `vulnerability-inventory-exporter` emits:

```
e2e_last_run_duration_seconds{tier="vcluster",service="product-catalog",project="api+flows"} 
```

— i.e. the metric line has **no value after the label set**, which is an invalid Prometheus
exposition line.

## Actual impact (corrected — NOT cosmetic)

An invalid exposition line makes Prometheus reject the **whole scrape payload**, not just the
bad line. Confirmed live 2026-08-21 during the v1.27.0 foundation-vCluster-CLI live gate:

```
up{job="vulnerability-inventory-exporter"} = 0
lastError: expected value after metric, got "\n" ("INVALID") while parsing:
  "e2e_last_run_duration_seconds{tier=\"vcluster\",service=\"product-catalog\",
   project=\"api+flows\"} \n"
```

Because the target is `up=0`, Prometheus ingests **none** of the exporter's series — every
`e2e_*` gauge **and** all `trivy_*` / `cve_remediation_state` / vulnerability-inventory
metrics disappear from Prometheus (verified: all query empty while the exporter's own
`:8080/metrics` serves them correctly via port-forward). This blinds the E2E promotion
dashboard AND the entire CVE/vulnerability dashboard until a *passing* run (with a numeric
duration) happens to re-validate the payload. The v1.26.0 acceptance only saw
`e2e_last_run_pass=0` in Prometheus because that run carried a numeric duration; the first
failed run with an empty duration silently took the whole exporter offline for Prometheus.

## Root cause

`scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml` (embedded
`exporter.py`), **line 344**:

```python
lines.append("e2e_last_run_duration_seconds{" + body + "} " + str(event["duration_seconds"]))
```

`event["duration_seconds"]` arrives as `""` (empty string) from the result ConfigMap on a
failed run, so `str("")` renders an empty value. (`payload.get("duration_seconds", 0)` at
line 223 does not help — the key is present with an empty value, so the default never applies.)

## Fix direction

Coerce an empty/null `duration_seconds` to `0` before emitting the metric line at line 344
(e.g. `d = event["duration_seconds"]; d = d if d not in (None, "") else 0`). Keep the other
four series unchanged. Add exporter unit coverage asserting a valid
`e2e_last_run_duration_seconds … 0` line — and, ideally, a guard/test that a single malformed
value can never zero out the whole scrape (emit `0`/omit rather than empty for any numeric
gauge). Redeploy the exporter via `argocd.sh` (platform-ops verify-script CM path, NOT
ArgoCD). Confirm `up{job="vulnerability-inventory-exporter"}=1` and the series return.
