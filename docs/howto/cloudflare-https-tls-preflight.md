# Cloudflare HTTPS and TLS preflight

This is an operator-run, read-only preflight for the seven proxied names under `3ai-talk.org`. The helper does not change Cloudflare settings and does not prove authentication workflows work. Existing reports of Always Use HTTPS being Off and minimum TLS being 1.0 remain unverified until an actual API or dashboard read.

## Run a preflight

The no-argument command and `--dry-run` print a plan without environment, network, process, or account access:

```sh
bin/k3dm-cloudflare-posture
bin/k3dm-cloudflare-posture --dry-run
```

The Make shortcut runs the same read-only check, using the zone ID shown on
Cloudflare's domain Overview page:

```sh
make cloudflare-preflight ZONE_ID=0123456789abcdef0123456789abcdef
```

Use `DRY_RUN=1` to print only the helper's plan, without probes or credential
access. The Make target uses the existing `CLOUDFLARE_API_TOKEN` environment for
API reads, just like the direct command. It does not retrieve credentials.
Missing credentials leave settings unknown while public probes still run.

For an actual bounded check, use an existing least-privilege Cloudflare API token with Zone Settings Read permission and the zone ID. Supply the token only through the already managed `CLOUDFLARE_API_TOKEN` environment; never put it in command arguments, shell history, logs, output, or a file. The helper sends it only to the fixed Cloudflare API HTTPS host, disables proxy inheritance and redirects, validates TLS normally, bounds response size/time, and makes GET requests only.

```sh
bin/k3dm-cloudflare-posture --check --zone-id 0123456789abcdef0123456789abcdef
```

Do not add token retrieval, Keychain access, or credential provisioning just for this check. Alternatively, pass an existing sanitized settings response snapshot:

```sh
bin/k3dm-cloudflare-posture --check --settings-file /path/to/sanitized-zone-settings.json
```

The existing environment token must already be available through the operator's secret-management workflow for API mode. No token argument is accepted.

Snapshot input is limited to 65,536 bytes, as is each API response; oversized, malformed, and failed responses become unknown. Snapshot output is explicitly labeled as an operator-supplied snapshot, not a current API read. Accepted snapshot shapes are a setting-name-to-value map, that map inside `settings`, a map of setting names to Cloudflare success responses or `{id, value}` objects, and a Cloudflare success envelope with a single result or result list. Every result object must have the matching setting ID; duplicate IDs are unknown. For example:

```json
{
  "settings": {
    "always_use_https": "off",
    "min_tls_version": "1.0",
    "ssl": "full",
    "security_header": {"strict_transport_security": {"enabled": false}},
    "tls_1_3": "on"
  }
}
```

Only documented setting strings are retained. Numeric/boolean substitutes for string settings, unknown values, wrong IDs, arbitrary text, and extra fields are discarded. HSTS output retains only the boolean `strict_transport_security.enabled`; its absence is unknown. The helper reports only `always_use_https`, `min_tls_version`, `ssl`, `security_header`, and `tls_1_3`; missing, malformed, unsuccessful, or unrecognized values remain unknown. Missing telemetry is not a healthy result. The HTTP and TLS sections are unauthenticated probes to the fixed seven hostnames; they do not submit credentials, follow redirects, store response bodies, or send authorization headers.

## Review F0 evidence

Capture the timestamped sanitized output and review each hostname individually. HTTP `301`/`308` with an HTTPS `Location` is edge redirect evidence; an HTTPS `302` to Keycloak is an authentication redirect and says nothing by itself about a successful login. HTTPS `200`, `302`, and expected unauthenticated `401` are baselines only, not proof of end-to-end application functionality. Location output retains only a known destination hostname and HTTP/HTTPS scheme. Every non-root path is redacted; user information, ports, queries, fragments, and arbitrary external hostnames are omitted. Comparison flags distinguish an exact root HTTP-to-HTTPS equivalent, a downgrade, and a self redirect without following any hop. A self redirect suggests a loop; loops across several hops still require manual review. Response bodies are never read for public probes. Unknown probe results remain inconclusive.

Exit status zero means the report completed, including when every setting is unknown. The JSON always reports `f0_complete: false`: the manual compatibility review and independent operator evidence are still required. This helper alone cannot complete F0 or resolve the security bug.

Record a before/after baseline for every row; do not replace missing observations with expected values:

| Hostname | HTTP status / sanitized destination | HTTPS status / sanitized destination | TLS 1.0 / 1.1 / 1.2 / 1.3 |
| --- | --- | --- | --- |
| alertmanager.3ai-talk.org | Record observation | Record observation | Record each result |
| argocd.3ai-talk.org | Record observation | Record observation | Record each result |
| frontend.3ai-talk.org | Record observation | Record observation | Record each result |
| grafana.3ai-talk.org | Record observation | Record observation | Record each result |
| keycloak.3ai-talk.org | Record observation | Record observation | Record each result |
| prometheus.3ai-talk.org | Record observation | Record observation | Record each result |
| webhook.3ai-talk.org | Record observation | Record observation | Record each result |

For each hostname also review, manually and read-only:

- Cloudflare redirect rules, hostname-specific exceptions, edge certificate coverage, and HTTP-01/DCV requirements.
- Keycloak external URL and proxy scheme; Argo CD SSO callback; Grafana login; frontend routes; Prometheus, Alertmanager, and webhook authentication.
- Slack slash command, events, and interactive callback URLs, signature validation, and return-thread behavior.
- Whether any legacy callback, monitor, authentication client, or automation still needs TLS 1.0/1.1. A hostname exception blocks a zone-wide rollout until a narrowly scoped policy is agreed.
- TLS probe classifications. `client_unsupported` is a local client limitation, not edge rejection. Only the structured OpenSSL peer `TLSV1_ALERT_PROTOCOL_VERSION` reason is classified as `edge_rejected`. Local low-version/no-protocol/no-cipher errors, context configuration errors, and ambiguous handshake failures cannot prove edge rejection. Successful handshakes report the observed negotiated version, and an unexpected protocol remains inconclusive. Certificate errors, DNS failures, timeouts, and other inconclusive outcomes are not passes. TLS 1.3 enablement is a separate setting from the minimum TLS floor.

Do not use `curl -k`, submit credentials or POST bodies over HTTP, or test sensitive paths. Use only authorized, non-sensitive paths and fixture-only query values for any later manual acceptance checks.

## Change and rollback procedure

F1 requires a separate explicit operator go after F0. Record a sanitized before snapshot and timestamp. Change Always Use HTTPS to On as one operation, then minimum TLS to 1.2 or higher as a separate operation while keeping TLS 1.3 enabled. Do not raise the minimum to 1.3. Do not change HSTS, SSL mode, DNS, tunnel connectors, origin routes/TLS, certificates, WAF, Workers, or application authentication.

Record the exact prior values for both `always_use_https` and `min_tls_version`, the change timestamps, and the operator. If an observed regression occurs, the operator can restore only the setting that caused it to its recorded prior value. Keep sanitized before/after settings and probe output with the bug record; never include credentials or sensitive response data. No automated repair or scheduled drift alert is included. A later read-only drift report should say HTTPS enforcement `on`, `off`, or `unknown`, and minimum TLS as the exact supported value or `unknown`.

After separate approval, F2 should verify all seven HTTP redirects without following them, TLS 1.0/1.1 rejection and TLS 1.2/1.3 negotiation where clients support them, and bounded authorized HTTPS/SSO/Slack flows. Check for redirect loops, unexpected HTTP destinations, and new 4xx/5xx behavior during a defined short observation window. Keep genuine failures visible. Do not claim this prevents historical 502s or establishes whether an attacker accessed M4. Mark the security bug LIVE-VERIFIED only with operator-supplied live evidence.

## References

- [Always Use HTTPS](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/always-use-https/)
- [Encrypt visitor traffic](https://developers.cloudflare.com/ssl/edge-certificates/encrypt-visitor-traffic/)
- [Troubleshoot redirect loops](https://developers.cloudflare.com/ssl/troubleshooting/too-many-redirects/)
- [Minimum TLS version](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/minimum-tls/)
- [Cloudflare zone settings GET API](https://developers.cloudflare.com/api/resources/zones/subresources/settings/methods/get/)
