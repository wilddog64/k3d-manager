# Two new P2 bugs — scope, source evidence and Luna review

Operator selected currentCloudflareHTTPS/TLS andoffline test-all P2bugs.
Concurrent alreadycommittedd7b74077/d8565087bugfilings preserved; rootcurrent
branch clean. Separate boundednativegpt-6-luna worktrees: CFreadonlytooling/
preflightguidance(noaccountwrite) andactualofflineguard/E2Efixturerepair.
No newplan slots or user-visible dashboard/table changes. Existing investigation
verificationfix has passed bothPushgateway andPrometheus data assertions;
finalGrafanarowvisualcheck remainspending whilethisnewwork proceeds.

## Prior fix Prometheus source verification — PASS

Actual read-only dashboarddatasource result:
```json
{
  "status": "success",
  "data": {
    "resultType": "vector",
    "result": [
      {
        "metric": {
          "__name__": "k3dm_bug_info",
          "branch": "k3d-manager-v1.43.9",
          "bug": "2026-10-26-webhook-unresponsive-minimal-diagnosis-recovery",
          "filed": "2026-10-26",
          "fix_sha": "-",
          "fixed_in": "v1.43.9",
          "job": "k3dm-bug-open",
          "live_evidence": "ok",
          "live_verified": "true",
          "live_verified_at": "2026-10-28",
          "priority": "P2",
          "release": "v1.43.9",
          "release_order": "9998.9956.9990 v1.43.9",
          "repo": "k3d-manager",
          "sort_key": "9998.9956.9990 v1.43.9 P2 3 2026-10-26 2026-10-26-webhook-unresponsive-minimal-diagnosis-recovery",
          "status": "fixed",
          "title": "Incident: webhook unresponsive while operator offsite \u2014 minimal diagnosis and controlled recovery",
          "verified": "true",
          "verified_at": "2026-10-28",
          "verified_sha": "7ea1032f"
        },
        "value": [
          1793203359.586,
          "-2"
        ]
      }
    ]
  }
}
```
Onecurrentincidentseriesfixed/verifiedtrue/livetrue/evidenceok/date2026-10-28/
record7ea1032f/fixSHA'-'/value-2. No manualpublisherfromcoordinator.

## Recorded offline source, read-only, not rerun

Actual Prometheus queries:
```json
{
  "failures": {
    "status": "success",
    "data": {
      "resultType": "vector",
      "result": [
        {
          "metric": {
            "__name__": "k3dm_test_failure",
            "case": "130",
            "instance": "test-all-local",
            "job": "k3dm-tests",
            "name": "grep-q guard: no non-allowlisted pipeline retains -q",
            "reason": "`[ \"$status\" -eq 1 ]' failed",
            "suite": "bats",
            "target": "test-all"
          },
          "value": [
            1793203528.672,
            "1"
          ]
        },
        {
          "metric": {
            "__name__": "k3dm_test_failure",
            "case": "1015",
            "instance": "test-all-local",
            "job": "k3dm-tests",
            "name": "dispatch refuses and never falls back locally when the lock is held",
            "reason": "`[[ \"$output\" == *\"busy\"* ]]' failed",
            "suite": "bats",
            "target": "test-all"
          },
          "value": [
            1793203528.672,
            "1"
          ]
        },
        {
          "metric": {
            "__name__": "k3dm_test_failure",
            "case": "1016",
            "instance": "test-all-local",
            "job": "k3dm-tests",
            "name": "dispatch chains publish-back after the E2E and preserves the exit code",
            "reason": "`[ \"$status\" -eq 0 ]' failed",
            "suite": "bats",
            "target": "test-all"
          },
          "value": [
            1793203528.672,
            "1"
          ]
        },
        {
          "metric": {
            "__name__": "k3dm_test_failure",
            "case": "1194",
            "instance": "test-all-local",
            "job": "k3dm-tests",
            "name": "PR check duration legend uses a readable side layout without changing its query",
            "reason": "`table = next(panel for panel in data[\"panels\"] if panel[\"id\"] == 6)' failed",
            "suite": "bats",
            "target": "test-all"
          },
          "value": [
            1793203528.672,
            "1"
          ]
        }
      ]
    }
  },
  "run": {
    "status": "success",
    "data": {
      "resultType": "vector",
      "result": [
        {
          "metric": {
            "__name__": "k3dm_test_run_complete",
            "instance": "test-all-local",
            "job": "k3dm-tests",
            "target": "test-all"
          },
          "value": [
            1793203528.715,
            "0"
          ]
        }
      ]
    }
  },
  "last": {
    "status": "success",
    "data": {
      "resultType": "vector",
      "result": [
        {
          "metric": {
            "__name__": "k3dm_test_last_timestamp_seconds",
            "instance": "test-all-local",
            "job": "k3dm-tests"
          },
          "value": [
            1793203528.752,
            "1793191274"
          ]
        }
      ]
    }
  },
  "step": {
    "status": "success",
    "data": {
      "resultType": "vector",
      "result": [
        {
          "metric": {
            "__name__": "k3dm_test_last_step_reached",
            "instance": "test-all-local",
            "job": "k3dm-tests",
            "step": "test",
            "target": "test-all"
          },
          "value": [
            1793203528.78,
            "1"
          ]
        }
      ]
    }
  }
}
```
Fourfailurecases130/1015/1016/1194. Sourcepublication1793191274=2026-10-28T12:41:14Z,
complete0,laststeptest. Rawsourcefile unavailable in/private/tmp and current
PythonTMPDIR(searchreturned[]); no originalrawstagecompletionmarkers reconstructed.
Initialshellgloblookup had `zsh: no matches found: /private/tmp/k3dm-test-all-*.log`;
replaced by boundedPath.glob, no fullrerun/publish. Initial19094Pushgatewayread
had no test-allseries; authoritativePrometheusseriesabove were available.

## Focused safe baseline

Exactguardscanoutput andrc:
```text
bin/k3dm-orbstack-upgrade:168:forecast_ok=0; curl -fsS "$PUSHGATEWAY_URL/metrics" | grep -q '^k3dm_release_forecast' && forecast_ok=1
scanner_exit=0
```
ActualguardBATS:
```text
1..2
not ok 1 grep-q guard: no non-allowlisted pipeline retains -q
# (in test file scripts/tests/lib/grep_q_pipe_guard.bats, line 13)
#   `[ "$status" -eq 1 ]' failed
ok 2 grep-q guard: matching producer is read to EOF under pipefail

```
CurrentPRChecks isolatedsuite, promtoolenabled:
```text
1..6
ok 1 PR checks dashboard YAML and embedded JSON are valid
ok 2 PR checks dashboard has filtered panels and repo variable
ok 3 PR checks tables say No open PRs instead of No data when nothing is open
ok 4 PR checks tables join populated rows without duplicate label fields
ok 5 PR check duration legend uses a readable side layout without changing its query
ok 6 PR checks distinguish current rows, retained history, empty ranges, and failed or stale reads

```
PRfix2b21e8afcommitted11:41:43Z, sourcefailedrunpublished12:41:14Z; thisalone
doesnotexplainwhichcheckout/testsnapshotwasused, order-dependentbehavior or
midrunworkingtreechanges. Do not inferhistoricalcauseresolved fromfocusedpass.
E2Ebaseline reproduction deferred untilworkerinstallsallfakeSSH/credential/
copy boundaries; no accidentalrealrunner/credentialcall authorized.

## Cloudflare facts and authorization boundary

OnlyoperatorinventoryclaimsAlwaysHTTPSOff/minTLS1.0, notindependentlyconfirmed.
No connectedCloudflareaccounttools available (metadata discoveryonlySitesmatches);
no credential access attempted. Offlinehelper supportsread-onlyexistingtokenor
sanitizedsnapshot, no newcredentialrequirement orapplymode. LiveF0account/read/
HTTP/TLS/SSOcompatibilitythenconcreteF1approval andtwoexternalsettingchanges
remainoperatorowned; helpercompletiondoesnotresolveactualedgeposture.
Officialprimarysourceschecked:
- https://developers.cloudflare.com/ssl/edge-certificates/additional-options/always-use-https/
- https://developers.cloudflare.com/ssl/edge-certificates/additional-options/minimum-tls/
- https://developers.cloudflare.com/api/resources/zones/subresources/settings/methods/get/
GET acceptsZoneSettingsRead; floor1.2 andTLS1.3enablementseparate; clientlegacy
protocolunsupported cannotcountasedgerejection. No tokens/rawbodies/liveprobes.

## Initial worker submissions — review/rework, not accepted

Both nativeLuna tasks started/exitedrun1. Offlineworker madeactualone-line
forecastproducerdrainfix andsaferdispatcherfakes; coordinatorrequestedrun2:
mutationmustexerciseexactrealguardscan(withnegative-safe/standalonecases),
largebodymustexerciseactualOrbStackforecastpath usingexistinglocalfakeharness,
and cleanrawShellCheck ratherthanglobalSC2034suppression. Existing6indirectfixture
SC2034warnings observed; finalsourcecommentsmustbe localandjustified. Current
capture below mayreflectin-progressannotationedits, so it is not finalgateproof:
```text

```

Cloudflareinitialdraft218lines/executable, read-only. Independentpurefunction
probes(no network/credentials) exposedmalformedsettingecho andTLSmisclassification/
client-configexception:
```json
{
  "executable": true,
  "unknown_setting_output": {
    "always_use_https": null,
    "min_tls_version": null,
    "ssl": "sentinel-secret-value",
    "security_header": null,
    "tls_1_3": null
  },
  "local_version_error": "edge_rejected",
  "local_config_error": "uncaught ValueError (no network called)"
}
```
CloudflareLunarun2requestedstrictsettingnormalization/identity/size, no arbitrary
Locationpathdisclosure, definitivepeer-alertclassification, localSSLunsupported
handling, realhandler/noAuth/noRedirect/versionlimit tests. No liveproviderprobe,
secretvalue, zonechange or automaticrecovery attempted. Firstdraftnotaccepted.
Optionaloperatororiginaltestlogpathquestion remainsnonblocking/unanswered.

## Independent final focused verification / Cloudflare landing

Cloudflare first-draft findings were corrected in Luna rework 2. API settings
are strictly typed/enumerated and matched by setting ID; unsafe Location data
is redacted. Only a structured peer protocol-version alert means edge rejection.
Local unsupported TLS setup returns an explicit client limitation, never a pass.
Real urllib handler and real SSLContext fixture tests verify no redirects, no
proxy inheritance, no public authorization/body, fixed API bearer destination,
protocol bounds, certificate validation, SNI and timeouts. No live calls.

The snapshot-mode test initially rejected all environment reads, including
stdlib SSLKEYLOGFILE lookup. Luna narrowed its spy to API credential access;
default/dry-run/help still forbid all environment access. No host policy changed.

Actual independent test output:

```text
============================= test session starts ==============================
platform darwin -- Python 3.15.1, pytest-9.1.1, pluggy-1.7.0
rootdir: /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.9/cloudflare-https-tls-preflight-luna
collected 169 items

scripts/tests/bin/test_cloudflare_posture.py ........................... [ 15%]
........................................................................ [ 58%]
......................................................................   [100%]

============================= 169 passed in 2.74s ==============================
```

Ruff actual output:

```text
All checks passed!
```

Landing repeated tests/lint/audit successfully. Final remote implementation SHA:
`2e0be3f6`; native dispatcher verification recorded pass. This verifies tooling
only; security bug stays OPEN, no F0/F1/F2 success inferred.

Offline focused BATS actual full output:

```text
1..116
ok 1 grep-q guard: no non-allowlisted pipeline retains -q
ok 2 grep-q guard: matching producer is read to EOF under pipefail
ok 3 grep-q guard: rejects a forbidden non-allowlisted fixture pipeline
ok 4 grep-q guard: standalone grep-q is not a forbidden pipeline
ok 5 grep-q guard: draining pipeline is not forbidden
ok 6 public runner functions are dispatchable (no leading underscore)
ok 7 e2e_remote.sh sources cleanly under set -euo pipefail
ok 8 eval_gates accepts a healthy runner
ok 9 eval_gates reports docker_down when Docker is unresponsive
ok 10 eval_gates reports busy when the runner lock is held
ok 11 eval_gates fails when the mean CPU idle is below the floor
ok 12 one dipped sample does not refuse a mostly idle runner
ok 13 eval_gates refuses a blob with no CPU samples
ok 14 preflight retry retries capacity refusal and then succeeds
ok 15 preflight retry does not retry busy refusal
ok 16 preflight retry stops after the configured capacity retries
ok 17 dispatch uses retry preflight and probe takes six top samples
ok 18 eval_gates fails on low memory
ok 19 eval_gates fails on low disk
ok 20 eval_gates treats missing metrics as a capacity stop, not available
ok 21 num_lt compares decimals
ok 22 SSH options never weaken host verification and keep BatchMode
ok 23 remote SSH command injects the homebrew+local PATH so tools resolve
ok 24 preflight reports unreachable when the probe yields nothing
ok 25 preflight surfaces the pure gate verdict from a live probe
ok 26 cluster reconcile refuses to operate on the hub cluster name
ok 27 cluster reconcile targets the dedicated runner context, never the hub
ok 28 bootstrap returns unreachable without mutating when SSH is down
ok 29 valid_digest accepts empty, bare, and repo-qualified sha256 digests
ok 30 valid_digest rejects malformed or injection-y digests
ok 31 runner_allowed enforces the allowlist
ok 32 dispatch rejects a runner outside the allowlist
ok 33 denied runners get the right redirect at every allowlist entry point before work starts
ok 34 unknown denied runner keeps allowlist error and allowlisted names stay permitted
ok 35 dispatch rejects an invalid digest
ok 36 dispatch refuses to run and never falls back locally when preflight fails
ok 37 dispatch reports the held lock holder and preserves the lock
ok 38 dispatch builds the correct remote command and records a transcript
ok 39 dispatch streams the GHCR token on stdin and not in the command string
ok 40 the dispatch transcript never contains the GHCR token
ok 41 dispatch returns the remote exit code when a token is streamed
ok 42 dispatch sends an empty credential when no token source is available
ok 43 an empty forwarded credential is treated as absent by the env resolver
ok 44 the token resolver never prints the token value
ok 45 dispatch refuses an unpushed SHA before SSH
ok 46 dispatch refuses a malformed runner repository URL
ok 47 dispatch uses an explicit runner repository override
ok 48 dispatch returns the remote exit code unchanged
ok 49 publish-back host loads from the operator conf file and env wins
ok 50 publish-back conf ignores shell metacharacters and warns when absent
ok 51 dispatch copies remote result files and preserves a non-zero exit code
ok 52 make e2e-remote requires RUNNER and wires to the dispatcher
ok 53 publish_build accepts a valid m2 payload and emits a deterministic name
ok 54 publish_build accepts a real null-heavy summary (no digest, unparsed results)
ok 55 publish_build rejects the local-m4 runner (local publishes itself)
ok 56 publish_build rejects unexpected keys (namespace/kubeconfig/labels injection)
ok 57 publish_build rejects missing required fields
ok 58 publish_build rejects a malformed digest and a bad exit code
ok 59 publish_build rejects an invalid result value
ok 60 publish_build rejects non-JSON payloads
ok 61 e2e_result_publish applies to the hub context and audits the outcome
ok 62 e2e_result_publish rejects an empty stdin payload
ok 63 e2e_result_publish rejects a bad payload and does not apply
ok 64 publisher install builds a restricted forced-command authorized_keys entry
ok 65 publisher install refuses a non-key file
ok 66 remote path never exfiltrates M4 kubeconfig, Vault, or Cloudflare secrets
ok 67 public failure/ops functions are dispatchable (no leading underscore)
ok 68 lock token carries only owner/pid/ts and no shell metacharacters
ok 69 the runner lock is a directory (atomic mkdir), probed with -e
ok 70 lock acquire records the owner token via mkdir + meta
ok 71 lock release only removes when the owner meta matches (never blind rm)
ok 72 dispatch refuses and never falls back locally when the lock is held
ok 73 dispatch chains publish-back after E2E and returns zero after lock release
ok 74 dispatch preserves a nonzero SSH exit after tee and failed result copy
ok 75 newest_summary returns the latest run json and skips retention markers
ok 76 synth_summary writes a schema-valid failed summary carrying the exit code
ok 77 synth_summary clamps an out-of-range exit code
ok 78 publish_back_push fails when no M4 target is configured
ok 79 publish_back_push uses the dedicated key and streams the file over stdin
ok 80 publish_back synthesizes a summary when the run left none, and returns 0
ok 81 publish_back retains a publication_pending marker when M4 is unavailable
ok 82 publish_replay pushes retained results and renames them published, idempotently
ok 83 publish_replay reports still-pending (non-zero) when a push fails
ok 84 M4 replay enforces the allowlist and the reachability guard
ok 85 M4 replay drives the remote publish_replay when the runner is reachable
ok 86 M4 republish keeps the newest result per service and tier in run order
ok 87 M4 republish continues after a publish failure
ok 88 M4 republish treats a failed fetch as nothing to do
ok 89 M4 republish enforces the allowlist and reachability guard
ok 90 unlock reports nothing to clear when no lock is present
ok 91 unlock refuses while an E2E run is still active
ok 92 unlock refuses a fresh (not-yet-stale) lock
ok 93 unlock clears a stale lock past the max age with no live run
ok 94 unlock enforces the allowlist
ok 95 health reports a hub outage as critical, distinct from runner state
ok 96 health is ok when the hub is up and the runner is available
ok 97 an unavailable runner is a warning, but critical when a run was requested
ok 98 the failure path never auto-restarts OrbStack, deletes a cluster, or blind-clears the lock
ok 99 make targets wire the failure/ops entry points
ok 100 orbstack upgrade: fresh compact last-success timestamp passes preflight
ok 101 orbstack upgrade: refuses a compact last-success timestamp older than 24 hours
ok 102 orbstack upgrade: refuses a missing or malformed last-success marker
ok 103 orbstack upgrade: FORCE overrides only no-update status
ok 104 orbstack upgrade: refuses active dispatch and lifecycle work
ok 105 orbstack upgrade: refuses wrong context or absent DR copy
ok 106 orbstack upgrade: refuses a real run without a TTY
ok 107 orbstack upgrade: typed no refuses without running orbctl update
ok 108 orbstack upgrade: watchdog unseals when Vault stays sealed and skips DR when it unseals
ok 109 orbstack upgrade: repoints only after UID change and an invalid SecretStore
ok 110 orbstack upgrade: repairs drift, republishes metrics, and kicks only dead port-forwards once
ok 111 orbstack upgrade: a hub that is ready when the deadline passes is not a failed upgrade
ok 112 orbstack upgrade: forecast probe drains large metrics producer to completion
ok 113 orbstack upgrade: reports empty regressions for equal counts and names a count drop
ok 114 orbstack upgrade: failed unseal does not stop later recovery and verification
ok 115 orbstack upgrade: never deletes Kubernetes objects or reads Keychain values
ok 116 orbstack upgrade: destructive and credential guard assertions are effective
```

Offline report-contract pytest actual output:

```text
============================= test session starts ==============================
platform darwin -- Python 3.15.1, pytest-9.1.1, pluggy-1.7.0
rootdir: /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.9/offline-test-all-regressions-luna
collected 37 items

scripts/tests/bin/test_orbstack_metrics.py .........                     [ 24%]
scripts/tests/bin/test_k3dm_test_metrics.py ............................ [100%]

============================= 37 passed in 25.29s ==============================
```

Raw ShellCheck, Bash syntax and git diff --check all exited 0 with no output.
No blanket warning exclusions were used. A broader curated BATS stage is running
in the isolated offline task under the repository tripwire, without the
make test-all wrapper or metrics publication. Results remain pending.

One read command accidentally looked for the Cloudflare test guide in the other
worker's isolated tree. Actual output (exit 1):

```text
cat: docs/tests/cloudflare-posture.md: No such file or directory
```

The read was repeated from the root tree containing the landed file and passed;
no implementation/test effect. No skipped evidence is counted as a pass.
