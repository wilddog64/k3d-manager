# Bug: Cloudflare Always Use HTTPS disabled for 3ai-talk.org public entrypoints

**Filed:** 2026-10-28 (operator request after reviewing Cloudflare configuration inventory)
**Status:** OPEN — operator-approved filing only; edge configuration has not been changed or live-verified
**Priority:** P2 — security hardening, higher priority than routine P3 enhancements; no demonstrated compromise
**Severity:** medium (cleartext HTTP entry possible before redirect; actual exposure and HTTP handling require verification)
**Release:** v1.43.9 security bug (not a new plan slot; fixes should be scheduled on the active release process after preflight approval)
**Branch:** `k3d-manager-v1.43.9`
**Approval:** operator requested higher-priority plan/bug filing; separate explicit go required for changing Cloudflare zone settings
**Component:** Cloudflare zone `3ai-talk.org`, edge TLS/redirect settings; affected names: alertmanager, argocd, frontend, grafana, keycloak, prometheus, webhook
**Related:** `docs/howto/public-endpoint-alerts.md`; `docs/howto/tunnel.md`; `docs/plans/v1.43.10-hostinger-public-path-on-node.md`; `docs/plans/v2.0.0-autonomous-incident-investigation.md`

## Symptom / evidence

Operator-supplied Cloudflare account analysis on 2026-10-28 reports **Always Use HTTPS = Off** while seven CNAME records are proxied to a single Cloudflare Tunnel, with SSL mode described as `Full`. The setting and actual edge behavior have **not** been independently read from the Cloudflare API in this investigation. Verify current configuration before mutation.

Cloudflare documents that Always Use HTTPS redirects requests entering on HTTP to the equivalent HTTPS URL at the edge, applies zone-wide to all hostnames, and is available on Free. This is a defense-in-depth transport policy, **not** a fix for October 502s, a substitute for authentication, or proof of host compromise.

Sources:
- https://developers.cloudflare.com/ssl/edge-certificates/additional-options/always-use-https/
- https://developers.cloudflare.com/ssl/edge-certificates/encrypt-visitor-traffic/
- https://developers.cloudflare.com/ssl/troubleshooting/too-many-redirects/

## Risk and scope

Without edge HTTP-to-HTTPS enforcement, clients may initiate an unencrypted request to port 80, even when applications subsequently redirect. This risks exposure of data in an initial HTTP URL/request; actual behavior depends on edge and origin configuration. Main goal: prevent insecure public entry to the seven proxied names and verify no authentication or Slack callback flows regress.

This has **no established causal connection** to the 7,360 historical HTTP 502s or malicious access to M4. It must not trigger SSH key rotation, WAF country blocking, or any live remediation automatically.

## Proposed fix / staged rollout

### F0. Preflight and immutable evidence (read-only)

1. Read zone setting `always_use_https` through Cloudflare's documented API or dashboard, plus SSL/TLS mode, current redirect rules, HSTS status, edge certificate coverage and any hostname-specific exceptions. Collect timestamp and sanitized evidence; never store bearer/API tokens.
2. Read-only test `http://` and `https://` for all seven hostnames, with **redirect following disabled**, recording response status and `Location` (without secrets). Do not submit credentials or POST bodies over HTTP. Check that 401, 302, 200 behavior on direct HTTPS remains baseline.
3. Review Keycloak external URL/proxy scheme, ArgoCD SSO callback, Grafana login, frontend flows, Prometheus/Alertmanager/Webhook auth, Slack relay callback URLs, HTTP-01/DCV if relevant, and existing Cloudflare Redirect Rules for loops or forced HTTPS-to-HTTP redirects.
4. If an exception is necessary for a hostname, stop zone-wide rollout and propose a narrowly scoped redirect rule instead; do not silently exclude a service.

### F1. Controlled edge change (separate operator approval)

- Prefer Cloudflare `Always Use HTTPS = On` for the entire zone **only after F0 passes**. Use dashboard or documented API with least-privilege credentials; do not write tokens into shell history, command arguments, logs, Git, CI or agent output.
- Record prior value and exact rollback, `Always Use HTTPS = Off`, under operator control.
- Do **not** change SSL/TLS mode, HSTS, DNS, tunnel connectors, origin routes, certificates, application authentication, or Worker settings as part of this change.
- No automatic remediation or unattended agent action against account settings.

### F2. Acceptance / live validation

- For each of seven names, plain HTTP GET with redirects disabled receives edge HTTP 301/308 to exactly the HTTPS equivalent, preserves safe path/query in test fixtures, and does not expose a response body from origin. Use non-sensitive paths and fixture-only query values.
- Direct HTTPS responses stay within preflight expectations; tests explicitly distinguish edge redirect `http -> https` from auth redirects `https -> Keycloak`.
- Bounded browser smoke validates Keycloak login + return, ArgoCD/Grafana SSO, frontend, and authenticated webhook behavior without sending real tokens over HTTP; use authorized test paths only.
- Ensure Slack slash/events/interactive delivery paths remain functional at HTTPS URLs, including signature validation and return-thread behavior; document genuine failures rather than masking them behind an accepted 302.
- Verify no new redirect loop, no unexpected `Location: http://`, no new 4xx/5xx regression during a short defined observation window. Existing 502 incident analysis remains separate.
- Store before/after configuration, sanitized curl outputs, timestamps and operator confirmation with this bug.

### F3. Drift detection (separate, scoped implementation)

Read-only periodic Cloudflare configuration posture check may alert when Always Use HTTPS reverts to Off; do not automatically change it. Reuse Hermes security-posture patterns if available. Avoid requiring a new credential solely for this task unless a documented minimally scoped API exists and the operator approves it.

## Acceptance

```yaml
must:
  - id: M1
    text: Current zone setting and redirect interactions are independently confirmed before any write.
  - id: M2
    text: All seven proxied public hostnames redirect plain HTTP to HTTPS at the edge without credential-bearing HTTP test requests.
  - id: M3
    text: Keycloak SSO and authenticated public workflows remain functional; HTTPS status baselines are preserved.
  - id: M4
    text: The operator receives a documented rollback and sanitized before/after evidence.
  - id: M5
    text: A read-only drift check is specified and must show missing/unavailable telemetry as unknown.
must_not:
  - id: N1
    text: No live zone setting change without separate explicit operator go.
  - id: N2
    text: Do not alter HSTS, SSL mode, DNS, Cloudflare Tunnel, WAF or application auth as a side effect.
  - id: N3
    text: No real credential, token, sensitive path, or personal data transmitted over plain HTTP or committed to Git.
  - id: N4
    text: No redirect loop or regression in Slack callbacks, Keycloak login or public HTTPS probes.
  - id: N5
    text: Do not claim this prevents 502s or establishes that no attacker accessed M4.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M4, N1, N2, N3]
    text: Documented preflight checklist, sanitized baselines, rollback plan, and fake-response tests for redirect chains and error handling.
  - id: E2
    kind: live
    proves: [M2, M3, N4]
    text: After operator-approved change, seven HTTP redirect checks and authorized HTTPS/SSO/Slack flows are observed and recorded with timestamps.
  - id: E3
    kind: offline
    proves: [M5]
    text: Configuration posture check reports on/off/unknown, handles API errors and never attempts a write.
interface:
  - Cloudflare documented always_use_https zone setting
  - public endpoint and SSO smoke checks
  - Hermes read-only security posture/drift reporting
```

## Definition of Done

- [ ] F0 verified with captured settings, 7-host baseline and callback/redirect compatibility assessment.
- [ ] Explicit approval received for the external setting change.
- [ ] F1 applied with rollback documented and retained before/after record.
- [ ] F2 real-world validation passing; failures kept open with observed evidence.
- [ ] F3 drift check planned or delivered separately with tests and no auto-repair.
- [ ] Mark LIVE-VERIFIED only after E2; update bug status accordingly.

## What NOT to Do

- Do not file this as a new v1.43.9 feature plan that would consume its capped plan slots.
- Do not create PR, write to main, skip hooks or perform an external configuration change from this filing.
- Do not turn on HSTS in the same change; its browser persistence complicates rollback.
- Do not misclassify normal SSO 302 or expected unauthenticated 401 as proof of a working end-to-end application.
