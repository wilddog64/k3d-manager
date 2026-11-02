# Hub-data test shared temporary directory collision

The resume-reason landing fast gate failed twice in `scripts/tests/plugins/hub_data.bats`. Its 20-line failure tail omitted the failing case; a parallel diagnostic captured the complete suite output below. The isolated suite passed 116/116. The failing test searched the landing gate's shared `TMPDIR` for `*.tar`. A scratch unrelated tar reproduces the same failure; the test now uses its own asserted scratch temporary directory.

## Reproduction before fix

```text
1..1
not ok 1 hub data export: streams each claim from its own node and path
# (in test file scripts/tests/plugins/hub_data.bats, line 318)
#   `run hub_data_export; [ "$status" -eq 0 ]; [ "$(find "${TMPDIR:-/tmp}" -name '*.tar' -print | wc -l)" -eq 0 ]; [ "$(grep -Ec '\.tar$' "$TEST_ROOT/age-stage.log" || true)" -eq 0 ]' failed

```

## After fixture isolation, same unrelated scratch tar

```text
1..1
ok 1 hub data export: streams each claim from its own node and path
```

## Full parallel suite failure

```text
1..116
ok 1 fixture checksum writer fails clearly when no SHA-256 tool is available
ok 2 fixture checksum writer uses shasum and writes a verifiable manifest
ok 3 git stub dispatches on subcommand when -C paths contain git words
ok 4 hub data restore: decrypts every claim and uses metadata
ok 5 hub data restore: node mismatch stops before extraction
ok 6 hub data restore: automatic stage is removed and caller stage survives
ok 7 hub data restore: empty context returns 2 without kubectl
ok 8 hub data restore: scales live workloads down and up
ok 9 hub data restore: applies the drill postgres before scaling any claim down
ok 10 hub data restore: drill postgres starts at zero replicas and carries no password
ok 11 hub data restore: a workload that cannot be scaled stops the restore with its name
not ok 12 hub data export: streams each claim from its own node and path
# (in test file scripts/tests/plugins/hub_data.bats, line 318)
#   `run hub_data_export; [ "$status" -eq 0 ]; [ "$(find "${TMPDIR:-/tmp}" -name '*.tar' -print | wc -l)" -eq 0 ]; [ "$(grep -Ec '\.tar$' "$TEST_ROOT/age-stage.log" || true)" -eq 0 ]' failed
ok 13 hub data export: encrypted contents, checksums, and split limit
ok 14 hub data vault: executing stub proves order, stdin hygiene, and cancel
ok 15 hub data vault: revoke runs after a post-root KV failure
ok 16 hub data vault: invalid path is rejected before any exec
ok 17 hub-data: the dispatcher finds every public hub_data function
ok 18 hub data inventory: walks nested Vault folders by their full path
ok 19 hub data inventory: a failed nested list names the path instead of failing silently
ok 20 hub data inventory: a zero LDAP count names LDAP
ok 21 hub data export setup: the policy grants list below secret/metadata so nested folders can be walked
ok 22 hub data inventory: counts Keycloak users and LDAP entries with the pod's own credentials
ok 23 hub data inventory: records the bare array vault kv list prints
ok 24 hub data inventory: an empty Vault listing or no root token fails instead of recording null
ok 25 hub data vault: an inventory without Vault paths fails before any Vault call
ok 26 hub data vault: a recorded path missing from the restored Vault fails and names it
ok 27 hub data vault: an empty root token fails before listing
ok 28 hub data export: an inventory failure stops the export before anything is pushed
ok 29 1 inventory uses Kubernetes login JWT on stdin only
ok 30 2 export never loads DR shards or generate-root
ok 31 3 empty login fails with setup guidance and pushes nothing
ok 32 4 missing pinned context fails before docker or git clone
ok 33 5 prune keeps recent exports and the last passing export
ok 34 5b prune retention boundary follows the clock, not the calendar
ok 35 6 prune keeps the newest when all exports are old
ok 36 7 results fetch failure is nonzero and does not push
ok 37 8 prune force-pushes snapshots only
ok 38 8b export passes its existing clone to prune
ok 39 9a manifest detects edited, extra, missing, and bad-age files
ok 40 9b remote mismatch writes no success metric and does not prune
ok 41 9c prune refuses a kept export with a bad manifest
ok 42 9 dry-run prune prints keep and prune without pushing
ok 43 11 rendered plist has scheduled command and calendar
ok 44 12 alert manifest contains all three export alerts
ok 45 13 legacy export verifies and one-sided metadata listing fails
ok 46 14 split export first part must have an age header
ok 47 15 unparseable export timestamp stops prune without push
ok 48 10 scheduled run posts newline-delimited metrics and kept count
ok 49 19 a lock left by a dead run is taken over; a live owner's lock is not
ok 50 17 setup self-test passes and revokes its single token
ok 51 17b setup binds the role to the API server audience (required from Vault 1.21)
ok 52 18 lock semantics distinguish manual, scheduled, and delegated ownership
ok 53 hub-data: repo file defaults resolve from the plugin, not the caller's directory
ok 54 recover B4-13: approval is typed and mismatches are refused
ok 55 recover B4-13a: target validation checks the local serverlb and server-0
ok 56 recover B4-13b: destructive checkpoints require explicit redo on resume
ok 57 recover B4-13c: compatibility requires format 2 and all claims
ok 58 recover B4-13d: verification uses metadata proof fields
ok 59 recover B4-13e: drill delegates verification to hub_data
ok 60 recover B4-15: hub mode skips the drill postgres manifest
ok 61 recover B4-17: ArgoCD resume patches the child before the parent with the recorded values
ok 62 recover K2: a drill target skips the Keycloak and ESO refresh; the hub runs it
ok 63 recover D1: credential guard security shim survives its installer function
ok 64 recover D2: refresh force-syncs, waits, discovers Keycloak, then restarts dependents
ok 65 recover D2: an OpenLDAP restart failure fails the refresh
ok 66 recover D2: waits for ArgoCD to create Keycloak before restarting it
ok 67 recover D2: missing Keycloak reports the bounded ArgoCD timeout
ok 68 recover D2: Grafana restart failure is a warning
ok 69 recover D3: restored claims use server-side hub-restore field ownership
ok 70 recover F4: Step 9 reminds the operator to recreate the export ServiceAccount
ok 71 recover F5: restore-hub allows finding the unseal-key cache
ok 72 recover K3: a missing ArgoCD Application is skipped, not a fatal kubectl exit
ok 73 recover K4: the Keychain age identity is drill-only and never prompts
ok 74 recover K5: V5 reads pv-pvc.yaml from the recovery's export dir, and names a missing one
ok 75 recover K6: RTO runs from approval across resumes, not from the last resume
ok 76 recover K1: a drill target never caches unseal keys in the Keychain; the hub does
ok 77 recover B4-18: Vault re-point order is config, shards, vault-root, root
ok 78 recover B4-20: refused preflight prevents hub-recover
ok 79 recover preflight: present hub is marked and approval warns before deletion
ok 80 recover preflight: absent hub skips validation and still asks approval
ok 81 recover teardown: present removes only exact k3d leftovers
ok 82 recover teardown: cluster-down wrapper deletes the hub and never discards hub data
ok 83 recover teardown: absent hub checks leftovers without cluster-down
ok 84 recover teardown: snapshot guard refusal stops before docker cleanup
ok 85 recover teardown: surviving cluster stops before docker cleanup
ok 86 recover preflight: a failed k3d listing refuses instead of treating the hub as absent
ok 87 recover teardown: a failed k3d listing stops before docker cleanup
ok 88 recover teardown: missing hub_present fails before cluster-down
ok 89 recover B4-21: teardown precedes rebuild and resume
ok 90 recover B4-21: hub-recover-all preserves DR shards during hub rebuild
ok 91 recover B4-22: teardown failure prevents rebuild and resume
ok 92 recover B4-23: keychain preflight refusal stops hub-recover-all before teardown
ok 93 recover B4-D1: a failed step records its rc and does not run the next step
ok 94 recover B4-D2: empty ArgoCD jsonpath is paused and auto-sync is rejected
ok 95 recover B4-D3: vault-root is JSON from stdin and no literal dash is used
ok 96 recover B4-R1: finished steps are skipped and unfinished step 4 needs redo
ok 97 recover B4-R2: restore uses the recorded export and never clones
ok 98 recover B4-R3: verification passes context to kubectl
ok 99 recover B4-R3: a failed LDAP admin bind fails LDAP verification
ok 100 recover B4-R4: resume failure is logged and report records false
ok 101 recover B4-14: without a TTY approval is refused before the prompt
ok 102 recover B4-16: age identity is not sent in command argv
ok 103 recover B4-17a: ArgoCD read-back stops before destructive work
ok 104 recover B4-19: V8 records SecretSyncedError as false
ok 105 recover B4-21: drill unseal uses the moved hub function
ok 106 dr credential shim: stdin is recorded and forwarded byte-for-byte without -w value
ok 107 dr credential shim: argv -w is skipped and never written under the run directory
ok 108 dr credential shim: enforce exits 44 and does not reach real security
ok 109 dr credential scope: a drill may not touch the unseal-key cache or another context's root token
ok 110 dr credential scope: a hub restore may cache unseal keys; a drill rehearsal may not; root token only for the target context
ok 111 dr credential guard: hub_data_recover records in its own process, also on RESUME, and scopes by target
ok 112 dr restore: an out-of-cluster docker target is refused before exec
ok 113 recover F1: the preflight summary is on stderr so it shows before the approval; stdout is only RUN_ID
ok 114 recover F2: a resumed run pauses ArgoCD again and keeps the value recorded before the first pause
ok 115 recover F3: step 2 prompts on every run and hub mode never reads the age identity from the Keychain
ok 116 scheduled export: SSH guard runs first and a failed guard prevents export

```

Follow-up: retain the failing test case in fast-gate summaries instead of only the last 20 lines.
