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
