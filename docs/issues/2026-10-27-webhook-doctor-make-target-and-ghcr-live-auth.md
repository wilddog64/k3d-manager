# Webhook doctor Make target and operator GHCR live-auth result

## Requested Make entrypoint

No webhook-doctor Make target existed. Operator asked for one while a CVE
scan ran in tmux. Implemented47b4d740 (normal hooks):

- `make webhook-doctor` calls the existing doctor --check, read-only.
- `make webhook-doctor DRY_RUN=1` calls --dry-run (probe plan only).
- Target is PHONY and listed in make help; howto/test guide updated.
- No restart, scan, credential or extra dependency is wired to the wrapper.

Actual verification:

```text
$ make -n webhook-doctor
bin/k3dm-webhook-doctor --check
$ make -n webhook-doctor DRY_RUN=1
bin/k3dm-webhook-doctor --dry-run
$ make webhook-doctor DRY_RUN=1
{"mode": "dry-run", "probes": ["launchd job state and last exit code", "webhook process PID", "configured webhook TCP listener (default 7443)", "bounded redacted log summary", "reader-authenticated loopback /api/v1/health?quick=1"], "recovery": "No recovery is performed. Operator may run make restart-webhook once only when local evidence warrants it; it also restarts cloud-bridge.", "timestamp_utc": "2026-10-27T22:56:38.842360+00:00"}
$ make help (checked target entry)
make help: webhook-doctor listed
$ bats scripts/tests/bin/restart_webhook.bats
1..5
ok 1 restart-webhook reloads the plist with bootout then bootstrap, never kickstarting the webhook
ok 2 restart-webhook continues to bootstrap when bootout reports the job is not loaded
ok 3 restart-webhook still restarts the cloud bridge
ok 4 restart-webhook retries bootstrap twice then reports success
ok 5 restart-webhook fails after five bootstrap attempts and skips cloud bridge
```

Thin wrapper adds no shell function/file: ShellCheck not applicable. Normal
staged lint/audit, doc links and checkpoint hooks passed. No new mirror test
was added; actual Make expansion, real no-I/O plan and existing adjacent
restart suite were exercised. Existing doctor35 Python/5BATS results remain
in the preceding health-budget issue; Python behavior unchanged here.

## Operator scanner command completed

Full supplied output:

```text
make app-cve-scan
./scripts/k3d-manager app_cve_scan_trigger
running under bash version 5.3.20(1)-release
INFO: [observability] triggering app-cve-scan as job/app-cve-scan-manual-1793141593
job.batch/app-cve-scan-manual-1793141593 created
INFO: [observability] waiting up to 600s for job/app-cve-scan-manual-1793141593
INFO: [observability] job/app-cve-scan-manual-1793141593 completed
app-cve-scan-manual-1793141593   1     <none>
INFO: [observability] most recent promotion requests:
cve-remediation-qrwcd   2026-10-16T08:01:38Z
cve-remediation-ldcpd   2026-10-19T10:55:21Z
cve-remediation-26nt6   2026-10-20T08:01:23Z
cve-remediation-594kd   2026-10-21T08:01:34Z
cve-remediation-fck8q   2026-10-22T08:02:07Z
cve-remediation-xxx4r   2026-10-22T19:11:48Z
```

These are historical promotion request records, not evidence of a new
promotion by this run. No second scan was started by coordinator.

## Actual new-job log, read-only

Command: kubectl --context k3d-k3d-cluster -n platform-ops logs
job/app-cve-scan-manual-1793141593 -c app-cve-scanner --tail=200

```text
[app-cve-scan] STAGE shopping-cart-basket: deployed image ghcr.io/wilddog64/shopping-cart-basket:sha-1404c74800bdb8f4cfdc90331790052c212773f6 has no HIGH/CRITICAL findings
[app-cve-scan] STAGE shopping-cart-frontend: deployed image ghcr.io/wilddog64/shopping-cart-frontend:<none> has no HIGH/CRITICAL findings
[app-cve-scan] STAGE shopping-cart-order: deployed image ghcr.io/wilddog64/shopping-cart-order:<none> has no HIGH/CRITICAL findings
[app-cve-scan] STAGE shopping-cart-payment: deployed image ghcr.io/wilddog64/shopping-cart-payment:<none> has no HIGH/CRITICAL findings
[app-cve-scan] STAGE shopping-cart-product-catalog: failed to resolve immutable sha-* candidate for ghcr.io/wilddog64/shopping-cart-product-catalog; reason=auth — promotion skipped
[notify] Email skipped: SENDGRID_API_KEY or NOTIFICATION_EMAIL not set
[notify] PagerDuty skipped: PAGERDUTY_ROUTING_KEY not set
[app-cve-scan] Done
```

This run exercised the new auth diagnosis and deliberately skipped product
catalog promotion. Successful Job exit does not mean private-package access
or remediation succeeded. Optional email/PagerDuty notice delivery was skipped
for missing config, so end-to-end notice delivery is not verified. Other
report image tags include <none>; no independent claim about those workloads
or unrelated parser fix was made.

## Published resolution metric

Read through hub API service proxy (GET only), filtering product-catalog:

```text
k3dm_app_cve_candidate_resolution{instance="shopping-cart-product-catalog",job="k3dm-app-cve-scan",reason="auth",service="shopping-cart-product-catalog"} 1
```

This confirms the per-service auth-resolution metric is published. It does
not establish a later auth-to-ok transition or successful promotion.

## Dedicated local PAT checked without disclosure

Keychain lookup metadata only:

```json
{"service": "platform-ops-app-rebuild", "lookup_exit": 0, "credential_present": true}
```

PAT was held only in process memory and sent only to its intended GHCR/GitHub
HTTPS endpoints, with proxy routes and redirects disabled. Token/Authorization
never appeared in process arguments or outputs. No cluster Secret was read
or decoded. No value, raw response body, profile or full permission list was
logged. GHCR token request result:

```json
{"registry_token_http_status": 403, "pull_token_present": false}
```

No manifest request was made because no pull token was returned. A subsequent
read-only GitHub /user authentication check of the same dedicated PAT:

```json
{"github_auth_http_status": 401}
```

The existing dedicated PAT is rejected by GitHub/GHCR. This is not explained
by the prior Keychain lock, since retrieval now succeeds. We did not establish
expired versus revoked versus another invalid-credential cause. Resyncing
this rejected local credential alone would not validate package access.

Next single operator action: replace/regenerate the dedicated PAT in GitHub
and update the existing Keychain item platform-ops-app-rebuild / account k3dm
through the operator's credential UI; never paste its value into chat. For
GHCR pulls GitHub documents a classic PAT with read:packages and applicable
package access:
[GitHub Container registry authentication](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-with-a-personal-access-token-classic).
Preserve other permissions actually required by the existing dedicated
rebuild workflow; do not substitute the operator's broad gh token. The
coordinator did not generate, store, rotate or modify access to a credential.
After operator confirms storage, recheck authentication before syncing the
cluster Secret and rerunning the scan, one step at a time.

GHCR live result is PARTIAL: deployed auth classification/metric verified;
credential remediation, successful candidate resolution/promotion and
notification delivery remain unverified. Canonical bug remains VERIFIED
offline with these live observations, not a full LIVE-VERIFIED closeout.

## Credential selection clarification — existing Dependabot App

Operator asked about regenerating k3dm-dependabot-merger. Repository source
`docs/bugs/2026-10-17-dependabot-automerge-github-token-skips-main-ci.md`
explicitly identifies that name as a GitHub App installed on the five
shopping-cart repos, with private-key-based automation and live merge
evidence attributed to app/k3dm-dependabot-merger. This source does not
identify it as the scanner's dedicated PAT.

No App key/client credential was generated, regenerated, revoked or modified.
The next scanner credential action remains operator-owned: use Personal
access tokens (classic), create/regenerate the dedicated scanner token with
read:packages/package access and required existing rebuild permissions, then
update Keychain platform-ops-app-rebuild / account k3dm. No value in chat.
No unrelated Dependabot App credentials need to change for this step.

Automatic approval review rejected archiving/pushing the user-supplied
credential-management screenshot because its full contents were not verified
non-sensitive and artifact export was not authorized. That image was omitted;
no screenshot copy or indirect export was attempted after rejection. Only
identification already supported by the existing repository document is
recorded here. This safer evidence-only alternative requires no credential
or artifact approval. No credential rotation has been completed.

## Native Keychain update command verified, operator execution pending

User clarified the intended PAT entry has the already-documented scanner
service name platform-ops-app-rebuild and asked for an update command. No
credential-page screenshot, expiry, token value or additional scope metadata
was archived. The prior artifact-export rejection remains respected.

Read-only `security help add-generic-password` confirms -U updates an existing
item, and its final help line says:

```text
Specify -w as the last option to be prompted.
```

Apple keychain_add.c handles a missing final -w argument by prompting for
password data and confirmation through getpass. Provided command:

```bash
/usr/bin/security add-generic-password -U \
  -s platform-ops-app-rebuild -a k3dm -w
```

No value follows -w: PAT entry/confirmation occurs at the native hidden
prompts, keeping it out of history and argv. This updates the exact scanner
service/account rather than a Dependabot App key. The coordinator did not
execute add-generic-password, capture a new token, change an ACL, sync a
Secret or trigger a scan. Guidance is concrete and verified from local help
and primary Apple source; actual storage/authentication remain pending
operator confirmation. No code tests needed for this documentation update.

[Apple source](https://github.com/apple-oss-distributions/Security/blob/main/SecurityTool/macOS/keychain_add.c).

## Operator replacement stored — authentication passes; rotation recorded

Operator confirmed the new PAT is stored and has90-day validity, then
explicitly requested a note to rotate before expiry. No token value was
provided in chat or recorded. Read-only in-memory checks of the updated
Keychain item returned:

```json
{"github_auth_http_status": 200, "read_packages_scope": false, "owner_matches": true}
{"registry_token_http_status": 200, "pull_token_present": true}
{"latest_manifest_http_status": 200, "digest_present": true}
```

The scope boolean checks literal read:packages membership in the response
header, not effective download permission; a write:packages grant includes
download ability per GitHub Container registry docs. The successful actual
GHCR token and manifest requests establish working package access. No scope
list, profile or token value was output, and no invalid-credential claim
remains for this new local value.

At the operator's explicit rotation-note request, queried only the expiration
header from the authenticated GitHub response:

```json
{"github_auth_http_status": 200, "token_expiration_header": "2027-01-26 01:55:50 UTC"}
```

Verified conversion:

```text
expiry_local=2027-01-25T17:55:50-08:00
rotate_by_local_date=2027-01-18
```

Exact expiry and seven-day-early rotation target saved in
`docs/howto/app-cve-scan-auth.md` and memory-bank. This is an explicitly
authorized textual rotation note, not a credential-page screenshot export
or a scheduled notification. No App keys or lock settings were changed.

Next single operator step: sync the dedicated existing Secret from Keychain
with `./scripts/k3d-manager argocd_sync_app_rebuild_secret platform-ops`
while the hub context is selected. Review output before one rescan. The
coordinator has not synced the cluster Secret or created another scan Job.
Local authentication passing does not prove the running cluster uses the
replacement yet, or that candidate selection/promotion succeeds.
