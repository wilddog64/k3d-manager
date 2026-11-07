# Phase B: headless CA trust containment

**Result:** Offline containment tests pass; the code remains on the task branch and is not landed. The operator requested review of Phase B before Phase C. The historical cause remains inconclusive as recorded in `docs/issues/2026-11-03-ca-trust-phase-a-diagnosis.md`.

Prior decisions preserved by the draft are automatic trust for an untrusted CA (`docs/plans/v1.4.6-auto-trust-vault-ca.md`), skipping a trusted CA (`docs/bugs/v1.5.0-bugfix-acg-up-vault-ca-pty-sudo.md`), and warning/continuing on trust failure (`docs/bugs/v1.5.3-bugfix-acg-up-vault-ca-trust-no-soft.md`). Those prior incidents do not establish the cause of this stall.

The independently run fixture exercises the production caller, bounded client and supervisor code with fake permission and security operations. It uses a one-second monotonic test deadline and short cleanup grace, a TERM-resistant controlled child holding stdout and stderr open, and a sentinel after the caller. This tests controlled same-user processes; it does not establish real sudo/root signal behavior or cancellation of work already handed to macOS services. No live Keychain, sudo, cloud or cluster operation was performed.

Independent command (in the task worktree, with scratch HOME and the host-tool tripwire):

```text
scripts/tests/tripwire.sh bats --print-output-on-failure --show-output-of-passing-tests scripts/tests/bin/vault_ca_trust_e2e.bats scripts/tests/bin/vault_ca_trust_supervisor.bats scripts/tests/bin/cluster_up.bats
```

Full output follows; 89 passed, 0 failed, 0 skipped:

```text
1..89
ok 1 headless caller bounds controlled trust and continues after timeout or denial
# success: exit=0 elapsed=0.308s
# INFO:[acg-up] Trusting Vault CA cert in macOS System Keychain (may prompt for sudo password)...
# bounded-result=0
# NEXT-SENTINEL
# denied: exit=0 elapsed=0.076s
# INFO:[acg-up] Trusting Vault CA cert in macOS System Keychain (may prompt for sudo password)...
# controlled permission denied
# bounded-result=77
# WARN:[acg-up] Could not add Vault CA to System Keychain — browser may show TLS warning for ArgoCD HTTPS
# NEXT-SENTINEL
# hung: exit=0 elapsed=1.542s
# INFO:[acg-up] Trusting Vault CA cert in macOS System Keychain (may prompt for sudo password)...
# child-stdout-inherited
# child-stderr-inherited
# Vault CA trust interrupted
# Vault CA trust watchdog could not signal the full sudo process group; the root helper deadline remains active
# Vault CA trust timed out waiting for sudo or the root helper
# bounded-result=124
# WARN:[acg-up] Could not add Vault CA to System Keychain — browser may show TLS warning for ArgoCD HTTPS
# NEXT-SENTINEL
ok 2 supervisor accepts a safe caller-owned certificate and rejects unsafe paths
#
ok 3 supervisor installation requires root-owned fixed executable paths
ok 4 supervisor entry rejects extra arguments and dispatches only a scratch certificate
ok 5 supervisor absolute deadline covers preflight and certificate opening
ok 6 expired supervisor deadline never spawns the Keychain command
ok 7 supervisor ignores a deadline alarm during TERM grace and still kills the group
ok 8 bounded sudo client caps startup and kills a resistant descendant after leader exit
ok 9 bounded sudo client enforces its deadline across sudo policy startup
ok 10 supervisor preserves quick security success and failure status
ok 11 supervisor bounds a TERM-resistant controlled security process group
ok 12 supervisor interruption terminates its controlled security process group
ok 13 supervisor cleans up when termination arrives as signals are unmasked
ok 14 acg-up TTL M1 restarts an expiring sandbox with aws
ok 15 acg-up TTL M2 fails when the sandbox restart fails
ok 16 acg-up TTL M3 proceeds without restart for safe or unreadable TTL
ok 17 acg-up TTL M4 honors the provisioning floor override
ok 18 headless Vault CA trust runs quick success once and warns on quick failure
ok 19 headless Vault CA trust fails closed when the fixed supervisor is missing
ok 20 interactive Vault CA trust preserves direct TTY runner when helper is missing
ok 21 non-Darwin browser setup skips Keychain trust while Darwin invokes it
ok 22 already trusted Vault CA skips the add command and stubs stay in scratch
ok 23 acg-up forwards default and configured ArgoCD ports to the fixed listener helper
ok 24 acg-up TTL N2 does not restart after a successful or unnecessary extension
ok 25 acg-up Step 1 delegates TTL safety and does not inline warn-and-continue
ok 26 ACG sandbox registration carries the provider label used by observability selection
ok 27 acg-up identity Application uses server-side apply with server-side diff
ok 28 acg-up preseeds smoke-user Vault before the identity Application apply
ok 29 acg-up applies the extracted identity Application file without an inline heredoc
ok 30 acg-up leaves the hub Grafana port-forward wrapper path untouched
ok 31 acg-up forwards Keycloak to the named http Service port
ok 32 acg-up sources overrides and exits at the dry-run Step 4 seam
ok 33 acg-up repairs the Hub host alias before ArgoCD registration
ok 34 acg-up uses the shared host resolver and fails when it cannot resolve the host
ok 35 acg-up skips the CoreDNS patch when the Hub host alias is already present
ok 36 acg-up patches a wrong Hub host alias without restarting CoreDNS
ok 37 acg-up patches a missing Hub host alias without restarting CoreDNS
ok 38 acg-up reconciles other app-cluster registrations after registering the hub
ok 39 acg-up verifies exact ACG registration before deploying observability
ok 40 acg-up does not capture the dry-run wrapper as its own base
ok 41 acg-up dry-run previews core and never crosses the Step 4 seam
ok 42 acg-up sources the Argo CD plugin before readiness checks
ok 43 acg-up restores cosign signing only for a newly created Hub
ok 44 acg-up never references signing_init or signing_rotate_key
ok 45 acg-up preserves existing Vault identity secrets on rebuild
ok 46 acg-up verifies every LDAP password before checkpointing the seed
ok 47 acg-up seeds LDAP users with the openldap-admin Secret, not the pod env
ok 48 acg-up keeps LDAP user passwords out of command arguments
ok 49 acg-up selects the LDAP provider by type and keeps its password off argv
ok 50 acg-up reads the LDAP bind password from openldap-admin
ok 51 acg-up uses the LDAP provider helper and removes the substring lookup
ok 52 acg-up and refresh regenerate the fixed ArgoCD browser listener
ok 53 acg-up registers the app cluster with a real provider and the shopping-cart label
ok 54 acg-up data-layer explanation reports sync cause and NotReady node
ok 55 acg-up data-layer explanation stays silent when healthy
ok 56 acg-up data-layer explanation truncates long operation messages
ok 57 acg-up data-layer explanation survives kubectl failure
ok 58 acg-up reconnect timeout does not claim the controller connected
ok 59 acg-up image-pull probe reports a blocked container with pod, container and reason
ok 60 acg-up image-pull probe stays quiet when every container is running
ok 61 acg-up image-pull probe ignores a non-fatal waiting reason
ok 62 acg-up data-layer abort waits three polls before giving up
ok 63 acg-up data-layer abort resets its strike count when the pull recovers
ok 64 acg-up checks for a blocked image pull inside both data-layer sync waits
ok 65 acg-up failure cleanup leaves a port-forward owned by another run
ok 66 acg-up failure cleanup kills and removes a port-forward owned by this run
ok 67 acg-up records Vault port-forward ownership
ok 68 acg-up failure cleanup warns for a stack created by this run
ok 69 acg-up failure cleanup reports a missing marked stack
ok 70 acg-up failure cleanup keeps an unconfirmed warning on AWS failure
ok 71 acg-up failure cleanup does not warn for a reused stack
ok 72 acg-up success clears the CloudFormation ownership marker
ok 73 acg-up clears a stale ownership marker at start and after success
ok 74 acg-up failure cleanup tolerates a missing or unreadable marker
ok 75 acg-up failure cleanup leaves a pre-existing cloudflare tunnel running
ok 76 acg-up failure cleanup removes only a tunnel it created itself
ok 77 acg-up marks the tunnel plist as created only when none existed
ok 78 acg-up failure cleanup never boots out the tunnel unconditionally
ok 79 acg-up puts ~/.local/bin on PATH before anything reads it
ok 80 acg-up guards the PATH prepend so it cannot duplicate an existing entry
ok 81 acg-up Keycloak reverse tunnel helper accepts a non-zero HTTP status
ok 82 acg-up Keycloak reverse tunnel helper rejects curl status 000
ok 83 acg-up Keycloak reverse tunnel helper rejects an empty curl status
ok 84 acg-up Step 10g.5 reuses or replaces the Keycloak reverse tunnel
ok 85 acg-up root-owned state preflight is before launchd sudo
ok 86 acg-up root-owned state preflight passes with no root-owned folders
ok 87 acg-up root-owned state preflight stops with repair guidance
ok 88 acg-up Vault port cleanup kills the listener but not a connected client such as an ssh -R tunnel
ok 89 acg-up Step 4 frees the Vault port through the listener-only cleanup
```
