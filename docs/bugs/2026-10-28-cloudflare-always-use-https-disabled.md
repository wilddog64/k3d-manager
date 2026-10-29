# Bug: Cloudflare HTTPS enforcement and obsolete minimum TLS version

**Filed:** 2026-10-28 (operator request after reviewing Cloudflare configuration inventory)
**Status:** OPEN — operator reports both edge changes applied; seven-host HTTP and TLS enforcement independently verified; final post-TLS authenticated workflow smoke pending
**Priority:** P2 — security hardening, higher priority than routine P3 enhancements; no demonstrated compromise
**Severity:** medium (unenforced HTTP redirect and potentially permitted obsolete TLS protocols; confirm effective edge posture)
**Release:** v1.43.9 security bug (not a new plan slot; fixes should be scheduled on the active release process after preflight approval)
**Branch:** `k3d-manager-v1.43.9`
**Approval:** operator 2026-10-28 requested review/dispatch to Luna; offline implementation authorized, separate explicit go still required for live zone setting changes
**Component:** Cloudflare zone `3ai-talk.org`, edge TLS/redirect settings; affected names: alertmanager, argocd, frontend, grafana, keycloak, prometheus, webhook
**Related:** `docs/howto/public-endpoint-alerts.md`; `docs/howto/tunnel.md`; `docs/plans/v1.43.10-hostinger-public-path-on-node.md`; `docs/plans/v1.45.0-autonomous-incident-investigation.md`

## Symptom / evidence

Operator-supplied Cloudflare account analysis on 2026-10-28 reports **Always Use HTTPS = Off** while seven CNAME records are proxied to a single Cloudflare Tunnel, with SSL mode described as `Full`. A second operator-provided Cloudflare agent report states **Minimum TLS Version = 1.0**, potentially allowing TLS 1.0/1.1 at the visitor-facing edge. Both settings and actual edge behavior have **not** been independently read from the Cloudflare API in this investigation. Verify current configuration before mutation.

Cloudflare documents that Always Use HTTPS redirects requests entering on HTTP to the equivalent HTTPS URL at the edge, applies zone-wide to all hostnames, and is available on Free. This is a defense-in-depth transport policy, **not** a fix for October 502s, a substitute for authentication, or proof of host compromise.

Sources:
- https://developers.cloudflare.com/ssl/edge-certificates/additional-options/always-use-https/
- https://developers.cloudflare.com/ssl/edge-certificates/encrypt-visitor-traffic/
- https://developers.cloudflare.com/ssl/troubleshooting/too-many-redirects/
- https://developers.cloudflare.com/ssl/edge-certificates/additional-options/minimum-tls/

## Risk and scope

Without edge HTTP-to-HTTPS enforcement, clients may initiate an unencrypted request to port 80, even when applications subsequently redirect. This risks exposure of data in an initial HTTP URL/request; actual behavior depends on edge and origin configuration. Main goal: prevent insecure public entry to the seven proxied names, reject obsolete edge TLS negotiations, and verify no authentication or Slack callback flows regress. TLS minimum applies at the visitor-to-Cloudflare edge; origin-side TLS is a separate control.

This has **no established causal connection** to the 7,360 historical HTTP 502s or malicious access to M4. It must not trigger SSH key rotation, WAF country blocking, or any live remediation automatically.

## Proposed fix / staged rollout

### F0. Preflight and immutable evidence (read-only)

1. Read zone settings `always_use_https` and `min_tls_version` through Cloudflare's documented API or dashboard, plus SSL/TLS mode, current redirect rules, HSTS status, edge certificate coverage and any hostname-specific exceptions. Collect timestamp and sanitized evidence; never store bearer/API tokens.
2. Read-only test `http://` and `https://` for all seven hostnames, with **redirect following disabled**, recording response status and `Location` (without secrets). Do not submit credentials or POST bodies over HTTP. Check that 401, 302, 200 behavior on direct HTTPS remains baseline.
3. Review Keycloak external URL/proxy scheme, ArgoCD SSO callback, Grafana login, frontend flows, Prometheus/Alertmanager/Webhook auth, Slack relay callback URLs, HTTP-01/DCV if relevant, and existing Cloudflare Redirect Rules for loops or forced HTTPS-to-HTTP redirects.
4. Inspect permitted TLS versions on each of seven HTTPS hostnames using a read-only client that forces TLS 1.0, 1.1, 1.2 and 1.3 (where supported); record handshake success/failure, negotiated protocol and certificate validity without authentication tokens. Separate local OpenSSL/client limitations from edge refusal.
5. Check whether any legacy Slack/Cloudflare Worker callbacks, monitoring, authentication clients, or automation require TLS 1.0/1.1. Modern clients should support TLS 1.2+. Document any compatibility exception before rollout.
6. If an exception is necessary for a hostname, stop zone-wide rollout and propose a narrowly scoped policy instead; do not silently exclude a service.

### F1. Controlled edge change (separate operator approval)

- Prefer Cloudflare `Always Use HTTPS = On` for the entire zone **only after F0 passes**. Use dashboard or documented API with least-privilege credentials; do not write tokens into shell history, command arguments, logs, Git, CI or agent output.
- After explicit operator approval, set Cloudflare minimum TLS version to **1.2** as a separate controlled operation, keeping TLS 1.3 enabled. Do not raise the minimum to TLS 1.3 without separate compatibility review.
- Record prior values and rollback paths for each setting (`always_use_https`, `min_tls_version`); restore only the setting that caused an observed regression, under operator control.
- Do **not** change SSL/TLS mode, HSTS, DNS, tunnel connectors, origin routes, certificates, application authentication, or Worker settings as part of this change.
- No automatic remediation or unattended agent action against account settings.

### F2. Acceptance / live validation

- For each of seven names, plain HTTP GET with redirects disabled receives edge HTTP 301/308 to exactly the HTTPS equivalent, preserves safe path/query in test fixtures, and does not expose a response body from origin. Use non-sensitive paths and fixture-only query values.
- Explicit protocol checks show TLS 1.0 and TLS 1.1 handshakes rejected, while TLS 1.2 and TLS 1.3 negotiate successfully when the client and edge support them. Test on all seven names and explain any client-side unsupported protocol case instead of claiming a pass.
- Direct HTTPS responses stay within preflight expectations; tests explicitly distinguish edge redirect `http -> https` from auth redirects `https -> Keycloak`.
- Bounded browser smoke validates Keycloak login + return, ArgoCD/Grafana SSO, frontend, and authenticated webhook behavior without sending real tokens over HTTP; use authorized test paths only.
- Ensure Slack slash/events/interactive delivery paths remain functional at HTTPS URLs, including signature validation and return-thread behavior; document genuine failures rather than masking them behind an accepted 302.
- Verify no new redirect loop, no unexpected `Location: http://`, no new 4xx/5xx regression during a short defined observation window. Existing 502 incident analysis remains separate.
- Store before/after configuration, sanitized curl outputs, timestamps and operator confirmation with this bug.

### F3. Drift detection (separate, scoped implementation)

Read-only periodic Cloudflare configuration posture check may alert when Always Use HTTPS reverts to Off or minimum TLS falls below 1.2; do not automatically change it. Reuse Hermes security-posture patterns if available. Avoid requiring a new credential solely for this task unless a documented minimally scoped API exists and the operator approves it.

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
  - id: M6
    text: Minimum edge TLS is confirmed at 1.2 or higher, with TLS 1.0/1.1 rejected and TLS 1.2 supported on all seven names; TLS 1.3 remains enabled where supported.
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
  - id: N6
    text: Do not raise the minimum to TLS 1.3, change origin-side TLS, or label a client unsupported-protocol error as proof of an edge rejection.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M4, N1, N2, N3]
    text: Documented preflight checklist, sanitized baselines, rollback plan, and fake-response tests for redirect chains and error handling.
  - id: E2
    kind: live
    proves: [M2, M3, M6, N4, N6]
    text: After operator-approved changes, seven HTTP redirect checks, forced TLS 1.0/1.1/1.2/1.3 connection tests, and authorized HTTPS/SSO/Slack flows are observed with timestamps. Distinguish client capability from edge enforcement.
  - id: E3
    kind: offline
    proves: [M5]
    text: Configuration posture check reports HTTPS enforcement on/off/unknown and TLS minimum as exact version/unknown, handles API errors and never attempts a write.
interface:
  - Cloudflare documented always_use_https and min_tls_version zone settings
  - public endpoint and SSO smoke checks
  - Hermes read-only security posture/drift reporting
```

## Definition of Done

- [ ] F0 verified with captured HTTPS and TLS minimum settings, 7-host HTTP/HTTPS/TLS baseline and callback/redirect compatibility assessment.
- [ ] Explicit approval received for the external setting change.
- [ ] F1 applied with rollback documented and retained before/after record.
- [ ] F2 real-world validation passing for HTTP redirects, TLS protocol enforcement and authenticated workflows; failures kept open with observed evidence.
- [ ] F3 drift check planned or delivered separately with tests and no auto-repair.
- [ ] Mark LIVE-VERIFIED only after E2; update bug status accordingly.

## What NOT to Do

- Do not file this as a new v1.43.9 feature plan that would consume its capped plan slots.
- Do not create PR, write to main, skip hooks or perform an external configuration change from this filing.
- Do not turn on HSTS in the same change; its browser persistence complicates rollback.
- Do not change Cloudflare minimum TLS to 1.3 or confuse edge TLS with origin TLS.
- Do not misclassify normal SSO 302 or expected unauthenticated 401 as proof of a working end-to-end application.

## Authorized Luna offline deliverable — 2026-10-28

Operator selected this P2 for Luna. Task cloudflare-https-tls-preflight-luna,
modelgpt-6-luna. Implement bounded read-only posture/preflight helper and operator
guidance for F0/F3; F1 account changes and F2 live acceptance remain pending.
Do not claim the security bug fixed by tooling alone. No new Make target,
periodic scheduler, Hermes automation, dashboard, account credential or applymode.

### Files

- `Makefile` — operator-requested read-only preflight shortcut, 2026-10-28
- `bin/k3dm-cloudflare-posture`
- `scripts/tests/bin/test_cloudflare_posture.py`
- `docs/howto/cloudflare-https-tls-preflight.md`
- `docs/tests/cloudflare-posture.md`
- `CHANGELOG.md`

## Files

- `bin/k3dm-cloudflare-posture`
- `scripts/tests/bin/test_cloudflare_posture.py`
- `docs/howto/cloudflare-https-tls-preflight.md`
- `docs/tests/cloudflare-posture.md`
- `CHANGELOG.md`

## Rules — current bounded task

- Pythonstdlib helper default/--dry-run prints plan without environmentcredential,
  network, process or account access. Explicit --check is read-only; no --apply,
  PATCH/POST/PUT/DELETE, mutationcommands, tokenretrieval/Keychain or tokenCLIarg.
- Read fixed documented Cloudflare API GET settings paths for validated32hex
  zoneid (always_use_https, min_tls_version, ssl, security_header/HSTS, tls_1_3)
  with existing operator CLOUDFLARE_API_TOKEN onlyinmemory. Missingcredentials,
  HTTP/APIerrors/malformedresults reportunknown, neverhealthy. Tokenneverargv,
  plainHTTP, errorbody/log/output. AuthAPIredirects/proxies mustnotleakBearer;
  denyredirects, fixedAPIhost/path, boundedtime/response, normalcertvalidation.
- Optional --settings-file supports existing operator-supplied sanitized API
  snapshot, labeledsnapshot/notequaltocurrentAPIread, no credentialneeded. Accept
  documented setting shapes, output onlyknownsanitizedfields, unknowninvalidvalues.
  Existing accountreport's Off/TLS1.0 claims are unverified until actualpreflight.
- Fixed sevenhostnames alertmanager/argocd/frontend/grafana/keycloak/prometheus/
  webhook.3ai-talk.org. Explicitcheck unauthenticatedHTTP/HTTPS GET, no redirects
  followed, tokens/bodies/login submitted or rawresponsebodiesrecorded. Record
  status/sanitizedLocation to distinguish transport/authredirects. Probes always
  credentialfree; do not use -k or sendAuthorization outsidefixedCFAPI.
- ForceTLS1.0/1.1/1.2/1.3 perhostname, boundedtimeouts, validatedcert/SNI. Distinguish
  actualedgeprotocolrejection fromlocalclient/cipherunsupported, certificateerror,
  DNS/timeout/otherinconclusive; unknown/unsupported is not a pass. Tests use
  injected/mocknetwork/SSL/process only. No realendpointprobe in worker.
- No setting shouldbe securebyabsence. Read-onlyposture reports enforcementon/
  off/unknown and exactTLSminimum/unknown. No conclusion of end-to-endlogin from
  HTTPS200/302/401 alone; keep baseline observations separate fromF0complete.
- Guideprovides sevenhostbaseline, manualredirectrules/certcoverage/SSO/Slack/
  hostnameexceptions checklist, existing least-privilege credentialuse, missing
  telemetrylimitations, before/afterandrollback retaining previousvalues for
  eachsetting, operatorapprovalbetweenpreflightandtwo separatezonechanges,
  noHSTS/SSLmode/DNS/tunnel/authsideeffects. No credentialprovisioning required
  justfortask; snapshotmode/workflow handlesabsence. No automateddriftalerting.
- Document public officialsources cited above and API GET reference:
  https://developers.cloudflare.com/api/resources/zones/subresources/settings/methods/get/
  Cloudflare confirmsGET acceptsZoneSettingsRead; do not requireZoneSettingsWrite
  forreadonlyhelper. TLSfloor andTLS1.3enablement are distinct settings.
- Fixtures provezeroaccessdryrun, knownshapeon/off/unknown, auth/API/malformed
  failure, noBearerleaks/redirectfollow/mutations, each7host protocolmatrix,
  clientunsupportedvsedgereject, baseline/authredirectdistinction, timeoutbounds.
  No livecalls in tests, no pipinstall/network/dependencies required. Fakevalues
  musttestrealhelperbehavior, nottoyconstantassertions.
- Only Files above; no spec/memory/statusedits, gitadd/commit/push/PR, newplan,
  livehost/Keychain/cloud/provider/test-run/clusteraccess. Coordinatorownsreview,
  stagedgates/landing/push and operatorlivechecks. Keepnewfunctions<=8ifs,
  preserveDO_NOT_REMOVE, reportlegacyconflictsinstead ofrelaxinggates.
- Gates: full newpytest suite, Ruff (/private/tmp/k3dm-review-tools/bin/ruff check
  --no-cache), Python syntax, helperdryrun/help with noenvaccess, docslinks,
  gitdiffcheck. E1/E3offline only; E2/livezoneposture remainsnotverified.

## 2026-10-28 Luna implementation review

Luna task `cloudflare-https-tls-preflight-luna` rework 2 landed as
`2e0be3f6`. Coordinator independently ran 169 offline pytest cases, Ruff, direct
executable help/dry-run and required lint/audit/checkpoint hooks; landing reran
the same gates successfully. No real API, public endpoint, credential lookup,
zone mutation or scheduled automation was used. The helper is read-only; this
commit is tooling evidence, not a fix to the actual edge configuration.

Current configuration, redirect-rule/certificate/SSO/Slack compatibility, F1
operator go and F2 live acceptance remain pending. Full review output is in
[the batch review](../issues/2026-10-28-two-new-p2-luna-batch.md). No PR created;
Claude owns PR creation.

## Operator preflight and Make shortcut follow-up

Operator report timestamp2026-10-28T17:36:46.131214+00:00: all seven
TLS1.2/1.3 handshakes negotiated with valid certificates; TLS1.0/1.1 are
client_unsupported (not proof of edge rejection). No HTTP root probe upgraded
to HTTPS: ArgoCD/frontend200, Alertmanager/Prometheus/webhook401, Grafana/
Keycloak302 same-scheme destinations. All API settings null with credential
or valid zone ID unavailable; supplied ID is valid32hex, so helper had no
nonempty API token. F0 remains incomplete; no live change is authorized by
this partial report. Redirect rules/certificate coverage/SSO/Slack and current
zone values still need review. TLS deprecation warnings came from intentional
legacy-version probes; no runtime warning filters added.

Operator explicitly requested a Make target. Scope extends to Makefile plus
existing preflight howto: cloudflare-preflight accepts ZONE_ID and follows
existing DRY_RUN=1 convention. No helper, credential, scheduling, API-write or
UI changes. Exact operator output and wrapper verification are recorded in
`docs/issues/2026-10-28-cloudflare-preflight-operator-report.md`.

## Latest saved operator report: 18:16:57Z

Read actual /tmp/k3dm-cloudflare-preflight.json successfully:7hosts, valid
TLS1.2/1.3 on all,0/7HTTP-to-HTTPS upgrades, legacyTLSclient_unsupported, API
settingsallunknown/no credential. Deprecation warnings reflect intentional
legacy probes, not edge rejection. Fullactualoutput in existingoperatorreport
issue. F0partial unchanged; nextreadcurrentzonevalues/rules viaCloudflareAI or
dashboard. No additional probe rerun, warning suppression or live change.

## Operator Cloudflare AI report review

Screenshots reportFull/AlwaysHTTPSOff/minTLS1.0/TLS1.3On/rewritesOn andall7
proxiedTunnelrecords. This suppliesoperator-reportedsettings, not an independent
coordinatorAPIread. HSTS andactualruleinventory notshown. MissingTLSanalytics
doesnotprovelegacyclientsabsent; TunnelconnectiondoesnotprovevisitorTLS
compatibility orabsenceoforiginredirectloops. Officialdocs andremaining
review inexistingoperatorreportissue. F0partial/no F1writego inferred.
Recommendedsequence afteractualrule/compatcheck: approveHTTPSonly, validate,
then separatelyapproveTLS1.2; keepFull/TLS1.3/HSTS/DNS/tunnel/auth unchanged.

## First live setting change observed

Operator Cloudflare AI reports Always Use HTTPS enabled 2026-10-28T22:00:41Z.
Independent public probes 22:02:51Z: all seven HTTP roots301 to same-hostHTTPS;
direct HTTPS matches baseline (200/302/401 by service). Full actual output in
existing operator-report issue. Actual SSO/Slack and redirect-chain acceptance
pending. MinimumTLS still1.0 per operator report; bug remainsOPEN. No coordinator
credential read or settings write.

## Operator browser smoke results

Frontend SSO successful per operator report; authenticated Developer page shown.
Grafana and ArgoCD existing authenticated sessions remain accessible. These
are not fresh login/expiry tests for those services. Exact interpretation and
remaining Slack/TLS acceptance recorded in the operator-report issue. No
session regression inferred or live settings changed. Bug remainsOPEN.

## HTTPS application smoke acceptance

Operator fresh Grafana logout/login succeeded; fresh Slack make fix-list
job02be2e0b queued/started/succeeded with response. FrontendSSO alreadypass;
ArgoCD existingaccesspass. FirstHTTPSchange smokeaccepted; separateTLS1.2
change/postcheckpending, latestmin1.0. FullverbatimSlackscreenshottext in
operatorreportissue. NoCloudflarewritebycoordinator; bugOPEN.

## Minimum TLS1.2 applied; public protocol enforcement PASS

OperatorCF_AI tableconfirmsminimum1.0to1.2only, TLS1.3On/HTTPSOn/Full unchanged.
Reported22:00:41ZchangetimerepeatsearlierHTTPSreport, notindependentlyconfirmed.
Independent00:05:40ZOct29(17:05PDTOct28)7hosts: HTTP301samehostHTTPS, HTTPS
baselineunchanged, pinnedTLS1.2/1.3validcert/pass andTLS1.0/1.1explicit
TLSV1_ALERT_PROTOCOL_VERSION rejection. Temporarylegacyclientciphercompat
wasprobe-localonly; no system/helper/appchange. FullactualJSON/method in
existingoperatorreportissue. AI526claimcorrected: protocolhandshakealert.
M2/M6PASS; finalpostsecondchangefrontendSSO+freshSlackresponsependingM3/E2,
so bugOPEN. No coordinatorCloudflarecredential/write or screenshotexport.
