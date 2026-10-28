# Offline P2 curated-stage independent verification

## Attempt and result

Coordinator ran `scripts/tests/tripwire.sh ./scripts/k3d-manager test all`
in Luna's isolated offline-test-all-regressions-luna worktree. This is the
curated BATS stage, not the complete three-stage make test-all wrapper.
No metrics were published. Python resolved to 3.15.1. Actual exit: 1.

Tally: 1,892 passed, 20 skipped, one failed (1,913 total). All four source
failure cases passed in this current checkout: guard130, E2E busy1018 and
publish-back1019, and PR Checks legend1198. Renumbering follows added tests.
The sole failure is existing ESO test473, using the removed load_module API.
Independent focused rerun diagnostics:

```text
1..1
not ok 1 smoke test ESO wiring samples app and hub through helper
# (in test file scripts/tests/lib/webhook_hub_eso.bats, line 155)
#   `[ "$status" -eq 0 ]' failed
# Last output:
# Traceback (most recent call last):
#   File "<stdin>", line 7, in <module>
# AttributeError: 'SourceFileLoader' object has no attribute 'load_module'. Did you mean '.exec_module' instead of '.load_module'?
```

The same case with the existing Python3.13.6 environment (no new installation):

```text
1..1
ok 1 smoke test ESO wiring samples app and hub through helper
```

Track separately in [existing Python loader P3](../bugs/2026-10-15-webhook-bats-load-module-removed-in-python-3-15.md)
and [previous ESO failure evidence](2026-10-27-existing-eso-test-python-loader-failure.md).
Those files and production ESO code were not modified by this task.

Skipped cases remain skipped, not passed. Reasons appear verbatim below: live
opt-ins, missing legacy/history fixtures, pending features, missing amtool and
promtool, and unavailable sibling realm fixture. The relevant PR Checks suite
is independently rerun with the available promtool; its result is recorded in
[the batch review](2026-10-28-two-new-p2-luna-batch.md). Other missing prerequisites
were not installed or enabled to broaden this task. The tripwire intercepted
545 host-tool calls and reports none reached real binaries; no live verification
is inferred. Fresh operator full-stage output/metrics are still required to
resolve incomplete/failing-suite alerts.

After this run, coordinator added two explicit remote command-order and
rc-preservation assertions to the already reviewed E2E fixtures. The focused
116-case gate is rerun after that change; broad output below predates only those
extra assertions. No production change was made after the broad run.

## Full actual curated BATS output

```text
running under bash version 5.3.20(1)-release
1..1913
ok 1 deploy_app_cluster --help passes through the guard
ok 2 deploy_app_cluster without --confirm is blocked by the guard safety gate
ok 3 deploy_app_cluster --confirm reaches the confirmed path (Finding 2b)
ok 4 deploy safety gate: no args requires confirm
ok 5 deploy_vault --dry-run prints commands
ok 6 _start_k3s_service falls back to manual start without systemd
ok 7 _ensure_path_exists uses sudo when available
ok 8 _ensure_path_exists fails when sudo unavailable
ok 9 _install_k3s renders config and manifest
ok 10 every BATS suite lives in a directory some target globs
ok 11 default (laptop) profile uses the bridge endpoint
ok 12 hostinger profile uses the in-cluster endpoint and disables the bridge
ok 13 explicit overrides win over profile defaults
ok 14 laptop profile derives token CSS auth
ok 15 hostinger profile derives kubernetes CSS auth
ok 16 persisted state file selects the profile when env is unset
ok 17 explicit env wins over the persisted state file
ok 18 app context uses its own persisted profile instead of the legacy global file
ok 19 hostinger context falls back to the legacy global file for backward compatibility
ok 20 per-context CSS override applies when base env is unset
ok 21 explicit base env CSS wins over a per-context override
ok 22 without a per-context override the profile default is used
ok 23 per-context overrides apply to bridge and auth with a sanitized context key
ok 24 watchdog renders into the provided namespace
ok 25 watchdog image is pinned (not latest)
ok 26 watchdog mounts the vault-unseal secret optionally
ok 27 watchdog targets the in-cluster endpoint and unseals via shard-1
ok 28 inline shell vars survived envsubst (not expanded away)
ok 29 _acg_write_credentials writes [default] profile to ~/.aws/credentials
ok 30 _acg_write_credentials sets file permissions to 600
ok 31 _acg_write_credentials creates ~/.aws directory if missing
ok 32 acg_import_credentials parses label format (Pluralsight UI copy)
ok 33 acg_import_credentials parses export format
ok 34 acg_import_credentials succeeds with AKIA key and no session token
ok 35 acg_import_credentials returns 1 on empty/unparseable input
ok 36 acg_import_credentials --help exits 0
ok 37 acg_get_credentials --help exits 0
ok 38 _acg_update_ssh_config creates missing SSH config and server target idempotently
ok 39 _acg_update_ssh_config adds server stanza without changing agent aliases
ok 40 _acg_update_ssh_config updates existing server and tunnel stanzas
ok 41 _acg_extend_playwright: returns 0 when node script succeeds
ok 42 _acg_sync_known_hosts prunes stale managed AWS IPs and records current ones # skip Feature not yet implemented: see docs/issues/2026-05-13-acg-up-maintain-known-hosts-for-managed-aws-ips.md
ok 43 _acg_extend_playwright: returns 1 when node script fails
ok 44 acg_watch_start reloads the agent so retargeted run-dir logs take effect
ok 45 _agent_checkpoint: fails when git missing
ok 46 _agent_checkpoint: skips when working tree clean
ok 47 _agent_checkpoint: commits when working tree dirty
ok 48 _agent_lint: skips when AI disabled
ok 49 _agent_audit: detects test weakening (placeholder)
ok 50 _agent_audit: flags bare sudo in staged diff
ok 51 _agent_audit: ignores _run_command sudo in diff
ok 52 _agent_audit: flags kubectl exec with credential env var in staged diff
ok 53 _agent_audit: passes clean staged diff
ok 54 _agent_audit: k3d-manager honours the lib-foundation remote-sudo marker
ok 55 scripts/lib/agent_rigor.sh is a shim to the subtree copy
ok 56 _gemini_ensure_github_session: returns 0 when gemini succeeds
ok 57 _gemini_ensure_github_session: returns 1 when gemini fails
ok 58 _agy_prompt: succeeds on first model
ok 59 _agy_prompt: falls back to next model on 429
ok 60 _agy_prompt: fails when all models exhausted
ok 61 _agy_prompt: passes --dangerously-skip-permissions to agy when requested
ok 62 _agy_prompt: creates workspace temp dir
ok 63 no bare '! cmd' assertions in BATS suites (set -e ignores them)
ok 64 _cleanup_on_success removes every provided path
ok 65 cluster-down no longer removes the legacy active-provider path
ok 66 cluster-down unrecords the current provider
ok 67 _dirservice_activedirectory_config displays configuration
ok 68 _dirservice_activedirectory_validate_config succeeds in test mode
ok 69 _dirservice_activedirectory_validate_config fails when AD_DOMAIN not set
ok 70 _dirservice_activedirectory_validate_config fails when AD_SERVERS not set
ok 71 _dirservice_activedirectory_validate_config fails when AD_BIND_DN not set
ok 72 _dirservice_activedirectory_validate_config fails when AD_BIND_PASSWORD not set
ok 73 _dirservice_activedirectory_validate_config skips check when ldapsearch unavailable
ok 74 _dirservice_activedirectory_generate_jcasc creates valid YAML
ok 75 _dirservice_activedirectory_generate_jcasc requires namespace argument
ok 76 _dirservice_activedirectory_generate_jcasc requires secret_name argument
ok 77 _dirservice_activedirectory_generate_jcasc requires output_file argument
ok 78 _dirservice_activedirectory_generate_env_vars creates output file
ok 79 _dirservice_activedirectory_generate_env_vars requires secret_name argument
ok 80 _dirservice_activedirectory_generate_env_vars requires output_file argument
ok 81 _dirservice_activedirectory_generate_authz creates valid authorization config
ok 82 _dirservice_activedirectory_generate_authz includes custom permissions from env var
ok 83 _dirservice_activedirectory_generate_authz requires output_file argument
ok 84 _dirservice_activedirectory_get_groups returns test groups in test mode
ok 85 _dirservice_activedirectory_get_groups requires username argument
ok 86 _dirservice_activedirectory_get_groups fails when ldapsearch unavailable
ok 87 _dirservice_activedirectory_create_credentials validates AD_BIND_DN is set
ok 88 _dirservice_activedirectory_create_credentials validates AD_BIND_PASSWORD is set
ok 89 _dirservice_activedirectory_create_credentials fails when secret_backend_put unavailable
ok 90 _dirservice_activedirectory_create_credentials calls secret_backend_put when available
ok 91 _dirservice_activedirectory_init runs validation
ok 92 _dirservice_activedirectory_init fails when validation fails
ok 93 _dirservice_activedirectory_init fails when credential storage fails
ok 94 _dirservice_activedirectory_smoke_test_login requires jenkins_url argument
ok 95 _dirservice_activedirectory_smoke_test_login requires test_user argument
ok 96 _dirservice_activedirectory_smoke_test_login requires test_password argument
ok 97 _dirservice_activedirectory_smoke_test_login fails when curl unavailable
ok 98 _dirservice_activedirectory_smoke_test_login fails when authentication fails
ok 99 _dirservice_activedirectory_smoke_test_login succeeds with valid credentials
ok 100 AD_BASE_DN auto-detection from AD_DOMAIN
ok 101 AD_USER_SEARCH_BASE uses AD_BASE_DN
ok 102 AD_GROUP_SEARCH_BASE uses AD_BASE_DN
ok 103 canonical DRY_RUN disables commands and activates predicate
ok 104 legacy K3DM_DEPLOY_DRY_RUN remains a compatible alias
ok 105 dry-run predicate is inactive when both flags are unset or zero
ok 106 dry-run prints command instead of executing
ok 107 dry-run with --prefer-sudo shows sudo prefix
ok 108 dry-run with --require-sudo shows sudo prefix
ok 109 normal mode executes command when K3DM_DEPLOY_DRY_RUN unset
ok 110 normal mode executes command when K3DM_DEPLOY_DRY_RUN=0
ok 111 no-op when bats already meets requirement
ok 112 falls back to source install when sudo unavailable
ok 113 uses package manager when sudo available
ok 114 no-op when copilot binary already present
ok 115 installs via brew when available
ok 116 falls back to release installer when brew missing
ok 117 fails when copilot is not authenticated
ok 118 copilot binary is operational with COPILOT_GITHUB_TOKEN # skip K3DM_COPILOT_LIVE_TESTS not set — skipping live binary check
ok 119 no-op when kubeconform is already installed
ok 120 prefers Homebrew when available
ok 121 installs the pinned release into ~/.local/bin when the checksum matches
ok 122 refuses a download whose checksum does not match and installs nothing
ok 123 every supported platform has a pinned 64-hex checksum
ok 124 validate-manifests ensures kubeconform and pins the CRD catalog to a commit
ok 125 no-op when node already installed
ok 126 installs via brew when available
ok 127 installs via apt-get on Debian systems
ok 128 installs via dnf on RedHat systems
ok 129 falls back to release installer when no package manager works
ok 130 grep-q guard: no non-allowlisted pipeline retains -q
ok 131 grep-q guard: matching producer is read to EOF under pipefail
ok 132 grep-q guard: rejects a forbidden non-allowlisted fixture pipeline
ok 133 grep-q guard: standalone grep-q is not a forbidden pipeline
ok 134 grep-q guard: draining pipeline is not forbidden
ok 135 sweep: dry-run counts stale without removing it
ok 136 sweep: apply removes stale and keeps live, reported, young and metadata files
ok 137 sweep: records the count and oldest age of SKIP reservations
ok 138 sweep: empty sandbox list refuses to remove
ok 139 sweep: empty pod IP list refuses to remove
ok 140 sweep: crictl failure refuses to remove
ok 141 sweep: bad argument is rejected
ok 142 N1: pre-fix sweep must fail the empty-list safety case # skip
ok 143 N2: pre-fix sweep must fail the young-file safety case # skip
ok 144 cni ipam install: enables the timer
ok 145 cni ipam install: rejects an unexpected staging directory
ok 146 cni ipam install: dry run sends no remote command
ok 147 cni ipam install: both provider call sites follow the spec
ok 148 the pushgateway probe uses the installed service name
ok 149 no producer refers to the bare pushgateway service name
ok 150 all three sites agree on the pushgateway service name
ok 151 hostinger watchdog: skips when Vault StatefulSet is absent
ok 152 hostinger watchdog: installs for an existing Vault StatefulSet
ok 153 hostinger watchdog: reports installer failure
ok 154 hostinger refresh: calls watchdog after edge refresh
ok 155 M2: refresh path installs the watchdog on ubuntu-hostinger in the Vault namespace
ok 156 M3: watchdog image comes from the target context's Vault StatefulSet
ok 157 N1: every kubectl/_kubectl call of the install carries the given --context
ok 158 N1b: the refresh path never touches any other context
ok 159 N2: no unseal key material is printed
ok 160 N2b: kubectl calls do not read the unseal secret data
ok 161 M4: Degraded app on expected branch is reported under a health heading
ok 162 N3: app on the expected branch is never listed under the stale values branch heading
ok 163 N3b: only a Degraded app on expected branch -> no stale heading at all
ok 164 hub host resolver selects the IPv4 answer after Name
ok 165 hub host resolver returns empty for NXDOMAIN
ok 166 hub host resolver returns empty when docker fails
ok 167 hub host resolver skips IPv6 and selects IPv4
ok 168 hub host resolver source contains no getent
ok 169 installs kubectl via brew on macOS
ok 170 uses non-macOS installers when not on macOS
ok 171 istio-ingressclass manifest exists
ok 172 istio-ingressclass has the correct kind
ok 173 istio-ingressclass has the correct name
ok 174 istio-ingressclass has the correct controller
ok 175 Istio operator template renders valid YAML without HPAs
ok 176 Istio operator template preserves component resources
ok 177 fails when prompt requests forbidden shell cd
ok 178 invokes copilot with scoped prompt and guard rails
ok 179 name- and server-matched apps are both deleted; others are not
ok 180 Secret is deleted before the first Application
ok 181 in-cluster server is never used
ok 182 deregister never deletes the shared observability ApplicationSet
ok 183 cluster-down keep-hub guard protects the Vault LaunchAgent
ok 184 _provider_k3s_aws_deploy_cluster --help prints k3s-aws usage
ok 185 _provider_k3s_aws_destroy_cluster --help prints k3s-aws usage
ok 186 _provider_k3s_aws_destroy_cluster without --confirm fails
ok 187 k3s-aws fallback watcher logs away from the terminal
ok 188 k3s-aws skips the fallback watcher when launchd is loaded
ok 189 k3s-aws preserves the already-running watcher branch
ok 190 N1: launchd retires a stale cluster-up watcher
ok 191 k3s-aws removes a dead launchd watcher PID
ok 192 k3s-aws does not kill an unrelated launchd PID
ok 193 cluster-up stops the shell watcher only after launchd succeeds
ok 194 _provider_k3s_aws_deploy_cluster runs acg_provision once
ok 195 k3s-aws marks a newly created stack with its name and region
ok 196 k3s-aws does not mark a healthy reused stack
ok 197 k3s-aws dry-run does not write stack ownership
ok 198 k3s-aws retries app provisioning over SSH after SSM bootstrap fails
ok 199 k3s-aws uses SSH when the laptop Vault reverse bridge is required
ok 200 k3s-aws overrides explicit SSM when the laptop Vault reverse bridge is required
ok 201 k3s-aws fails when SSM bootstrap and SSH retry both fail
ok 202 k3s-aws derives four agent hosts and five total nodes from ACG_AGENT_COUNT
ok 203 k3s-aws preserves two-agent default and three-node total
ok 204 k3s-aws rejects a malformed ACG_AGENT_COUNT before provisioning
ok 205 _provider_k3s_aws_destroy_cluster --confirm runs acg_teardown
ok 206 _provider_k3s_aws_destroy_cluster skips deregister when acg_teardown fails
ok 207 _k3s_aws_deregister_cluster DRY_RUN describes the hub cleanup
ok 208 _k3s_aws_deregister_cluster deletes only ubuntu-k3s hub objects
ok 209 _k3s_aws_deregister_cluster is idempotent when hub objects are absent
ok 210 _k3s_aws_deregister_cluster fails when hub kubectl is unreachable
ok 211 k3s-aws keeps SSM when registration and tunnel succeed
ok 212 k3s-aws falls back to SSH when SSM registration fails
ok 213 k3s-aws fails when both SSM and SSH tunnels fail
ok 214 k3s-aws SSM registration timeout returns instead of exiting the shell
ok 215 k3s-aws falls back to SSH when the real SSM registration wait times out
ok 216 _provider_k3s_oci_deploy_cluster --help prints k3s-oci usage
ok 217 _provider_k3s_oci_deploy_cluster -h prints k3s-oci usage
ok 218 _provider_k3s_oci_destroy_cluster --help prints destroy usage
ok 219 _provider_k3s_oci_destroy_cluster without --destroy-infra preserves instance
ok 220 _provider_k3s_oci_destroy_cluster --destroy-infra aborts when user does not type yes
ok 221 _provider_k3s_oci_destroy_cluster --destroy-infra proceeds when user types yes
ok 222 _oci_validate_prereqs fails when oci CLI not in PATH
ok 223 _oci_validate_prereqs fails when required env vars missing and no state file
ok 224 _oci_reconfigure removes env and image-id state files
ok 225 _provider_k3s_oci_deploy_cluster calls all twelve steps in order
ok 226 _provider_k3s_oci_deploy_cluster aborts when validate_prereqs fails
ok 227 _provider_k3s_oci_deploy_cluster aborts when install_cilium fails
ok 228 _oci_provision_instance skips launch when instance already running
ok 229 _oci_provision_instance launches instance when not running
ok 230 _oci_provision_infrastructure writes server-instance-id and agent-instance-id
ok 231 _oci_install_k3s_server skips when k3s already installed
ok 232 _oci_install_k3s_server sends --flannel-backend=none and --disable-network-policy
ok 233 _oci_install_cilium skips when Cilium already installed
ok 234 _oci_install_cilium includes cni.exclusive=false and kubeProxyReplacement=true
ok 235 _oci_install_k3s_agent skips when k3s-agent already active
ok 236 _oci_install_k3s_agent joins via server private IP, not public IP
ok 237 _oci_install_k3s_agent wait loop counts Ready nodes (not grep -v master)
ok 238 _oci_smoke_test fails when fewer than 2 nodes are Ready
ok 239 _oci_smoke_test fails when Cilium DaemonSet is not ready
ok 240 _oci_destroy_infrastructure terminates both server and agent instances
ok 241 oci_backup fails when etcd-snapshot SSH command fails
ok 242 oci_backup fails when snapshot download produces empty file
ok 243 oci_restore fails when snapshot name has invalid format
ok 244 oci_restore fails when scp upload to server fails
ok 245 oci_restore fails when remote restore SSH command fails
ok 246 deploy_observability calls envsubst with $ARGOCD_NAMESPACE and $K3D_MANAGER_BRANCH
ok 247 deploy_observability_acg retires legacy Applications before applying the cluster matrix
ok 248 deploy_observability_acg falls back to generated Prometheus config when Vault bootstrap write fails
ok 249 legacy ACG retirement preserves the set before stripping each owned finalizer
ok 250 legacy ACG finalizer failure returns nonzero
ok 251 legacy ACG retirement is a no-op when no owned Applications exist
ok 252 deploy_observability_acg does not apply the set after retirement fails
ok 253 observability exposes alertmanager login proxy and make targets
ok 254 observability restores alertmanager access layer when local agents are missing
ok 255 prometheus auth proxy keeps the public and raw backend ports separate
ok 256 prometheus login writes protected credentials without printing the password
ok 257 prometheus auth proxy skips unreadable Vault credentials and missing auth files
ok 258 prometheus auth proxy bootout precedes bootstrap
ok 259 trivy_scan_report calls kubectl get vulnerabilityreports -A for Hub context
ok 260 trivy_scan_report prints an explicit no-report note when empty
ok 261 trivy_scan_report calls kubectl get vulnerabilityreports -A --context ubuntu-k3s for ACG
ok 262 trivy_infra_security_report queries Prometheus for compliance and RBAC findings
ok 263 trivy_infra_security_report tolerates unreachable Prometheus backends
ok 264 observability_status iterates over monitoring trivy-system for both contexts
ok 265 observability exposes alertmanager via cloudflared and make targets
ok 266 prometheus basic-auth never seeds the weak 'password' default
ok 267 Prometheus rotation entrypoint and launchd template are value-free
ok 268 Prometheus rotation notice reads the hub Secret without exposing its URL
ok 269 Prometheus rotation notice prefers SLACK_WEBHOOK_URL without reading the Secret
ok 270 Prometheus rotation notice warns and succeeds when the hub Secret is unreadable
ok 271 _acg_record_provider writes a set marker and the legacy scalar
ok 272 _acg_record_provider normalizes aliases into the set
ok 273 _acg_list_active_providers lists every live marker
ok 274 _acg_unrecord_provider removes only its own marker; siblings survive
ok 275 _acg_unrecord_provider clears the legacy scalar only when it names that provider
ok 276 _acg_list_active_providers falls back to the legacy scalar when no dir markers
ok 277 _acg_resolve_provider uses the single live set member when offline
ok 278 _acg_resolve_provider on multiple live members falls back to the legacy scalar
ok 279 _acg_resolve_provider back-compat: legacy scalar only, no dir, resolves it
ok 280 _acg_resolve_provider defaults to k3s-hostinger with no set and no scalar
ok 281 _acg_migrate_flat_state moves flat state under the legacy owner
ok 282 _acg_migrate_flat_state claims flat state for the run provider when its context is reachable (no marker)
ok 283 _acg_migrate_flat_state leaves flat state untouched when no marker AND run provider context unreachable
ok 284 _acg_migrate_flat_state is a no-op when there is no flat state
ok 285 _acg_migrate_flat_state skips when the target subdir already exists
ok 286 _acg_provider_state_dir returns the scoped per-provider path
ok 287 _acg_lock_acquire creates the lock and records the pid; release removes it
ok 288 _acg_lock_acquire reclaims a stale lock whose owner is dead
ok 289 _acg_lock_acquire with an empty lock dir is a no-op success
ok 290 _acg_lock_acquire creates a missing parent directory instead of spinning
ok 291 _acg_provider_port_offset is 0 for the default provider (k3s-aws)
ok 292 _acg_provider_port_offset gives distinct non-zero offsets to other providers
ok 293 _acg_provider_port_offset defaults to 0 for unknown providers
ok 294 require-unambiguous-provider refuses when >1 live and provider not explicit
ok 295 require-unambiguous-provider allows >1 live when provider is explicit
ok 296 require-unambiguous-provider allows a single live provider
ok 297 require-unambiguous-provider down allows aws plus hostinger
ok 298 require-unambiguous-provider down refuses two sandboxes plus hostinger
ok 299 require-unambiguous-provider down allows hostinger only
ok 300 require-unambiguous-provider status still refuses aws plus hostinger
ok 301 _acg_normalize_provider normalizes short aliases
ok 302 _acg_provider_context maps providers to app contexts
ok 303 _acg_resolve_provider prefers Hostinger when both providers are reachable
ok 304 _acg_resolve_provider ignores a stale active-provider file
ok 305 _acg_resolve_provider prefers live Hostinger over a stale ACG active-provider file
ok 306 _acg_resolve_provider honors a live Hostinger active-provider file
ok 307 _acg_context_reachable is true when the context answers /readyz
ok 308 _acg_context_reachable is false for an unreachable context
ok 309 _acg_context_reachable is false for an empty context
ok 310 _acg_resolve_provider falls back to k3s-hostinger when nothing is reachable and no file exists
ok 311 _hostinger_set_active_app_cluster is additive by default
ok 312 _hostinger_set_active_app_cluster strips other labels in exclusive mode
ok 313 _argocd_set_active_app_cluster is additive by default
ok 314 _argocd_set_active_app_cluster strips other labels in exclusive mode
ok 315 _hostinger_register_cluster routes through register_app_cluster labels
ok 316 _provider_k3s_hostinger_refresh_cluster reapplies observability and refreshes frontend DNS on the hostinger context
ok 317 _provider_k3s_hostinger_refresh_registration registers only and never touches gitops, edge, or vault
ok 318 _provider_k3s_hostinger_refresh_registration refuses exclusive mode
ok 319 _provider_k3s_hostinger_refresh_registration propagates register failure
ok 320 _hostinger_reapply_gitops_applicationsets reapplies data, services, platform, istio-ambient, and CVE reader appsets from the current branch
ok 321 _hostinger_clear_stale_platform_tracking_ids strips stale basket/product-catalog ownership and refreshes apps
ok 322 _hostinger_reconcile_vault_cluster_store seeds hub Vault data before ExternalSecret reconcile
ok 323 register_app_cluster falls back to insecure tlsClientConfig when CA data is unset
ok 324 register_app_cluster fails closed when managed metadata is incomplete
ok 325 register_app_cluster emits managed labels and annotations when metadata is complete
ok 326 _hostinger_refresh_access_layer restarts argocd port-forward before cloudflared
ok 327 _hostinger_reconcile_vault_cluster_store bootstraps vault-backend when ESO is present
ok 328 _provider_k3d_exec is defined
ok 329 _provider_k3d_cluster_exists is defined
ok 330 _provider_k3d_list_clusters is defined
ok 331 _provider_k3d_apply_cluster_config is defined
ok 332 _provider_k3d_install is defined
ok 333 _provider_k3d_create_cluster is defined
ok 334 _provider_k3d_destroy_cluster is defined
ok 335 _provider_k3d_deploy_cluster is defined
ok 336 _provider_k3d_configure_istio is defined
ok 337 _provider_k3d_expose_ingress is defined
ok 338 _provider_k3s_exec is defined
ok 339 _provider_k3s_cluster_exists is defined
ok 340 _provider_k3s_list_clusters is defined
ok 341 _provider_k3s_apply_cluster_config is defined
ok 342 _provider_k3s_install is defined
ok 343 _provider_k3s_create_cluster is defined
ok 344 _provider_k3s_destroy_cluster is defined
ok 345 _provider_k3s_deploy_cluster is defined
ok 346 _provider_k3s_configure_istio is defined
ok 347 _provider_k3s_expose_ingress is defined
ok 348 _provider_orbstack_exec is defined
ok 349 _provider_orbstack_cluster_exists is defined
ok 350 _provider_orbstack_list_clusters is defined
ok 351 _provider_orbstack_apply_cluster_config is defined
ok 352 _provider_orbstack_install is defined
ok 353 _provider_orbstack_create_cluster is defined
ok 354 _provider_orbstack_destroy_cluster is defined
ok 355 _provider_orbstack_deploy_cluster is defined
ok 356 _provider_orbstack_configure_istio is defined
ok 357 _provider_orbstack_expose_ingress is defined
ok 358 read_lines reads file into array
ok 359 read_lines handles quotes and backslashes
ok 360 read_lines falls back on bash <4 # skip legacy bash not available
ok 361 --prefer-sudo uses sudo when available
ok 362 --prefer-sudo falls back when sudo unavailable
ok 363 --interactive-sudo without a TTY passes -n and the system binary
ok 364 --require-sudo --interactive-sudo without a TTY passes -n and the system binary
ok 365 --require-sudo fails when sudo -n unavailable and no TTY
ok 366 --require-sudo fails when sudo unavailable
ok 367 --probe supports multi-word subcommands
ok 368 --probe escalates to sudo when user probe fails
ok 369 _safe_path: world-writable dir is rejected
ok 370 _safe_path: relative path entry is rejected
ok 371 _safe_path: empty PATH component is rejected
ok 372 _safe_path: standard absolute non-writable dirs pass
ok 373 _safe_path: sticky-bit world-writable dir is rejected
ok 374 _sha256_12 trims digest from argument
ok 375 _sha256_12 reads from stdin when no argument
ok 376 ssh guard: all required aliases present returns silently
ok 377 ssh guard: repairs an emptied config and records warning and secure backup
ok 378 ssh guard: missing fragment or missing alias in fragment leaves config unchanged
ok 379 ssh guard: repair is idempotent and preserves existing config bytes after Include
ok 380 ssh guard: retains only five timestamped backups
ok 381 stale-ref check is executable
ok 382 stale-ref check flags the f03df202 data-layer rename # skip fixture commit f03df202 not reachable in this clone (orphaned by branch cleanup)
ok 383 stale-ref check flags the 4c89dabb trivy split # skip fixture commit 4c89dabb not reachable in this clone (orphaned by branch cleanup)
ok 384 stale-ref check is quiet on a commit that touched no etc files # skip fixture commit e3a75f1f not reachable in this clone (orphaned by branch cleanup)
ok 385 _run_command_resolve_sudo: no sudo flags → plain runner
ok 386 _run_command_resolve_sudo: require_sudo unavailable → returns 127
ok 387 _run_command_resolve_sudo: probe succeeds as user → plain runner
ok 388 _run_command: missing program → exits 127
ok 389 _run_command: succeeds for simple command
ok 390 _run_command: --quiet suppresses error output on missing program
ok 391 _run_command: --interactive-sudo flag is accepted without error
ok 392 _run_command: --prefer-sudo flag is accepted without error
ok 393 system overrides: failure handler redacts inline VAULT_TOKEN commands
ok 394 system.sh shim: _run_command_resolve_sudo is the lib-foundation definition
ok 395 system.sh shim: no-TTY interactive sudo resolves to sudo -n and the system binary
ok 396 system.sh shim: defines only the k3d-manager kubeconform helpers itself
ok 397 system.sh shim: SCRIPT_DIR defaults to the k3d-manager scripts dir
ok 398 system.sh shim: loads with no external commands on PATH
ok 399 test_jenkins trap removes auth file
ok 400 the harness neutralizes the Pushgateway so tests cannot write live metrics
ok 401 POST with wrong token returns 401
ok 402 POST with no auth header returns 401
ok 403 POST with correct token returns 202 and job_id
ok 404 POST body over 4KB returns 413
ok 405 GET /status with invalid job_id (not hex8) returns 400
ok 406 GET /status with invalid job_id containing special chars returns 400
ok 407 GET /status with valid hex8 job_id that does not exist returns 404
ok 408 GET unknown path returns 404
ok 409 POST with missing stage field returns 400
ok 410 POST with invalid stage value returns 400
ok 411 POST with JSON-injection attempt in chart_version queues job safely
ok 412 POST /cluster with provider=gcp returns 202 and job_id
ok 413 POST /cluster with unknown provider defaults to aws (202)
ok 414 POST /cluster-status with correct token returns 202 and job_id
ok 415 POST /cve-remediate requires auth, creates one job, and cooldown-skips repeat
ok 416 webhook hostinger status handler accepts provider dispatch
ok 417 Slack signature verification rejects malformed timestamps and bodies
ok 418 status smoke Keycloak admin login uses the operator keycloak-secrets account
ok 419 Slack ignores signed unknown and user-less commands without creating anchors
ok 420 Slack event larger than 4 KB is verified on the full body
ok 421 Slack event over the Slack cap returns 413
ok 422 Slack reports an authorization failure in the originating command thread
ok 423 Slack allowlisted reader can dispatch cluster-status
ok 424 Slack cluster parser accepts tokens in any order and dry-run isolates execution
ok 425 hostinger status keeps report header and final health sections when long
ok 426 POST /cluster-status with wrong token returns 401
ok 427 POST /cluster-status with reader role returns 202
ok 428 POST /diagnostics with reader role returns 202
ok 429 POST /diagnostics rejects non-approved namespaces
ok 430 POST /diagnostics ArgoCD requests must target hub
ok 431 POST /cluster-refresh with reader role returns 403
ok 432 POST /cluster-refresh with operator role returns 202
ok 433 POST /cluster up with operator role returns 403
ok 434 webhook remote operator access defines policy and audit log
ok 435 webhook diagnostics endpoint is reader-scoped and namespace-guarded
ok 436 webhook analysis uses ordered candidates and a safe sentinel
ok 437 webhook cluster status classifies absent ACG sandboxes explicitly
ok 438 webhook ask subprocess captures transcripts in the k3d-manager run dir
ok 439 webhook ask subprocess ensures the run dir exists before capturing
ok 440 POST /analyze with correct token returns 202 and job_id
ok 441 POST /analyze with wrong token returns 401
ok 442 POST /cluster with response_url stored in job dir
ok 443 POST /cluster with wrong token returns 401
ok 444 POST /cluster with action=up returns 202 and job_id
ok 445 POST /cluster with action=down returns 202 and job_id
ok 446 POST /cluster with invalid action returns 400
ok 447 POST /cluster with missing action returns 400
ok 448 Level 1: POST queues job and GET /status returns job output # skip set K3DM_WEBHOOK_LIVE=1 to enable
ok 449 Level 1: GET /status output field is non-empty after job completes # skip set K3DM_WEBHOOK_LIVE=1 to enable
ok 450 Level 2: POST current chart version returns success without running make up # skip set K3DM_WEBHOOK_LEVEL2=1 to enable (requires cluster)
ok 451 Level 3: tunnel rejects wrong token with 401 # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
ok 452 Level 3: tunnel unknown path returns 404 (auth passes, routing fails) # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
ok 453 Level 3: tunnel POST with real token queues job and returns 202 # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
ok 454 k3dm-ask-bash denies general-purpose interpreters
ok 455 k3dm-ask-bash denies output redirection
ok 456 k3dm-ask-bash denies nested shells and command maskers
ok 457 k3dm-ask-bash allows a plain kubectl read
ok 458 k3dm-ask-bash denies outbound network clients
ok 459 k3dm-ask-bash denies git network subcommands
ok 460 k3dm-ask-bash allows local read-only git inspection
ok 461 k3dm-ask-bash denies credential-dir reads
ok 462 k3dm-ask-bash denies editors and find -exec
ok 463 k3dm-ask-bash denies awk system
ok 464 k3dm-ask-bash denies make in read-only mode
ok 465 webhook role helpers preserve token admin and fail closed
ok 466 webhook fix mode requires operator+ role, not question phrasing
ok 467 webhook _slack_post only targets https Slack hosts
ok 468 hub ESO rows use the hub context and prefix
ok 469 app ESO rows keep legacy names
ok 470 absent ESO CRD is skipped rather than failed
ok 471 kubeconfig error is not reported as not installed
ok 472 absent ESO CRD still reports not installed
not ok 473 smoke test ESO wiring samples app and hub through helper
# (in test file scripts/tests/lib/webhook_hub_eso.bats, line 155)
#   `[ "$status" -eq 0 ]' failed
ok 474 acg_provision prints help with --help
ok 475 acg_provision requires --confirm
ok 476 acg_provision fails when aws credentials invalid
ok 477 acg_status prints help with --help
ok 478 acg_status exits 1 when no instance found
ok 479 acg_extend prints help with --help
ok 480 acg_extend_playwright prints help with --help
ok 481 acg_extend opens browser on macOS
ok 482 acg_extend prints URL on Linux
ok 483 acg_teardown prints help with --help
ok 484 acg_teardown requires --confirm
ok 485 acg_teardown is idempotent when no stack found
ok 486 acg_teardown deletes stack when found
ok 487 agent dispatch dashboard: valid ConfigMap JSON and datasource
ok 488 agent dispatch dashboard: every queried metric is exported
ok 489 agent dispatch dashboard: Claude context and compaction row panels exist below existing rows
ok 490 agent dispatch dashboard: landing success aggregates both sides
ok 491 agent dispatch dashboard: panel rectangles do not overlap
ok 492 agent dispatch dashboard: Codex API cost shows priced total and excluded sessions
ok 493 agent dispatch dashboard: per-spec panels use readable units and grouped targets
ok 494 agent dispatch dashboard: final exit gap and operator coverage are exposed
ok 495 agent dispatch dashboard: window is a query over the exported scopes and defaults to 7d
ok 496 agent dispatch dashboard: rework rate stat reads the selected window
ok 497 agent dispatch dashboard: verified delivery stats use exported metrics without overlap
ok 498 agent dispatch dashboard: stat and bar gauge panels use explicit colours
ok 499 agent dashboards: panel ids exactly match the pre-split dashboard and assigned groups
ok 500 agent dashboards: panel targets, fieldConfig and options match the pre-split fixture
ok 501 agent dashboards: each dashboard has unique panel ids and no overlapping rectangles
ok 502 agent dashboards: all dashboards have the tag-based Agents link
ok 503 agent dashboards: Activity has three time windows and Dispatch and Cost keep the query variable
ok 504 agent activity: Claude row fills the width and bar gauge names read beside each bar
ok 505 agent dispatch: run outcomes read beside each bar, first-pass verification bars with fixed fonts sit beside per run evidence, and each slug links to its spec
ok 506 agent dispatch: failed startup evidence is local-only and the Loki link is scoped to shipped logs
ok 507 agent dispatch: per spec shows which agent landed each spec
ok 508 agent dispatch dashboard: Log opens the filtered run log dashboard
ok 509 agent cost: Claude tokens by kind splits the selected window by cache kind
ok 510 agent cost: daily Claude tokens and cost panels split by kind
ok 511 agent dashboards: labels and titles stay readable and release-only stats say why they are empty
ok 512 agent dispatch dashboard: Per spec exposes unknown worker and coordinator identities
ok 513 agent dispatch dashboard: Per spec shows handoff and measured cost fields within width budget
ok 514 agent dispatch dashboard: Per spec spans the full width and its columns fit without scrolling
ok 515 agent dispatch: blank evidence paths remain visible clickable links and gaps are explicit
ok 516 agent dispatch: unrecorded attribution is labeled without overwriting known identities
ok 517 kube-prometheus-stack values point Alertmanager at the SMTP secret
ok 518 Grafana ServiceMonitors carry the release label Prometheus selects
ok 519 Alertmanager routes Trivy critical CVE alerts to null before SMS
ok 520 Alertmanager sends ACG sandbox criticals to email, not SMS
ok 521 Alertmanager amtool routes ACG sandbox criticals to email # skip amtool is not installed
ok 522 Alertmanager amtool routes HubKineCompactionStalled to email # skip amtool is not installed
ok 523 Alertmanager routes KubeJobFailed to platform-warning
ok 524 Alertmanager platform-warning has a non-empty recipient after envsubst
ok 525 Alertmanager keeps the critical route before platform-warning
ok 526 make alertmanager-secret rejects empty input without calling Vault
ok 527 observability treats empty Alertmanager Vault values as absent
ok 528 Alertmanager config helper applies the secret without exposing the password
ok 529 missing Alertmanager Vault secret fails the helper and public command
ok 530 Alertmanager config helper does not leak credentials into the calling shell
ok 531 Alertmanager template has one render site
ok 532 make alertmanager-config invokes the public command
ok 533 the dashboard is a sidecar-loaded ConfigMap in monitoring with valid JSON
ok 534 the integration variable lists only integrations that have sent something
ok 535 the dashboard names no integration this stack does not use
ok 536 every panel uses the hub Prometheus datasource
ok 537 argocd platform-ops deploy applies the Alertmanager delivery dashboard
ok 538 alert categories and pipeline panels use scoped selectors
ok 539 security, synthetic, and noisiest panel contracts match retention
ok 540 dashboard panel rectangles do not overlap and ids are unique
ok 541 all-skipped run exits 1 with the fatal zero-match diagnostic
ok 542 vulnerable deployed image with vulnerable latest dispatches rebuild instead of promotion
ok 543 rebuild dispatched within the cooldown is skipped without notifying
ok 544 rebuild dispatched after the cooldown expires dispatches and records the time
ok 545 vulnerable deployed image with clean latest promotes exact digest via application patch
ok 546 failed Trivy execution skips promotion and rebuild and hides scanner output
ok 547 malformed Trivy result is unknown and cannot promote
ok 548 empty Trivy output is unknown and cannot promote or rebuild
ok 549 non-auth Trivy execution error is unknown and cannot promote or rebuild
ok 550 Trivy registry transport error is unknown and cannot promote or rebuild
ok 551 missing Trivy binary fails closed
ok 552 valid zero candidate result retains promotion behavior
ok 553 valid CRITICAL candidate finding retains rebuild behavior
ok 554 one unknown candidate does not authorize its promotion in a mixed-service run
ok 555 COSIGN_VERIFY=1: signed clean candidate is cosign-verified then promoted
ok 556 COSIGN_VERIFY=1: unsigned clean candidate is refused (no promotion)
ok 557 COSIGN_VERIFY_ATTESTATION=1: signed + attested clean candidate is promoted
ok 558 COSIGN_VERIFY_ATTESTATION=1: signed but unattested candidate is refused (no promotion)
ok 559 registry-less trivy-operator repository form still matches and promotes
ok 560 digest resolution reads busybox-style indented lowercase headers
ok 561 clean frontend image is scanned and skipped
ok 562 clean payment image is scanned and skipped
ok 563 missing immutable candidate notifies without failing the batch
ok 564 rebuild dispatch failure notifies without failing the batch
ok 565 missing immutable sha candidate notifies without retrying the batch
ok 566 GHCR credential failure is classified and reported without exposing the token
ok 567 latest without a digest is classified no-latest
ok 568 unavailable tags endpoint is not classified as a genuine no-match
ok 569 manifest 404 is rejected even when it includes a digest header
ok 570 manifest 401 with GH_TOKEN is classified auth instead of no-match
ok 571 tags list 401 with GH_TOKEN is classified auth instead of no-match
ok 572 registry transport keeps credentials in a private curl config and scanner image contract is pinned
ok 573 candidate metric groups preserve two services and replace auth with ok per service
ok 574 real curl HEAD returns only the status and writes digest headers separately
ok 575 missing Application logs a failed promotion and returns zero
ok 576 missing Application emits no remediation event
ok 577 successful Application patch emits one remediation event
ok 578 git-persisted promotion clears the live image override
ok 579 live-patch-only promotion keeps the live image override
ok 580 app_cve_scan_trigger rejects an unsupported cronjob name
ok 581 app_cve_scan_trigger fails when the cronjob is absent
ok 582 app_cve_scan_trigger creates a job from the cronjob
ok 583 app_cve_scan_trigger defaults to app-cve-scan with no argument
ok 584 app_cve_scan_trigger returns non-zero when the wait times out
ok 585 app_cve_scan_trigger honours K3DM_CVE_SCAN_WAIT
ok 586 appset deploy derives envsubst vars from each file
ok 587 every appset variable is defaulted in the argocd bootstrap scope
ok 588 browser TLS defaults to the k3s-aws provider-scoped state dir
ok 589 browser TLS dirs differ between k3s-aws and k3s-hostinger
ok 590 explicit browser TLS dir overrides the provider-scoped default
ok 591 browser TLS files are inside the selected directory
ok 592 deploy_argocd --help shows usage
ok 593 ArgoCD credential rotator is namespaced and least privilege
ok 594 ArgoCD rotator bcrypt is runtime-correct and pod excludes istio sidecar
ok 595 deploy_argocd skips when CLUSTER_ROLE=app
ok 596 deploy_argocd_bootstrap --help shows usage
ok 597 deploy_argocd_bootstrap no-ops when skipping all resources
ok 598 deploy_argocd_applicationsets --help shows usage
ok 599 deploy_argocd_applicationsets reapplies then verifies the values-branch pin
ok 600 deploy_argocd_applicationsets --no-verify skips the values-branch check
ok 601 deploy_argocd_applicationsets rejects unknown options
ok 602 _argocd_bootstrap_is_ready returns 0 when AppProject and ApplicationSets exist
ok 603 _argocd_bootstrap_is_ready returns 1 when an ApplicationSet is missing
ok 604 _argocd_ensure_logged_in uses plaintext non-interactive login
ok 605 _argocd_wait_for_local_port_forward returns 0 when healthz is reachable
ok 606 _argocd_wait_for_local_port_forward returns 1 when healthz never becomes reachable
ok 607 _argocd_write_port_forward_wrapper includes a self-healing loop
ok 608 _argocd_write_port_forward_wrapper falls back when the requested context is missing
ok 609 port-forward wrapper scopes listener sweeps and refreshes context
ok 610 _argocd_write_browser_https_wrapper includes a canonical HTTPS listener
ok 611 _argocd_issue_browser_tls_material writes Vault-issued TLS files
ok 612 _argocd_deploy_appproject fails when template missing
ok 613 ARGOCD_NAMESPACE defaults to cicd
ok 614 register_app_cluster: permits token-less in-cluster registration
ok 615 register_app_cluster: in-cluster secret does not match platform-helm
ok 616 register_app_cluster: remote secret keeps platform-helm labels
ok 617 register_app_cluster: requires a token for remote registrations
ok 618 app-cluster registration verification accepts exact identity, provider, and server
ok 619 app-cluster registration verification fails closed on mismatched secret
ok 620 ArgoCD Helm values substitute Keycloak OIDC settings
ok 621 ArgoCD public URL override is passed to Helm independently of routing host
ok 622 register_app_cluster: shopping-cart label defaults to false
ok 623 register_app_cluster: shopping-cart label opts in when explicitly true
ok 624 register_app_cluster: rejects a non-boolean shopping-cart value
ok 625 _argocd_deploy_applicationsets surfaces the kubectl error when an apply fails
ok 626 _argocd_deploy_applicationsets returns success when every apply lands
ok 627 ACG deregistration leaves observability-acg in place and is repeatable
ok 628 argocd app cluster generator: no static ubuntu-k3s ApplicationSet destination remains
ok 629 argocd app cluster generator: services-git uses matrix clusters label selector
ok 630 argocd app cluster generator: data-git exists and targets shopping-cart-data
ok 631 argocd app cluster generator: data-git ignores controller-injected volumeClaimTemplates fields
ok 632 argocd app cluster generator: data-git requires the shopping-cart opt-in label
ok 633 argocd app cluster generator: services-git requires the shopping-cart opt-in label
ok 634 argocd app cluster generator: eso and acg dashboards stay opt-in-free so the hub keeps them
ok 635 services-git selects the exact e2e Stripe overlays
ok 636 hostinger registration sets the k3s-hostinger provider label
ok 637 an explicit provider override still wins
ok 638 register_app_cluster warns when the provider is unset
ok 639 hostinger registration sets the shopping-cart label by default
ok 640 an explicit shopping-cart override still wins
ok 641 register_app_cluster keeps the false shopping-cart default
ok 642 registration defaults the e2e profile to none
ok 643 missing secret and present context dispatches the row provider
ok 644 present secret does not dispatch
ok 645 missing kubeconfig context is skipped successfully
ok 646 dispatcher failure keeps reconcile successful and emits a gap banner
ok 647 exclusive mode refuses to reconcile
ok 648 comment header and blank lines are skipped
ok 649 platform AppProject has no orphaned-resource monitoring
ok 650 shopping-cart AppProject has no orphaned-resource monitoring
ok 651 AppProjects retain required project fields
ok 652 k3s provider wins over generic live CNI dirs
ok 653 orbstack provider wins over live CNI dirs
ok 654 usable live CNI dirs remain the fallback
ok 655 no source emits no CNI override and returns zero
ok 656 k3s refuses generic CNI dirs
ok 657 generic live dirs are refused for a k3d target
ok 658 an unknown provider warns that generic dirs are being written
ok 659 live APP_CLUSTER_NAME override remains unchanged
ok 660 provider is resolved for the live destination, not the shell APP_CLUSTER_NAME
ok 661 non-JSON live read still returns zero
ok 662 ApplicationSet logging says resolved overrides
ok 663 ApplicationSet reapply preserves live destination and CNI dirs
ok 664 ApplicationSet reapply uses CNI resolver when no live set exists
ok 665 ApplicationSet reapply keeps CNI environment defaults without a provider label
ok 666 ApplicationSet reapply ignores live values when requested
ok 667 ApplicationSet reapply leaves sets without live overrides untouched
ok 668 observability ACG set targets provider-limited app clusters and preserves release names
ok 669 appsets reapply retires legacy ACG Applications immediately before only that set
ok 670 appsets reapply confirmation: retries until the values branch passes
ok 671 appsets reapply confirmation: final stale output is shown after timeout
ok 672 appsets reapply confirmation: invalid timing values fall back to the defaults
ok 673 appsets reapply confirmation: does not wait when the first check passes
ok 674 appsets reapply confirmation: --no-verify skips the check
ok 675 appsets reapply confirmation: dry-run skips the check
ok 676 appset rollout stage: every manifest has a valid stage label
ok 677 appset rollout stage: hub applies before app-cluster
ok 678 appset rollout stage: direct deploy prepares when no stage is supplied
ok 679 appset rollout stage: failed hub confirmation prevents app-cluster apply
ok 680 appset rollout stage: hub applies only the hub stage
ok 681 appset rollout stage: unlabelled manifest aborts before apply
ok 682 appset rollout stage: confirmation checks only its owners
ok 683 appset rollout stage: Degraded owned Application fails hub confirmation
ok 684 appset rollout stage: all confirms and applies app-cluster after hub
ok 685 appset rollout stage: owners matching nothing fails closed
ok 686 appset rollout stage: a stage with no manifests fails instead of checking every Application
ok 687 appset rollout stage: an unknown stage refuses before preparing
ok 688 argocd.sh has no shared browser listener log default
ok 689 argocd.sh has no shared browser listener wrapper default
ok 690 cluster-up keeps the per-provider browser listener log fallback
ok 691 _argocd_deploy_key_policy_hcl includes deploy key paths
ok 692 _argocd_deploy_key_policy_hcl uses read capability
ok 693 _argocd_deploy_key_policy_hcl avoids write/delete
ok 694 configure_vault_argocd_repos errors when namespace missing
ok 695 configure_vault_argocd_repos errors when ESO CRDs missing
ok 696 configure_vault_argocd_repos --dry-run makes no kubectl calls
ok 697 configure_vault_argocd_repos --seed-vault writes placeholders
ok 698 configure_vault_argocd_repos --dry-run --seed-vault prints actions only
ok 699 image-updater: image-list annotation is absent
ok 700 image-updater: digest auto-update strategy is absent
ok 701 image-updater: argocd write-back method is absent
ok 702 image-updater: shopping-cart apps are no longer hard enrolled
ok 703 services-git ApplicationSet ignores kustomize image overrides via jqPathExpressions
ok 704 product-catalog kustomization declares an image override anchor
ok 705 image-updater install: deploy function defined
ok 706 image-updater install: targets image-updater config dir
ok 707 image-updater install: applies kustomize dir
ok 708 image-updater install: honors ARGOCD_SKIP_IMAGE_UPDATER
ok 709 image-updater install: invoked from post-deploy bootstrap
ok 710 image-updater pull-secret: ensure function defined
ok 711 image-updater pull-secret: ensure invoked before install
ok 712 image-updater pull-secret: secret created in ARGOCD_NAMESPACE
ok 713 image-updater pull-secret: credentials point at cicd
ok 714 image-updater pull-secret: no shopping-cart-apps reference in kustomization
ok 715 loki: observability-acg includes a loki application
ok 716 loki: hub observability includes a loki application
ok 717 loki: hub observability forces the helm release name back to loki
ok 718 loki: values pin monolithic filesystem mode
ok 719 loki: hub grafana provisions a loki datasource
ok 720 loki: promtail ships pod logs to Loki
ok 721 loki: observability deploy applies promtail manifest
ok 722 loki: hub observability deploy applies the argocd image updater dashboard
ok 723 metrics: serviceMonitor enabled for all four components
ok 724 metrics: prometheus-operator discovery label present per component
ok 725 metrics: dashboard ConfigMap carries grafana sidecar label
ok 726 metrics: dashboard targets monitoring namespace
ok 727 metrics: dashboard applied from argocd.sh platform-ops deploy
ok 728 metrics: dashboard includes image updater deployment readiness panels
ok 729 metrics: dashboard focuses sync activity on watched apps and infra services
ok 730 alerts: argocd rules cover degraded, out-of-sync, and image flapping for watched apps
ok 731 alerts: alertmanager routes argocd and image-updater alert names to the webhook analyzer
ok 732 metrics: dashboard includes image-updater stat tiles from loki processing results
ok 733 metrics: dashboard includes app-cve-scan job and decision visibility
ok 734 metrics: dashboard includes trivy infra security panels
ok 735 metrics: dashboard has exactly one trivy drilldown table and banner
ok 736 metrics: dashboard banner uses real newlines not literal backslash-n
ok 737 metrics: loki logs panel filters the app-cve-scan stream; other loki panels are stat/graph
ok 738 deploy_argocd_bootstrap invokes deploy_argocd_platform_ops
ok 739 the platform-ops bootstrap call is guarded so it cannot abort the bootstrap
ok 740 argocd reclaim ownership: plan strips foreign ownership from release objects
ok 741 argocd reclaim ownership: plan separates removable and review-only orphans
ok 742 argocd reclaim ownership: dry run reports without changing objects
ok 743 argocd reclaim ownership: confirm patches, removes tracking, and deletes only serviceaccounts
ok 744 argocd reclaim ownership: failed patch leaves tracking label untouched
ok 745 argocd reclaim ownership: unreadable objects return 2
ok 746 argocd reclaim ownership: unknown option returns 2
ok 747 data-git preserves generated resources and keeps its generator contract
ok 748 re-registration carries an existing app-cluster role into the manifest
ok 749 first-time registration applies the cluster secret without a role label
ok 750 a failed real kubectl role lookup still applies the cluster secret
ok 751 _argocd_ensure_servicemonitors renders with api-versions and applies only ServiceMonitors
ok 752 _argocd_ensure_servicemonitors is a no-op when the ServiceMonitor CRD is absent
ok 753 deploy_argocd_bootstrap calls _argocd_deploy_image_updater
ok 754 pin is nonempty and deploy path pins chart
ok 755 dry run snapshots baseline without upgrade or apply
ok 756 equal target exits without helm upgrade
ok 757 unknown version and unreachable context stop before upgrade
ok 758 older target is refused without downgrade flag
ok 759 upgrade writes after snapshot and invokes chart deploy helper
ok 760 degraded baseline Application fails postcheck and prints rollback hint
ok 761 a context other than the hub stops before any helm call
ok 762 an Application missing after the upgrade fails the postcheck
ok 763 dry run prints the deploy helper's values and set flags
ok 764 argocd values branch: reports drift and returns 1 when an Application is stale
ok 765 argocd values branch: the up-to-date Application is not reported as drifted
ok 766 argocd values branch: separates stale and degraded applications
ok 767 argocd values branch: returns 0 when every Application matches
ok 768 argocd values branch: owners are included in the success scope
ok 769 argocd values branch: returns 2 instead of a false green when Applications cannot be read
ok 770 argocd values branch: chart sources without the k3d-manager repo are ignored
ok 771 argocd values branch: unparseable input fails closed
ok 772 argocd values branch: zero k3d-manager references fails closed
ok 773 argocd values branch: manifest sources without ref are checked
ok 774 argocd values branch: HEAD sources are ignored as tracking sources
ok 775 argocd values branch: without owners Degraded Applications remain unreported
ok 776 argocd values branch: counter reports checked and ignored HEAD references
ok 777 argocd values branch: dry-run skips confirmation
ok 778 vectordb ApplicationSet is hub-scoped without an app-cluster selector
ok 779 vectordb uses the pinned pgvector pg17 image and not latest
ok 780 vectordb defines no Role, RoleBinding, or ClusterRole
ok 781 vectordb destination and manifests use namespace vectordb, never default
ok 782 vectordb credentials use secretKeyRef and never plaintext trust auth
ok 783 vectordb ExternalSecret uses vault-backend and vectordb/postgres
ok 784 vectordb destination is permitted by the platform AppProject
ok 785 vectordb Application template enables server-side diff
ok 786 vectordb ApplicationSet retains server-side apply and masks no differences
ok 787 the ESO Vault policy grants the prefix the vectordb ExternalSecret reads
ok 788 vectordb Vault seed function is defined
ok 789 bootstrap seeds vectordb before deploying the AppProject
ok 790 vectordb Vault seed checks for an existing secret before putting
ok 791 vectordb Vault seed sends generated credentials on stdin, not argv
ok 792 vectordb Vault seed generates the value from urandom inside remote sh
ok 793 vectordb Vault seed pins the secret KV mount on get and put
ok 794 aws_import_credentials parses simple CSV (Access key ID,Secret access key)
ok 795 aws_import_credentials parses CSV with User name column
ok 796 aws_import_credentials parses quoted export values
ok 797 aws_import_credentials returns 1 on unparseable input
ok 798 aws_import_credentials --help exits 0
ok 799 deploy_cert_manager fails when ACME_EMAIL is unset
ok 800 deploy_cert_manager --help prints usage
ok 801 _cert_manager_helm_install skips repo ops for local chart path
ok 802 _cert_manager_apply_issuer renders staging ClusterIssuer
ok 803 _cert_manager_apply_issuer renders production ClusterIssuer
ok 804 _cert_manager_apply_issuer fails when ACME_EMAIL empty
ok 805 deploy_cert_manager warns for production on k3d
ok 806 deploy_cert_manager warns for production on orbstack
ok 807 deploy_cert_manager --skip-issuer avoids ClusterIssuer apply
ok 808 deploy_cert_manager --skip-issuer waits for webhook only
ok 809 copilot_triage_pod prints help with --help
ok 810 copilot_triage_pod fails when namespace is missing
ok 811 copilot_triage_pod fails when pod is missing
ok 812 copilot_triage_pod fails when K3DM_ENABLE_AI is not 1
ok 813 copilot_triage_pod invokes _ai_agent_review with kubectl context
ok 814 copilot_draft_spec prints help with --help
ok 815 copilot_draft_spec fails when description is missing
ok 816 copilot_draft_spec fails when K3DM_ENABLE_AI is not 1
ok 817 copilot_draft_spec invokes _ai_agent_review with git context
ok 818 cve scan reads the Hub chart label from argocd-server
ok 819 cve scan does not create or patch an infra cluster-secret stage
ok 820 cve scanner is authorized only to read the Hub deployment
ok 821 cve scan runs end-to-end with wget, kubectl and trivy
ok 822 cve scan treats no newer chart as a finding, but lookup failure as fatal
ok 823 cve scan downloads kubectl when absent
ok 824 cve scanner has no curl invocation
ok 825 cve scan holds major chart upgrades but patches same-major ones
ok 826 cve scan cronjob gives trivy a writable HOME
ok 827 DR rules: failed and stale alerts are warning alerts in dr.alerts
ok 828 DR rules: rendered Alertmanager routes both alerts to platform-warning
ok 829 freshness: fresh successful run passes
ok 830 freshness: exact eight-day boundary passes
ok 831 freshness: stale successful run fails with timestamp, age, cutoff and next steps
ok 832 freshness: latest failed result has distinct diagnostic
ok 833 freshness: no valid result has distinct diagnostic without payload
ok 834 freshness: chooses newest valid run timestamp instead of filename order
ok 835 freshness: workflow uses installed data-repo script and how-to documents synchronization
ok 836 every substrate pod spec disables service links
ok 837 e2e_verify_vcluster is a public function (no leading underscore)
ok 838 e2e_verify_sandbox is a public function (no leading underscore)
ok 839 sandbox verification uses hub profile flow without vault, helm, envsubst or appset apply
ok 840 sandbox checks hub Applications before provisioning secrets
ok 841 sandbox provisions Keycloak credentials before enabling Stripe
ok 842 sandbox phase checks hub before extending it
ok 843 hub preflight names E2E_HUB_CONTEXT when it is set
ok 844 hub Applications require Synced and Healthy
ok 845 hub Applications re-poll until they converge
ok 846 hub Applications fail after a persistent unhealthy poll
ok 847 empty hub Applications fail without waiting
ok 848 hub Applications default window outlasts two ArgoCD reconciles
ok 849 stripe profile is set before rollout and reset after the run
ok 850 profile cleanup runs after Playwright failure
ok 851 keycloak credentials are deleted on the normal (non-trap) path
ok 852 cleanup delete does not wait on a lost watch
ok 853 sandbox job manifest exports OAuth2 and Stripe mode before Job creation
ok 854 sandbox Job uses the real Tier 2 Service hostnames
ok 855 sandbox Job preserves all four service ports
ok 856 sandbox Job command emits result markers and preserves Playwright status
ok 857 sandbox summary parser extracts marked Playwright results
ok 858 sandbox preflight creates both Secrets before completion
ok 859 sandbox preflight is idempotent
ok 860 sandbox preflight rejects a missing Stripe Keychain item
ok 861 sandbox preflight never places the Stripe key in kubectl argv
ok 862 sandbox summary carries the sandbox tier and Stripe project
ok 863 Tier 1 summary defaults remain vcluster and api+flows
ok 864 sandbox port attribution covers order 8081 and product-catalog 8082
ok 865 failure groups carry routed services
ok 866 failure details are redacted in summary and failures file
ok 867 auth classification survives the bash summary path
ok 868 e2e.sh sources cleanly under set -euo pipefail
ok 869 job manifest sets all four ClusterIP service URLs and OAUTH2 disabled
ok 870 latest E2E image defaults both runner manifests to Always
ok 871 immutable E2E image tags default both runner manifests to IfNotPresent
ok 872 explicit E2E image pull policy overrides tag-derived default
ok 873 invalid E2E image pull policy is rejected
ok 874 vcluster Job manifest wires the five Keycloak settings without a password literal
ok 875 payment is pinned in the E2E substrate kustomization
ok 876 substrate image inventory includes the pinned payment image
ok 877 datastore secret includes a payment encryption key without echoing it
ok 878 substrate rollout waits for payment
ok 879 datastore secret includes the RabbitMQ password
ok 880 substrate waits for RabbitMQ before payment
ok 881 payment RabbitMQ password is secret-backed and substrate renders the broker
ok 882 substrate provisions Keycloak before apply and waits before payment
ok 883 Keycloak secret value only appears in the create-secret argv
ok 884 Keycloak substrate renders and its realm JSON parses
ok 885 payment substrate renders offline
ok 886 substrate bundle is applied via kustomize (-k scripts/etc/e2e)
ok 887 successful job -> exit 0 and vcluster torn down
ok 888 failed job -> non-zero exit but vcluster still torn down (teardown on failure)
ok 889 substrate diagnostics capture pods, events and per-deployment logs
ok 890 substrate diagnostics no-op without a vCluster name
ok 891 exit trap dumps diagnostics before teardown
ok 892 teardown removes orphaned kubeconfig and transient log when destroy is incomplete
ok 893 a JSON summary with the gate-consumable keys is written
ok 894 E2E_RUNNER overrides the default runner in the summary
ok 895 failed job summary is exit-code-faithful (result fail, non-zero exit_code)
ok 896 summary writes a bounded ANSI-stripped failure sidecar from nested results
ok 897 summary writes an empty failure sidecar when results are missing
ok 898 vCluster readiness gate probes /readyz before applying the substrate
ok 899 readiness gate honours E2E_VCLUSTER_READY_TIMEOUT and fails when never ready
ok 900 readiness gate always probes at least once even if the deadline has already passed
ok 901 readiness probe is soft (--no-exit) so a not-ready probe cannot exit the harness
ok 902 readiness gate refreshes the proxy connection between failed probes
ok 903 result event ConfigMap carries the e2e-result labels and a boolean passed field
ok 904 result event carries the runner label/field from the summary
ok 905 failed run publishes passed=false in the result event
ok 906 missing summary -> writer is a no-op that does not fail the run
ok 907 e2e.sh passes shellcheck at warning severity
ok 908 result event publish passes --no-exit so a hub failure cannot exit the shell
ok 909 result event prune passes --no-exit so a hub failure cannot exit the shell
ok 910 result event prune survives a failed stale-event delete
ok 911 substrate Keycloak realm lists realm roles as an array
ok 912 substrate Keycloak e2e-user has a complete Keycloak 24 user profile
ok 913 exit trap tears down the vCluster even when the result event publish exits the shell
ok 914 exit trap writes the summary before the teardown that precedes the publish
ok 915 e2e_prune_images is a public function (no leading underscore)
ok 916 e2e_prune_images --help prints usage and exits 0
ok 917 e2e_prune_images rejects a non-integer --days
ok 918 _e2e_kustomization_images pairs newName with newTag from the real substrate
ok 919 _e2e_kustomization_images skips an entry that has newTag but no newName
ok 920 _e2e_substrate_images unions kustomize overrides with literal manifest images
ok 921 _e2e_image_epoch parses a docker CreatedAt timestamp
ok 922 _e2e_image_epoch returns non-zero on an unparseable timestamp
ok 923 dry run flags an old unprotected image and removes nothing
ok 924 dry run does not flag a pinned substrate image even when old
ok 925 exporter declares the e2e reader and label selector
ok 926 Hermes dashboard exposes current findings and history
ok 927 Hermes dashboard exposes failure evidence and status meanings
ok 928 exporter emits all five e2e_* gauges
ok 929 exporter emits grouped e2e failure metric and dashboard table
ok 930 exporter emits test-level failure metric and dashboard table
ok 931 exporter normalizes nested JSON and skips invalid E2E payloads
ok 932 exporter labels e2e gauges with the runner dimension
ok 933 exporter synthesizes one failure group for a test-less failed run
ok 934 embedded exporter.py compiles cleanly
ok 935 exporter RBAC is not widened (still get,list on configmaps only)
ok 936 exporter maps UNKNOWN Trivy severity from CVSS score
ok 937 exporter exposes report creation timestamps without inventing missing values
ok 938 exporter preserves remediation cache when refresh fails
ok 939 terminal remediation outcomes are excluded from current status
ok 940 e2e dashboard CM parses and its embedded JSON references e2e_* metrics
ok 941 E2E failure metrics carry run provenance and matching current status
ok 942 E2E fixed status requires a later pass with identical run dimensions
ok 943 E2E tables share owner-service filters and exact run ID selection
ok 944 prometheusrule defines the e2e alerts group and all alerts
ok 945 e2e alerts aggregate away the scrape target and name the exported service
ok 946 e2e staleness is fresh if any runner passed recently # skip promtool not installed
ok 947 E2EResultsMissing fires only when the hub has no e2e results # skip promtool not installed
ok 948 argocd platform-ops deploy applies the e2e dashboard
ok 949 Alertmanager has a non-null severity warning route
ok 950 Alertmanager warning catch-all follows the named allowlist
ok 951 e2e runs carry a run date and say whether a failure was fixed later
ok 952 public runner functions are dispatchable (no leading underscore)
ok 953 e2e_remote.sh sources cleanly under set -euo pipefail
ok 954 eval_gates accepts a healthy runner
ok 955 eval_gates reports docker_down when Docker is unresponsive
ok 956 eval_gates reports busy when the runner lock is held
ok 957 eval_gates fails when the mean CPU idle is below the floor
ok 958 one dipped sample does not refuse a mostly idle runner
ok 959 eval_gates refuses a blob with no CPU samples
ok 960 preflight retry retries capacity refusal and then succeeds
ok 961 preflight retry does not retry busy refusal
ok 962 preflight retry stops after the configured capacity retries
ok 963 dispatch uses retry preflight and probe takes six top samples
ok 964 eval_gates fails on low memory
ok 965 eval_gates fails on low disk
ok 966 eval_gates treats missing metrics as a capacity stop, not available
ok 967 num_lt compares decimals
ok 968 SSH options never weaken host verification and keep BatchMode
ok 969 remote SSH command injects the homebrew+local PATH so tools resolve
ok 970 preflight reports unreachable when the probe yields nothing
ok 971 preflight surfaces the pure gate verdict from a live probe
ok 972 cluster reconcile refuses to operate on the hub cluster name
ok 973 cluster reconcile targets the dedicated runner context, never the hub
ok 974 bootstrap returns unreachable without mutating when SSH is down
ok 975 valid_digest accepts empty, bare, and repo-qualified sha256 digests
ok 976 valid_digest rejects malformed or injection-y digests
ok 977 runner_allowed enforces the allowlist
ok 978 dispatch rejects a runner outside the allowlist
ok 979 denied runners get the right redirect at every allowlist entry point before work starts
ok 980 unknown denied runner keeps allowlist error and allowlisted names stay permitted
ok 981 dispatch rejects an invalid digest
ok 982 dispatch refuses to run and never falls back locally when preflight fails
ok 983 dispatch reports the held lock holder and preserves the lock
ok 984 dispatch builds the correct remote command and records a transcript
ok 985 dispatch streams the GHCR token on stdin and not in the command string
ok 986 the dispatch transcript never contains the GHCR token
ok 987 dispatch returns the remote exit code when a token is streamed
ok 988 dispatch sends an empty credential when no token source is available
ok 989 an empty forwarded credential is treated as absent by the env resolver
ok 990 the token resolver never prints the token value
ok 991 dispatch refuses an unpushed SHA before SSH
ok 992 dispatch refuses a malformed runner repository URL
ok 993 dispatch uses an explicit runner repository override
ok 994 dispatch returns the remote exit code unchanged
ok 995 publish-back host loads from the operator conf file and env wins
ok 996 publish-back conf ignores shell metacharacters and warns when absent
ok 997 dispatch copies remote result files and preserves a non-zero exit code
ok 998 make e2e-remote requires RUNNER and wires to the dispatcher
ok 999 publish_build accepts a valid m2 payload and emits a deterministic name
ok 1000 publish_build accepts a real null-heavy summary (no digest, unparsed results)
ok 1001 publish_build rejects the local-m4 runner (local publishes itself)
ok 1002 publish_build rejects unexpected keys (namespace/kubeconfig/labels injection)
ok 1003 publish_build rejects missing required fields
ok 1004 publish_build rejects a malformed digest and a bad exit code
ok 1005 publish_build rejects an invalid result value
ok 1006 publish_build rejects non-JSON payloads
ok 1007 e2e_result_publish applies to the hub context and audits the outcome
ok 1008 e2e_result_publish rejects an empty stdin payload
ok 1009 e2e_result_publish rejects a bad payload and does not apply
ok 1010 publisher install builds a restricted forced-command authorized_keys entry
ok 1011 publisher install refuses a non-key file
ok 1012 remote path never exfiltrates M4 kubeconfig, Vault, or Cloudflare secrets
ok 1013 public failure/ops functions are dispatchable (no leading underscore)
ok 1014 lock token carries only owner/pid/ts and no shell metacharacters
ok 1015 the runner lock is a directory (atomic mkdir), probed with -e
ok 1016 lock acquire records the owner token via mkdir + meta
ok 1017 lock release only removes when the owner meta matches (never blind rm)
ok 1018 dispatch refuses and never falls back locally when the lock is held
ok 1019 dispatch chains publish-back after E2E and returns zero after lock release
ok 1020 dispatch preserves a nonzero SSH exit after tee and failed result copy
ok 1021 newest_summary returns the latest run json and skips retention markers
ok 1022 synth_summary writes a schema-valid failed summary carrying the exit code
ok 1023 synth_summary clamps an out-of-range exit code
ok 1024 publish_back_push fails when no M4 target is configured
ok 1025 publish_back_push uses the dedicated key and streams the file over stdin
ok 1026 publish_back synthesizes a summary when the run left none, and returns 0
ok 1027 publish_back retains a publication_pending marker when M4 is unavailable
ok 1028 publish_replay pushes retained results and renames them published, idempotently
ok 1029 publish_replay reports still-pending (non-zero) when a push fails
ok 1030 M4 replay enforces the allowlist and the reachability guard
ok 1031 M4 replay drives the remote publish_replay when the runner is reachable
ok 1032 M4 republish keeps the newest result per service and tier in run order
ok 1033 M4 republish continues after a publish failure
ok 1034 M4 republish treats a failed fetch as nothing to do
ok 1035 M4 republish enforces the allowlist and reachability guard
ok 1036 unlock reports nothing to clear when no lock is present
ok 1037 unlock refuses while an E2E run is still active
ok 1038 unlock refuses a fresh (not-yet-stale) lock
ok 1039 unlock clears a stale lock past the max age with no live run
ok 1040 unlock enforces the allowlist
ok 1041 health reports a hub outage as critical, distinct from runner state
ok 1042 health is ok when the hub is up and the runner is available
ok 1043 an unavailable runner is a warning, but critical when a run was requested
ok 1044 the failure path never auto-restarts OrbStack, deletes a cluster, or blind-clears the lock
ok 1045 make targets wire the failure/ops entry points
ok 1046 preflight fails when _ACG_SANDBOX_URL is empty
ok 1047 preflight refuses to run when K3DM_ACG_SKIP_SESSION_CHECK is set
ok 1048 preflight reads no credential when it refuses on K3DM_ACG_SKIP_SESSION_CHECK
ok 1049 preflight fails when the credential entry is absent
ok 1050 preflight fails when the entry exists but the login keychain is locked
ok 1051 preflight fails when the entry exists but the stored value is empty
ok 1052 preflight still fails when the credential is unreadable but the profile dir EXISTS
ok 1053 preflight fails when only the username account is readable
ok 1054 preflight loads both credential accounts by name
ok 1055 preflight leaks no credential value into its output
ok 1056 preflight prints no placeholder credential command
ok 1057 preflight arms the fail-closed credential gate for the session check
ok 1058 preflight arms the fail-closed gate as an exported variable
ok 1059 preflight passes when url, credentials and env are all sane
ok 1060 make e2e-sandbox wires to the sandbox dispatcher and passes DIGEST through
ok 1061 sandbox preview reports a ready cluster without making changes
ok 1062 sandbox preview reports an absent cluster without making changes
ok 1063 sandbox preview loads the ACG plugin for the sandbox URL
ok 1064 sandbox preview stops on ACG auth failure
ok 1065 sandbox preview stops on hub failure
ok 1066 cluster preflight fails when the sandbox kubecontext is absent
ok 1067 cluster preflight does not match a context by prefix
ok 1068 cluster preflight fails when the context exists but the API server is dead
ok 1069 cluster preflight passes when the context exists and answers readyz
ok 1070 cluster preflight runs before the sandbox extension burns a browser step
ok 1071 hub preflight uses the default context and rejects an unavailable hub
ok 1072 hub preflight honors E2E_HUB_CONTEXT
ok 1073 provision readiness reuses a healthy sandbox without calling make
ok 1074 provisioning calls make up only for the k3s-aws provider
ok 1075 provisioning refuses a non-k3s-aws provider before make
ok 1076 provisioning failure is reported by the provisioning step
ok 1077 provisioning orchestration checks auth and hub before provisioning
ok 1078 cluster preflight finds ubuntu-k3s when more contexts follow it in the listing
ok 1079 provision readiness finds ubuntu-k3s when more contexts follow it in the listing
ok 1080 hub app convergence recovers frontend after product-catalog becomes healthy
ok 1081 M1: authorized run with absent context provisions with exact command, then continues
ok 1082 M1b: authorized run with context present but failing /readyz also provisions
ok 1083 M2: healthy ubuntu-k3s is reused and nothing is provisioned
ok 1084 M3: provisioning failure is recorded as phase provisioning-sandbox, not preflight
ok 1085 N1: no E2E_SANDBOX_PROVISION means no provisioning
ok 1086 N1b: E2E_SANDBOX_PROVISION=0 and empty do not authorize provisioning
ok 1087 N2a: credential preflight failure means no provisioning
ok 1088 N2b: hub preflight failure means no provisioning
ok 1089 N3: no provisioning on a CLUSTER_PROVIDER other than k3s-aws
ok 1090 N4: failed provisioning step is never reported as success
ok 1091 deploy_eso -h shows usage
ok 1092 Skips install if ESO already present
ok 1093 Fresh install
ok 1094 Skips Helm install if ESO is externally managed
ok 1095 Local ESO chart skips repo add
ok 1096 gcp_login --help exits 0
ok 1097 gcp_login skips gcloud when already active account
ok 1098 gcp_login uses config set when account in store but not active
ok 1099 gcp_login calls gcloud auth login when playwright available
ok 1100 gcp_login falls back to manual gcloud when node unavailable
ok 1101 gcp_login returns 1 when account not set
ok 1102 gcp_login returns 1 when gcloud not found
ok 1103 gcp_get_credentials calls _ensure_node when node is missing
ok 1104 gcp_login.js passes node --check
ok 1105 acg dashboard appset targets app-cluster role
ok 1106 acg dashboard appset syncs the dashboards directory
ok 1107 acg dashboard appset excludes hub collisions by server
ok 1108 acg dashboard appset renders the checkout dashboard exclusion only for the hub
ok 1109 acg dashboard appset checkout exclusion guard rejects a missing filename
ok 1110 acg dashboard appset does not manage the hub-owned k3dm tests dashboard
ok 1111 acg dashboard appset collision guard rejects a missing exclude
ok 1112 acg dashboard appset collision guard rejects a name-keyed condition
ok 1113 acg dashboard appset collision guard derives a second platform collision
ok 1114 hub dashboard appset includes all grafana-dashboard configmaps
ok 1115 hub dashboard appset imports the k3dm tests dashboard
ok 1116 k3dm tests dashboard uses the hub Prometheus datasource
ok 1117 k3dm tests failing-suite table has human-readable columns
ok 1118 k3dm tests dashboard preserves failed cases across the selected range
ok 1119 both dashboard appsets self-heal
ok 1120 Checkout Load Test CPU saturation uses a window that spans several scrapes
ok 1121 observability plugin applies both dashboard appsets
ok 1122 CVE remediation outcome panels preserve the affected service
ok 1123 Grafana Overview uses readable request labels
ok 1124 Grafana Overview dashboard count names what it counts
ok 1125 hub Grafana Overview uses the same readable dashboard contract
ok 1126 readable Overview title does not collide with the stock Grafana Overview
ok 1127 Grafana Health dashboard has a fixed uid and k3dm tags
ok 1128 Grafana Overview Build Info panels use the positive table contract
ok 1129 Grafana Bugs table title is filterable and preserves query selectors
ok 1130 Grafana Bugs table contract rejects an unfilterable title and missing selector
ok 1131 Grafana Overview Build Info panels stay byte-identical
ok 1132 Grafana Overview query panels use live metrics and rate interval
ok 1133 Grafana Overview Firing Alerts and Request Rate panels stay byte-identical
ok 1134 Grafana Overview Firing Alerts by Category panels satisfy the table contract
ok 1135 active alert instances use a dash for missing labels in both dashboards
ok 1136 Grafana Overview panel expressions have balanced PromQL parentheses
ok 1137 Grafana Overview expression guard rejects an unbalanced mutation
ok 1138 Grafana Overview firing instance detail contract is safe and preserves category counts
ok 1139 Grafana Overview CVE report-time panels stay synchronized and bounded
ok 1140 Grafana Overview firing instance fixtures preserve per-instance context and safe fallbacks
ok 1141 Grafana Overview firing instance regression rejects the pre-fix missing detail panel
ok 1142 Grafana Overview panels do not overlap
ok 1143 Grafana Overview category mutation rejects a missing Trivy category
ok 1144 Grafana Overview category mutation rejects a time-series format
ok 1145 Grafana Overview query mutation rejects a fixed one-minute window
ok 1146 Grafana Overview query mutation rejects the removed alert metric
ok 1147 Grafana Overview query mutation rejects missing alert exclusion
ok 1148 Grafana Overview query mutation rejects the old Request Rate description
ok 1149 Grafana Overview Build Info mutation guards reject a missing include
ok 1150 Grafana Overview Build Info mutation guards reject an extra include name
ok 1151 Grafana Overview Build Info mutation guards reject missing width overrides
ok 1152 k3dm tests dashboard shows the latest run classification
ok 1153 k3dm tests freshness stats aggregate to one latest value
ok 1154 every provisioned Grafana dashboard carries at least one tag
ok 1155 every dashboard refreshes every five minutes by default
ok 1156 bug dashboard is valid JSON with uid and Prometheus datasource
ok 1157 release forecast panels align by version and map dates and states
ok 1158 release cadence panel names the median tag gap and explains cadence
ok 1159 target state names the blocked milestone and reason
ok 1160 remaining releases table shows a not-before column
ok 1161 bug dashboard has a release variable
ok 1162 bug dashboard has a repo variable and scopes every bug selector
ok 1163 bug dashboard has a verified filter
ok 1164 bug dashboard defaults to Auto current release and keeps Manual selection
ok 1165 Auto bug filtering follows the repo-scoped current-release metric
ok 1166 release dropdown and table use version-order labels
ok 1167 Auto and Manual modes filter every filed-in bug summary and the table
ok 1168 release summary tiles follow mode while repository-wide tiles do not
ok 1169 bug dashboard separates filed-in and fixed-in release views
ok 1170 every bug metric queried by dashboard is emitted
ok 1171 bug dashboard panels have non-overlapping positions inside 24 columns
ok 1172 release forecast sits between the plan tiles and the Plans table, and lists only unshipped milestones for the selected release
ok 1173 plan titles link to the plan doc with redundant Plan hidden, and bug tiles say bugs
ok 1174 bug dashboard release plans row shows joined plan state without not-started inference
ok 1175 bug dashboard Plans table orders plans numerically and shows dependencies
ok 1176 bug dashboard bar charts blank the labels of empty segments
ok 1177 bug dashboard pins one colour per priority and state, independent of data order
ok 1178 bug dashboard stacked bars give counts in the tooltip, not on-bar labels
ok 1179 open bugs table links each title to its doc on the scanned branch
ok 1180 bug dashboard separates verified and live-verified summary and table
ok 1181 Verified column reads verified, and only Live-verified reads live
ok 1182 open bugs table sorts by sort_key before hiding it
ok 1183 open bugs table sits in row 22 under the stats, with the time series moved below
ok 1184 bugs table shows Release, Bug, Priority, Filed, Open for, Status, Fixed in, Verified (at), Live-verified (at)
ok 1185 open bugs table shows age in days, not a duration that rolls up to weeks
ok 1186 bugs table shows a dash, not a missing column, for an open bug's Fixed in and verification
ok 1187 bugs table pairs each verification column with its timestamp
ok 1188 Plans Dispatch links to the release in Agent dispatch
ok 1189 priority tiles say they count open bugs
ok 1190 bugs table columns fit a laptop-width panel without horizontal scrolling
ok 1191 plans table columns fit a laptop-width panel without horizontal scrolling
ok 1192 remaining releases table shows forecast dates only and fits a laptop-width panel
ok 1193 Plans table separates verified and live-verified status indicators
ok 1194 PR checks dashboard YAML and embedded JSON are valid
ok 1195 PR checks dashboard has filtered panels and repo variable
ok 1196 PR checks tables say No open PRs instead of No data when nothing is open
ok 1197 PR checks tables join populated rows without duplicate label fields
ok 1198 PR check duration legend uses a readable side layout without changing its query
ok 1199 PR checks distinguish current rows, retained history, empty ranges, and failed or stale reads # skip promtool not installed
ok 1200 HermesNotRunning alerts on a missing or stale heartbeat
ok 1201 HubKineCompactionStalled is a warning after 15 minutes
ok 1202 fixture checksum writer fails clearly when no SHA-256 tool is available
ok 1203 fixture checksum writer uses shasum and writes a verifiable manifest
ok 1204 git stub dispatches on subcommand when -C paths contain git words
ok 1205 hub data restore: decrypts every claim and uses metadata
ok 1206 hub data restore: node mismatch stops before extraction
ok 1207 hub data restore: automatic stage is removed and caller stage survives
ok 1208 hub data restore: empty context returns 2 without kubectl
ok 1209 hub data restore: scales live workloads down and up
ok 1210 hub data restore: applies the drill postgres before scaling any claim down
ok 1211 hub data restore: drill postgres starts at zero replicas and carries no password
ok 1212 hub data restore: a workload that cannot be scaled stops the restore with its name
ok 1213 hub data export: streams each claim from its own node and path
ok 1214 hub data export: encrypted contents, checksums, and split limit
ok 1215 hub data vault: executing stub proves order, stdin hygiene, and cancel
ok 1216 hub data vault: revoke runs after a post-root KV failure
ok 1217 hub data vault: invalid path is rejected before any exec
ok 1218 hub-data: the dispatcher finds every public hub_data function
ok 1219 hub data inventory: walks nested Vault folders by their full path
ok 1220 hub data inventory: a failed nested list names the path instead of failing silently
ok 1221 hub data inventory: a zero LDAP count names LDAP
ok 1222 hub data export setup: the policy grants list below secret/metadata so nested folders can be walked
ok 1223 hub data inventory: counts Keycloak users and LDAP entries with the pod's own credentials
ok 1224 hub data inventory: records the bare array vault kv list prints
ok 1225 hub data inventory: an empty Vault listing or no root token fails instead of recording null
ok 1226 hub data vault: an inventory without Vault paths fails before any Vault call
ok 1227 hub data vault: a recorded path missing from the restored Vault fails and names it
ok 1228 hub data vault: an empty root token fails before listing
ok 1229 hub data export: an inventory failure stops the export before anything is pushed
ok 1230 1 inventory uses Kubernetes login JWT on stdin only
ok 1231 2 export never loads DR shards or generate-root
ok 1232 3 empty login fails with setup guidance and pushes nothing
ok 1233 4 missing pinned context fails before docker or git clone
ok 1234 5 prune keeps recent exports and the last passing export
ok 1235 5b prune retention boundary follows the clock, not the calendar
ok 1236 6 prune keeps the newest when all exports are old
ok 1237 7 results fetch failure is nonzero and does not push
ok 1238 8 prune force-pushes snapshots only
ok 1239 8b export passes its existing clone to prune
ok 1240 9a manifest detects edited, extra, missing, and bad-age files
ok 1241 9b remote mismatch writes no success metric and does not prune
ok 1242 9c prune refuses a kept export with a bad manifest
ok 1243 9 dry-run prune prints keep and prune without pushing
ok 1244 11 rendered plist has scheduled command and calendar
ok 1245 12 alert manifest contains all three export alerts
ok 1246 13 legacy export verifies and one-sided metadata listing fails
ok 1247 14 split export first part must have an age header
ok 1248 15 unparseable export timestamp stops prune without push
ok 1249 10 scheduled run posts newline-delimited metrics and kept count
ok 1250 19 a lock left by a dead run is taken over; a live owner's lock is not
ok 1251 17 setup self-test passes and revokes its single token
ok 1252 17b setup binds the role to the API server audience (required from Vault 1.21)
ok 1253 18 lock semantics distinguish manual, scheduled, and delegated ownership
ok 1254 hub-data: repo file defaults resolve from the plugin, not the caller's directory
ok 1255 recover B4-13: approval is typed and mismatches are refused
ok 1256 recover B4-13a: target validation checks the local serverlb and server-0
ok 1257 recover B4-13b: destructive checkpoints require explicit redo on resume
ok 1258 recover B4-13c: compatibility requires format 2 and all claims
ok 1259 recover B4-13d: verification uses metadata proof fields
ok 1260 recover B4-13e: drill delegates verification to hub_data
ok 1261 recover B4-15: hub mode skips the drill postgres manifest
ok 1262 recover B4-17: ArgoCD resume patches the child before the parent with the recorded values
ok 1263 recover K2: a drill target skips the Keycloak and ESO refresh; the hub runs it
ok 1264 recover D1: credential guard security shim survives its installer function
ok 1265 recover D2: refresh force-syncs, waits, discovers Keycloak, then restarts dependents
ok 1266 recover D2: an OpenLDAP restart failure fails the refresh
ok 1267 recover D2: waits for ArgoCD to create Keycloak before restarting it
ok 1268 recover D2: missing Keycloak reports the bounded ArgoCD timeout
ok 1269 recover D2: Grafana restart failure is a warning
ok 1270 recover D3: restored claims use server-side hub-restore field ownership
ok 1271 recover F4: Step 9 reminds the operator to recreate the export ServiceAccount
ok 1272 recover F5: restore-hub allows finding the unseal-key cache
ok 1273 recover K3: a missing ArgoCD Application is skipped, not a fatal kubectl exit
ok 1274 recover K4: the Keychain age identity is drill-only and never prompts
ok 1275 recover K5: V5 reads pv-pvc.yaml from the recovery's export dir, and names a missing one
ok 1276 recover K6: RTO runs from approval across resumes, not from the last resume
ok 1277 recover K1: a drill target never caches unseal keys in the Keychain; the hub does
ok 1278 recover B4-18: Vault re-point order is config, shards, vault-root, root
ok 1279 recover B4-20: refused preflight prevents hub-recover
ok 1280 recover preflight: present hub is marked and approval warns before deletion
ok 1281 recover preflight: absent hub skips validation and still asks approval
ok 1282 recover teardown: present removes only exact k3d leftovers
ok 1283 recover teardown: cluster-down wrapper deletes the hub and never discards hub data
ok 1284 recover teardown: absent hub checks leftovers without cluster-down
ok 1285 recover teardown: snapshot guard refusal stops before docker cleanup
ok 1286 recover teardown: surviving cluster stops before docker cleanup
ok 1287 recover preflight: a failed k3d listing refuses instead of treating the hub as absent
ok 1288 recover teardown: a failed k3d listing stops before docker cleanup
ok 1289 recover teardown: missing hub_present fails before cluster-down
ok 1290 recover B4-21: teardown precedes rebuild and resume
ok 1291 recover B4-21: hub-recover-all preserves DR shards during hub rebuild
ok 1292 recover B4-22: teardown failure prevents rebuild and resume
ok 1293 recover B4-23: keychain preflight refusal stops hub-recover-all before teardown
ok 1294 recover B4-D1: a failed step records its rc and does not run the next step
ok 1295 recover B4-D2: empty ArgoCD jsonpath is paused and auto-sync is rejected
ok 1296 recover B4-D3: vault-root is JSON from stdin and no literal dash is used
ok 1297 recover B4-R1: finished steps are skipped and unfinished step 4 needs redo
ok 1298 recover B4-R2: restore uses the recorded export and never clones
ok 1299 recover B4-R3: verification passes context to kubectl
ok 1300 recover B4-R3: a failed LDAP admin bind fails LDAP verification
ok 1301 recover B4-R4: resume failure is logged and report records false
ok 1302 recover B4-14: without a TTY approval is refused before the prompt
ok 1303 recover B4-16: age identity is not sent in command argv
ok 1304 recover B4-17a: ArgoCD read-back stops before destructive work
ok 1305 recover B4-19: V8 records SecretSyncedError as false
ok 1306 recover B4-21: drill unseal uses the moved hub function
ok 1307 dr credential shim: stdin is recorded and forwarded byte-for-byte without -w value
ok 1308 dr credential shim: argv -w is skipped and never written under the run directory
ok 1309 dr credential shim: enforce exits 44 and does not reach real security
ok 1310 dr credential scope: a drill may not touch the unseal-key cache or another context's root token
ok 1311 dr credential scope: a hub restore may cache unseal keys; a drill rehearsal may not; root token only for the target context
ok 1312 dr credential guard: hub_data_recover records in its own process, also on RESUME, and scopes by target
ok 1313 dr restore: an out-of-cluster docker target is refused before exec
ok 1314 recover F1: the preflight summary is on stderr so it shows before the approval; stdout is only RUN_ID
ok 1315 recover F2: a resumed run pauses ArgoCD again and keeps the value recorded before the first pause
ok 1316 recover F3: step 2 prompts on every run and hub mode never reads the age identity from the Keychain
ok 1317 scheduled export: SSH guard runs first and a failed guard prevents export
ok 1318 hub Loki port-forward targets loki-gateway on 19100
ok 1319 hub Loki make target renders and bootstraps the agent
ok 1320 hub restore installs the Loki agent beside Pushgateway
ok 1321 hub Pushgateway values use the stable service name
ok 1322 hub port-forward template uses 19094 and never 9091 to 9091
ok 1323 make target renders the hub template without launching launchd
ok 1324 hub Prometheus scrapes the Pushgateway with honor_labels
ok 1325 hub Prometheus imports k3dm test metrics from the laptop Pushgateway
ok 1326 observability ApplicationSet pins the hub chart
ok 1327 only the two vectordb publishers left the app-cluster Pushgateway
ok 1328 hub recovery records: maps five restorable claims without Trivy
ok 1329 hub_recovery_validate: accepts the complete five-claim source map
ok 1330 hub_recovery_validate: a pre-2026-10-09 snapshot with retired ldap claims still validates
ok 1331 hub recovery records: retired osixia ldap claims are not captured
ok 1332 _hub_recovery_sync_vault_root_token: accepts a matching Keychain read-back
ok 1333 _hub_recovery_sync_vault_root_token: rejects a mismatching Keychain read-back
ok 1334 _hub_recovery_sync_vault_root_token: rejects a failed Keychain read-back without exposing the token
ok 1335 hub_recovery_plan: emits the dependency map by logical claim
ok 1336 hub_recovery_validate: rejects a duplicate captured claim
ok 1337 hub_recovery_validate: rejects an unexpected PVC tree
ok 1338 hub_recovery_validate: ignores files below a mapped PVC root
ok 1339 hub_recovery_restore: plans all mapped claims by default
ok 1340 hub_recovery_restore: rejects a target with the wrong logical claim
ok 1341 hub_recovery_targets: renders exactly one current PV target per claim
ok 1342 hub_recovery_targets: rejects a PV assigned to the wrong node
ok 1343 _hub_recovery_render_cloudflared_config: k3d overrides only the frontend origin
ok 1344 _hub_recovery_render_cloudflared_config: hostinger and unknown providers preserve config
ok 1345 _hub_recovery_install_cloudflared_config: app context frontend uses k3s-hostinger
ok 1346 _hub_recovery_install_cloudflared_config: only hub frontend uses k3d
ok 1347 _hub_recovery_install_cloudflared_config: missing frontend keeps k3s-hostinger with warning
ok 1348 _hub_recovery_install_cloudflared_config: explicit provider override wins
ok 1349 hub_recovery_reconcile: dry run prints steps and invokes no operations
ok 1350 _hub_recovery_ensure_identity_bootstrap: missing Application is applied
ok 1351 _hub_recovery_ensure_identity_bootstrap: existing Application is not applied
ok 1352 _hub_recovery_ensure_identity_bootstrap: present OIDC ExternalSecret is applied
ok 1353 _hub_recovery_ensure_identity_bootstrap: absent OIDC ExternalSecret warns and succeeds
ok 1354 hub_recovery_reconcile: bootstraps identity before retrying its sync
ok 1355 _hub_recovery_retry_failed_identity_sync: Failed phase requests one cicd patch
ok 1356 _hub_recovery_retry_failed_identity_sync: Succeeded, Running and empty phases do not patch
ok 1357 _hub_recovery_retry_failed_identity_sync: patch failure is non-fatal
ok 1358 hub_recovery_reconcile: hostnet drift runs after serverlb and failure is non-fatal
ok 1359 hub_recovery_reconcile: confirm invokes app-cluster registration reconcile
ok 1360 hub_recovery_reconcile: restores signing after ESO policy with a pinned context
ok 1361 hub_recovery_reconcile: signing restore failure warns and continues
ok 1362 _hub_recovery_restore_signing: pins the hub context and removes the temp kubeconfig
ok 1363 _hub_recovery_restore_signing: a pin failure warns, skips the restore and leaves no temp file
ok 1364 hub_recovery_reconcile: the dry list names the cosign step
ok 1365 hub_recovery never generates or rotates a signing key
ok 1366 _hub_recovery_render_serverlb_values: servers on 6443, servers then agents on 80/443
ok 1367 _hub_recovery_render_serverlb_values: fails with no server container
ok 1368 _hub_recovery_serverlb_upstream_pairs: empty inline lists yield no pairs
ok 1369 _hub_recovery_ensure_serverlb_upstreams: matching upstreams do not restart the LB
ok 1370 _hub_recovery_ensure_serverlb_upstreams: empty upstreams rewrite values and restart only the LB
ok 1371 _hub_recovery_ensure_serverlb_upstreams: fails when the host API never becomes ready
ok 1372 _hub_recovery_ensure_serverlb_upstreams: unreadable LB values fail without restart
ok 1373 make argocd-admin-resync: invokes only the public mirror action
ok 1374 _hub_recovery_mirror_argocd_admin: keeps an ArgoCD-accepted Vault password
ok 1375 _hub_recovery_mirror_argocd_admin: replaces rejected Vault password with accepted initial secret
ok 1376 _hub_recovery_mirror_argocd_admin: removes its password temp files
ok 1377 _hub_recovery_mirror_argocd_admin: keeps rejected Vault password when ArgoCD is unreachable
ok 1378 _hub_recovery_mirror_argocd_admin: does not expose passwords in mirror logs
ok 1379 _hub_recovery_mirror_argocd_admin: stores an ArgoCD-verified initial password
ok 1380 _hub_recovery_mirror_argocd_admin: does not store a rejected initial password
ok 1381 _hub_recovery_mirror_argocd_admin: skips an absent initial secret
ok 1382 _hub_recovery_mirror_argocd_admin: retries until the initial secret appears
ok 1383 _hub_recovery_mirror_argocd_admin: exhausted secret retry stays non-fatal
ok 1384 _hub_recovery_mirror_argocd_admin: fails when the Vault root token is absent
ok 1385 hub_recovery_reconcile: hub self-registration uses its own cluster name, not ubuntu-k3s
ok 1386 hub snapshot: guard accepts a fresh verified snapshot
ok 1387 hub snapshot: delete guard accepts a fresh data-repo export without SSH
ok 1388 hub snapshot: guard reads verified snapshots during dry-run
ok 1389 hub snapshot: guard refuses an old verified snapshot
ok 1390 hub snapshot: old data export and unreachable M2 fail
ok 1391 hub snapshot: inaccessible data repo falls through to M2
ok 1392 hub snapshot: guard refuses incomplete-only snapshots
ok 1393 hub snapshot: guard refuses an unreachable M2
ok 1394 hub snapshot: malformed age name fails
ok 1395 hub snapshot: capture emits the restore layout
ok 1396 hub snapshot: tree names satisfy hub recovery claim tree
ok 1397 hub snapshot: claim archive lists fixture files
ok 1398 hub snapshot: node placement comes from the PV
ok 1399 hub snapshot: PV hostname maps to one logical docker container
ok 1400 hub snapshot: unbound claim fails closed
ok 1401 hub snapshot: capture probes remote free space once
ok 1402 hub snapshot: checksum mismatch marks incomplete
ok 1403 hub snapshot: rsync stages under incomplete and renames after verification
ok 1404 hub snapshot: failing rsync leaves incomplete without rename or stamp
ok 1405 hub snapshot: capture writes stamp after verification
ok 1406 hub snapshot: prune keeps the configured verified snapshots
ok 1407 hub snapshot: list prints every verified and incomplete snapshot
ok 1408 hub snapshot: prune removes all verified snapshots older than newest keep
ok 1409 hub snapshot: capture auto-prunes to newest verified snapshots
ok 1410 hub snapshot: auto-prune leaves incomplete entries
ok 1411 hub snapshot: auto-prune can be disabled
ok 1412 hub snapshot: auto-prune failure does not fail capture
ok 1413 hub snapshot: insufficient space fails before rsync
ok 1414 hub snapshot: non-numeric free space fails closed
ok 1415 hub snapshot: rename failure leaves capture unverified
ok 1416 hub snapshot: prune removes incomplete snapshots first
ok 1417 hub snapshot: prune refuses zero verified snapshots
ok 1418 hub snapshot: unreachable M2 names the host and leaves no remote directory
ok 1419 hub snapshot: staging is removed after a mid-capture failure
ok 1420 hub snapshot: staging directory is 0700
ok 1421 hub snapshot: age prune removes only old snapshots outside the floor
ok 1422 hub snapshot: all recent snapshots survive regardless of count
ok 1423 hub snapshot: three old verified snapshots remain as the retention floor
ok 1424 hub snapshot: malformed names are kept and warned about
ok 1425 hub snapshot: invalid max age fails before removing anything
ok 1426 hub snapshot: successful capture removes only stale incomplete uploads
ok 1427 hub snapshot: manual capture releases the lock
ok 1428 hub snapshot: scheduled capture skips when lock is held
ok 1429 hub snapshot: scheduled capture returns status and releases lock
ok 1430 hub snapshot: weekly LaunchAgent template has Sunday schedule and logging
ok 1431 hub snapshot: Loki record is present
ok 1432 hub snapshot: remote dir default survives single-quoting on the remote shell
ok 1433 hub snapshot: retain patches Delete and skips Retain
ok 1434 hub snapshot: retain processes remaining claims after missing PVC
ok 1435 _istio_ambient_cni_dirs returns k3d paths
ok 1436 _istio_ambient_cni_dirs returns k3s-hostinger paths
ok 1437 _istio_ambient_cni_dirs defaults unknown providers to Cilium paths
ok 1438 _istio_ambient_cni_provider_is_specific accepts k3d and k3s-hostinger
ok 1439 _istio_ambient_cni_provider_is_specific rejects unknown, empty and bare k3s
ok 1440 deploy_istio_ambient skips provider lookup when CNI dirs are preset
ok 1441 deploy_jenkins skips when ENABLE_JENKINS unset
ok 1442 deploy_jenkins skips when ENABLE_JENKINS=0
ok 1443 deploy_keycloak --help shows usage
ok 1444 deploy_keycloak skips when CLUSTER_ROLE=app
ok 1445 KEYCLOAK_NAMESPACE defaults to identity
ok 1446 KEYCLOAK_HELM_RELEASE defaults to keycloak
ok 1447 deploy_keycloak rejects unknown option
ok 1448 _keycloak_seed_vault_admin_secret function exists
ok 1449 _keycloak_reconcile_realm_client function exists
ok 1450 _keycloak_ensure_e2e_identity creates missing client and user without leaking secrets
ok 1451 _keycloak_ensure_e2e_identity refuses a partial role mapping
ok 1452 _keycloak_ensure_e2e_identity updates existing client and user
ok 1453 _keycloak_ensure_e2e_identity rejects empty secrets before curl
ok 1454 smoke admin Secret falls back to keycloak-secrets
ok 1455 smoke admin Secret keeps preferred Secret when both exist
ok 1456 smoke admin Secret keeps preferred Secret when neither exists
ok 1457 _keycloak_reconcile_realm_client updates argocd redirect URIs # skip shopping-cart-infra realm fixture not reachable: /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.9/offline-test-all-regressions-luna/scripts/tests/plugins/../../../../shopping-carts/shopping-cart-infra/identity/keycloak/realm-shopping-cart.json
ok 1458 smoke admin token supports the deployed password-only admin Secret
ok 1459 _keycloak_remove_client_attribute deletes stale pkce attribute rows
ok 1460 KEYCLOAK_CONFIG_CLI_ENABLED defaults to false
ok 1461 test_keycloak function exists
ok 1462 smoke seed prefers Vault password and does not run openssl
ok 1463 smoke Vault preseed writes absent entry with four fields and a 48-hex password
ok 1464 smoke Vault preseed leaves present entry untouched
ok 1465 smoke Vault preseed forces ESO refresh after a successful put
ok 1466 smoke Vault preseed skips ESO refresh when ExternalSecret is absent
ok 1467 smoke Vault preseed skips ESO refresh when the put fails
ok 1468 smoke seed reuses legacy password and writes all Vault fields
ok 1469 smoke seed generates a password when Vault and legacy Secret are empty
ok 1470 smoke seed and provision never create the smoke Secret
ok 1471 smoke Vault hygiene keeps token and password out of kubectl argv
ok 1472 smoke Vault write failure warns and returns zero
ok 1473 smoke cleanup deletes an unowned legacy Secret
ok 1474 smoke cleanup preserves an ESO-owned Secret
ok 1475 keycloak rotator: CronJob has identity schedule and concurrency policy
ok 1476 keycloak rotator: Vault payload preserves db_password
ok 1477 keycloak rotator: never mutates keycloak-secrets ExternalSecret
ok 1478 keycloak rotator: uses the master realm
ok 1479 keycloak rotator: rollback trap precedes reset-password
ok 1480 keycloak rotator: password is not placed in URL or -u argv
ok 1481 keycloak rotator: no request body carrying a password is passed in argv
ok 1482 keycloak rotator: every curl is captured or redirected
ok 1483 keycloak rotator: apply path applies the manifest
ok 1484 keycloak rotator: apply path configures the exact Vault role
ok 1485 keycloak rotator: absent manifest is a no-op
ok 1486 keycloak rotator: absent Vault role helper is safe
ok 1487 keycloak RETURN traps are self-clearing
ok 1488 LDAP chart passwords: only sed-safe values are retained
ok 1489 LDAP chart passwords: generated values are delimiter-safe hex
ok 1490 rendered rotator uses portable password generation
ok 1491 generate_password returns 48 lowercase hexadecimal characters without openssl
ok 1492 empty password guard precedes the LDAP update
ok 1493 Vault preflight precedes the user loop and does not use the token
ok 1494 password rotator deploy derives the Vault address from VAULT_NS
ok 1495 loadtest: green gates increase and reset breach count
ok 1496 loadtest: first breach holds with hysteresis
ok 1497 loadtest: second consecutive breach stops
ok 1498 loadtest: each hard stop condition appears in breach list
ok 1499 loadtest: strict thresholds keep 2/2/80 green
ok 1500 loadtest: stage ladder caps at 5000
ok 1501 loadtest: confirmation gate refuses without explicit opt-in
ok 1502 loadtest: token endpoint is derived from the issuer
ok 1503 loadtest: mint token refuses without user credentials
ok 1504 loadtest: default PromQL gate queries are well-formed
ok 1505 loadtest: prom query returns 0 for empty/failed result
ok 1506 loadtest: prom query parses a scalar value
ok 1507 loadtest: prom flag maps positive to 1 and zero to 0
ok 1508 loadtest: fetch metrics emits the 8-positional snapshot
ok 1509 loadtest: dry-run ramps through green stages and writes a summary each
ok 1510 loadtest: dry-run stops after hysteresis on a persistent breach
ok 1511 loadtest: stage summary is valid and immutable
ok 1512 ACG PrometheusRule CRD wait reads Established condition
ok 1513 ACG PrometheusRule CRD wait no longer invokes kubectl wait
ok 1514 ACG discovery check accepts a served Prometheus kind
ok 1515 ACG discovery check warns when Prometheus kind is unserved
ok 1516 ACG Step 14b recovery hint escapes the port-forward PID
ok 1517 ACG discovery warning follows successful PrometheusRule apply
ok 1518 ACG Step 14b puts Prometheus port-forward inside the Service guard
ok 1519 no Alertmanager CR returns zero
ok 1520 empty configSecret returns zero
ok 1521 present config secret returns zero and logs info
ok 1522 absent config secret returns one and warns every alert is discarded
ok 1523 failure names the Alertmanager and secret
ok 1524 apiserver scrape timeout: patches unset endpoint to 45s
ok 1525 apiserver scrape timeout: skips an already matching endpoint
ok 1526 apiserver scrape timeout: honors the environment override
ok 1527 apiserver scrape timeout: missing ServiceMonitor is non-fatal
ok 1528 apiserver scrape timeout: patch payload changes only scrapeTimeout
ok 1529 deploy_observability: ensures apiserver timeout after ArgoCD ServiceMonitors
ok 1530 every deployment panel aggregates job_id away
ok 1531 the webhook harness neutralizes the Pushgateway
ok 1532 stat tiles read current values in stacked rows; the graph keeps history
ok 1533 hub istiod keeps only http-monitoring
ok 1534 hub istiod port rule action is keep
ok 1535 hub istiod service-name keep remains additive
ok 1536 acg istiod keeps only http-monitoring
ok 1537 acg istiod port rule action is keep
ok 1538 acg istiod service-name keep remains additive
ok 1539 federate-acg drops self-scraped samples
ok 1540 federate-acg selects raw series only
ok 1541 federate-acg excludes k3s control-plane histograms
ok 1542 federate-acg timeout stays below interval
ok 1543 federate-acg job selector is unchanged
ok 1544 federate-acg labels the target acg and honors source labels
ok 1545 image updater replica stats aggregate
ok 1546 argocd dashboard JSON parses
ok 1547 _observability_seed_grafana_if_absent skips a present credential
ok 1548 _observability_seed_grafana_if_absent writes an absent credential once
ok 1549 observability_seed_grafana is a declared function
ok 1550 observability_seed_grafana logs in and delegates to the private seed
ok 1551 _observability_apply_grafana_rotator logs in to Vault before seeding
ok 1552 observability ServiceMonitors: renders live release values and applies only ServiceMonitors
ok 1553 observability ServiceMonitors: exits cleanly when the CRD never appears
ok 1554 observability ServiceMonitors: exits cleanly when the release is missing
ok 1555 deploy_observability: promotes credential-free hub setup before Vault reads
ok 1556 k3dm-tests rules select the app-cluster stack, not the hub stack
ok 1557 k3dm-tests rules live on the app cluster only
ok 1558 all seven k3dm test-suite alerts are present
ok 1559 OfflineSuiteCaseCountDropped applies its floor only to complete runs
ok 1560 OfflineSuiteRunIncomplete fires for an incomplete run
ok 1561 OfflineSuiteVacuous names the result label value
ok 1562 every k3dm alert carries a non-empty expr
ok 1563 OfflineSuiteRunMissed keys on the per-run timestamp, not the last success
ok 1564 the ACG rules dir is applied to the app cluster by the observability plugin
ok 1565 PrometheusRule CRD wait allows rules apply after delayed creation
ok 1566 PrometheusRule CRD wait skips apply when creation never completes
ok 1567 keep-list predicate: in-list returns 0
ok 1568 keep-list predicate: not-in-list returns 1
ok 1569 keep-list predicate: empty keep-list returns 1
ok 1570 keep-list predicate: whole-word guard returns 1 both directions
ok 1571 keep-list predicate: multi-entry list returns 0
ok 1572 observability remove dashboard: missing configmap does not abort
ok 1573 prometheus reseed: healthy Vault credential does not write
ok 1574 prometheus reseed: readable cache password is reused
ok 1575 prometheus reseed: missing cache generates and writes a credential
ok 1576 prometheus reseed: literal password cache value is unusable
ok 1577 prometheus reseed: failed write remains a failure through refresh
ok 1578 values file does not fully qualify the repository
ok 1579 vars file exports CF_DOMAIN with an environment override
ok 1580 rules apply path runs envsubst
ok 1581 every rules placeholder is in the rules envsubst allowlist
ok 1582 every Probe target is CF_DOMAIN-suffixed
ok 1583 the ACG PrometheusRules apply cannot report success on failure
ok 1584 layer normalizer: 1 stays 1
ok 1585 layer normalizer: 2 stays 2
ok 1586 layer normalizer: empty defaults to 2
ok 1587 layer normalizer: 9 defaults to 2
ok 1588 layer normalizer: foo defaults to 2
ok 1589 platform-ops Application template enables server-side diff
ok 1590 platform-ops ApplicationSet retains server-side apply
ok 1591 platform-ops ExternalSecret and ApplicationSet do not mask differences
ok 1592 platform-ops rotators use BusyBox-compatible base64 -d
ok 1593 platform-ops rotators decode Kubernetes Secret data
ok 1594 new bug doc without Priority is rejected
ok 1595 new bug doc with P2 is accepted
ok 1596 modified legacy bug doc without Priority is accepted
ok 1597 the staged copy is checked, not the working tree
ok 1598 deploy_app_cluster prints help with --help
ok 1599 deploy_app_cluster requires --confirm
ok 1600 deploy_app_cluster fails if k3sup not found
ok 1601 local k3s kubeconfig keeps loopback endpoint for tunneled TLS
ok 1602 local k3s kubeconfig uses the sandbox tunnel port
ok 1603 keeps default when a context still references it
ok 1604 prunes default when nothing references it
ok 1605 add_ubuntu_k3s_cluster does not unconditionally delete default kubeconfig entries
ok 1606 register_shopping_cart_apps fails if argocd dir missing
ok 1607 _ensure_k3sup returns 0 when k3sup is already installed
ok 1608 _ensure_k3sup errors when k3sup absent and no installer available
ok 1609 shopping_cart bootstrap helpers exist
ok 1610 _shopping_cart_resolve_app_context follows the active provider context
ok 1611 _shopping_cart_vault_externalsecrets includes the GHCR pull secret
ok 1612 _ensure_k3sup returns 0 after successful brew install
ok 1613 _ensure_k3sup returns 0 after successful curl install on debian
ok 1614 SSH readiness fails after the configured budget with offline stubs
ok 1615 SSH readiness succeeds when the second probe answers
ok 1616 SSH readiness classifies common failures and redacts diagnostics and key paths
ok 1617 SSH readiness stops immediately when the target hostname cannot resolve
ok 1618 SSH readiness deadline includes probe time and caps the final wait
ok 1619 server install does not invoke k3sup when SSH preflight fails
ok 1620 agent joins fan out in parallel and wait for every worker
ok 1621 agent join failures are collected without aborting other workers
ok 1622 already-ready agents are skipped on an idempotent rerun
ok 1623 _k3sup_join_agent reserves kubelet memory by default
ok 1624 _k3sup_join_agent honours K3S_KUBELET_RESERVED_ARGS
ok 1625 deploy_app_cluster passes kubelet reservations to k3sup install
ok 1626 deploy_app_cluster resolves source-time alias default to current SSH HostName for readiness and k3sup
ok 1627 deploy_app_cluster preserves explicit external IP override
ok 1628 _k3s_agent_is_ready matches node InternalIP, not ssh alias or public IP
ok 1629 _k3s_agent_is_ready is false when the matched node is NotReady
ok 1630 GHCR pull probe succeeds after token exchange and tags list
ok 1631 GHCR pull probe rejects a 403 tags list
ok 1632 GHCR pull probe rejects an empty token exchange
ok 1633 gh CLI PAT is not stored when the pull probe fails
ok 1634 gh CLI pull failure names gh auth refresh
ok 1635 prompt reports HTTP 401 for a dead pasted token
ok 1636 prompt reports missing scope for a valid pasted token
ok 1637 resolve error names gh auth refresh
ok 1638 GHCR path does not pass Vault token or PAT in curl argv
ok 1639 credential drift: no drift matches all stores in check mode
ok 1640 credential drift: postgres drift is reported in check mode
ok 1641 credential drift: postgres apply fixes and restarts only its consumer
ok 1642 credential drift: rabbitmq apply restarts each consumer once
ok 1643 credential drift: redis apply restarts the store and basket consumer
ok 1644 credential drift: apply keeps secret values out of kubectl calls
ok 1645 credential drift: context is required
ok 1646 token mode emits tokenSecretRef block
ok 1647 default (no arg) is token mode
ok 1648 kubernetes mode emits kubernetes auth block with defaults
ok 1649 kubernetes mode honors mount/role overrides
ok 1650 kubernetes mode reflects derived per-context mount when override unset
ok 1651 shopping cart GHCR pull secret keeps the PAT off kubectl argv
ok 1652 shopping-cart-namespace app owns the namespace and ghcr pull secret manifests
ok 1653 shopping-cart-frontend deployment uses ghcr pull secret
ok 1654 reuses existing redis and rabbitmq secrets without PUT for those paths
ok 1655 puts redis and rabbitmq secrets when absent
ok 1656 seed helpers honor SEED_VAULT_ADDR instead of localhost port
ok 1657 copies redis/cart from canonical source Vault when absent in target
ok 1658 copies minio/credentials (multi-field) from canonical source Vault when absent in target
ok 1659 reuses existing payment/encryption without PUT
ok 1660 reuses existing payment/stripe without PUT
ok 1661 reuses existing payment/paypal without PUT
ok 1662 copies payment/encryption from canonical source instead of writing the default
ok 1663 copies payment/stripe from canonical source instead of writing the placeholder
ok 1664 copies payment/paypal from canonical source instead of writing the sandbox default
ok 1665 seed URL carries _vault_local_port set after the plugin was sourced (no empty-port freeze)
ok 1666 vault helpers work without prior seed-local temp state
ok 1667 put surfaces HTTP status and path on a non-2xx write, then fails
ok 1668 deploy_image_signing --help prints usage
ok 1669 deploy_image_signing --enforce is gated behind SIGNING_ALLOW_ENFORCE
ok 1670 deploy_image_signing rejects unknown option
ok 1671 deploy_image_signing --help documents --app-cluster
ok 1672 _signing_install_kyverno pins the chart version (no floating latest)
ok 1673 _signing_install_kyverno appends --set for each SIGNING_KYVERNO_HELM_SET entry
ok 1674 _signing_install_kyverno emits no --set when SIGNING_KYVERNO_HELM_SET is empty
ok 1675 _signing_install_kyverno skips repo ops for a local chart path
ok 1676 _signing_render_policy injects the public key under publicKeys
ok 1677 _signing_render_policy never leaks a private key
ok 1678 rendered policy is namespace-scoped to app namespaces only
ok 1679 rendered policy gates workload controllers, not bare Pod (401 root-cause fix)
ok 1680 rendered policy scopes verifyImages to first-party registry, not wildcard
ok 1681 rendered policy uses Kyverno 1.19 tlog/SCT field names (not bare 'ignore')
ok 1682 rendered policy defaults to Audit (never Enforce by default)
ok 1683 rendered policy honors Enforce when explicitly requested
ok 1684 rendered policy requires a cosign vuln attestation (ADMIT latch)
ok 1685 rendered policy is valid YAML with the key injected at BOTH depths
ok 1686 attestation block inherits the staged failureAction (no separate gate)
ok 1687 signing.sh never passes cosign key/password as a bare CLI argument
ok 1688 signing_restore is a declared function
ok 1689 _signing_grant_eso_read honors the configured ESO auth mount
ok 1690 _signing_grant_eso_read fails without writing when the role read is not JSON
ok 1691 _signing_grant_eso_read fails and does not log granted when the role write fails
ok 1692 _signing_grant_eso_read appends the policy without a leading comma on an empty policy list
ok 1693 signing_restore returns non-zero when the ESO grant fails but still applies the ExternalSecret
ok 1694 signing_restore preserves present key material and reapplies configuration
ok 1695 signing_restore restores absent key material from a backup
ok 1696 signing_restore fails without Vault key or Keychain backup
ok 1697 _signing_apply_pub_externalsecret skips when admission namespace is absent
ok 1698 _signing_apply_pub_externalsecret applies when admission namespace exists
ok 1699 signing_restore logs into Vault before probing key material
ok 1700 signing_init prefers restore over regenerate when a backup exists
ok 1701 ask-docs relay is allowed and reader-scoped
ok 1702 ask-docs relay validates text and sends its own endpoint
ok 1703 ask-docs webhook route and policy are reader-scoped
ok 1704 ask-docs does not alter the ask endpoint
ok 1705 slack relay uses waitUntil for slash command dispatch
ok 1706 slack relay cluster-status acks before webhook completes
ok 1707 slack relay can post a fallback response_url error
ok 1708 slack commands doc lists the cluster-status slash commands
ok 1709 slack commands doc manifest matches the relay command set
ok 1710 slack commands doc gives a concrete example for each command
ok 1711 slack commands doc fix mode names the real FIX_CONTEXT override
ok 1712 slack relay allowlist includes cluster-status and hostinger-status
ok 1713 slack relay assigns remote-operator roles to cluster commands
ok 1714 slack relay forwards remote-operator metadata headers
ok 1715 slack relay parses cluster-diagnose payloads
ok 1716 smoke: all checks pass
ok 1717 smoke: failing offline check fails
ok 1718 smoke: unreachable context skips cluster
ok 1719 smoke: reachable failing cluster fails
ok 1720 smoke: cluster failures include bounded redacted actionable details
ok 1721 smoke: target selection failure includes bounded candidate context
ok 1722 smoke: missing failure details are reported as unavailable
ok 1723 smoke: successful cluster output stays concise
ok 1724 smoke: offline filter never invokes cluster
ok 1725 smoke: invalid filter prints usage
ok 1726 smoke: later checks run after a failure
ok 1727 ssm_wait prints help with --help
ok 1728 ssm_exec prints help with --help
ok 1729 ssm_tunnel prints help with --help
ok 1730 _ssm_get_instance_id returns error for unknown alias
ok 1731 ssm_exec fails when jq is absent
ok 1732 ssm_wait timeout returns 1 so callers can fall back
ok 1733 trivy observability: charts pin trivy-operator 0.34.0 in both application sets
ok 1734 trivy observability: chart values enable serviceMonitor scraping
ok 1735 trivy observability: scanner image tag is explicitly pinned in both values files
ok 1736 trivy observability: both values files enable the built-in trivy server (ClientServer mode)
ok 1737 trivy observability: acg trivy application set uses the acg-specific values file
ok 1738 trivy observability: dashboard exposes log and metric panels for trivy-system
ok 1739 trivy observability: prometheus rule and alertmanager route cover scan job failures
ok 1740 trivy observability: acg values skip kube-system and run one scan job at a time
ok 1741 trivy observability: hub values skip the ephemeral e2e vCluster namespace
ok 1742 tunnel_status reports not running when process absent
ok 1743 tunnel_status reports running when process present
ok 1744 tunnel_start fails when autossh not installed
ok 1745 bare tunnel_start refuses unscoped default host without writing agents
ok 1746 unscoped tunnel_start refuses changing existing host unless forced
ok 1747 sandbox tunnel_start keeps ubuntu as its default host
ok 1748 unscoped tunnel_start with an explicit matching host succeeds
ok 1749 Hostinger reconcile forces existing unscoped ubuntu wrappers to Hostinger
ok 1750 tunnel_start is idempotent when already running
ok 1751 tunnel_stop is idempotent when not running
ok 1752 tunnel_start writes plist and calls launchctl load
ok 1753 main tunnel plist contains only the API forward
ok 1754 vault agent clears stale 8200 and owns the reverse forward
ok 1755 tunnel_start migrates a running main plist that still has the reverse forward
ok 1756 tunnel_stop unloads the vault agent when loaded
ok 1757 tunnel.sh does not disguise sudo
ok 1758 exact destination matching excludes Hostinger and accepts sandbox
ok 1759 sandbox tunnel_start uses sandbox agents and does not accept Hostinger autossh
ok 1760 tunnel scope resolves fresh values on every call
ok 1761 sandbox tunnel_stop uses destination-bounded kill patterns
ok 1762 generated tunnel wrappers timestamp stderr and bound SSH connection time
ok 1763 tunnel log rotation replaces old backup only above five megabytes
ok 1764 cluster-down preserves Hostinger tunnel logs
ok 1765 deploy_vault -h shows usage
ok 1766 _vault_build_policy_hcl: eso-apps prefixes are read-only and scoped
ok 1767 deploy_vault loads optional config when vars file exists
ok 1768 Namespace setup
ok 1769 Helm repo setup
ok 1770 _is_vault_health treats healthy HTTP statuses as success
ok 1771 _is_vault_health ignores prompts and deletion digits for healthy status
ok 1772 _is_vault_health fails for unhealthy HTTP statuses
ok 1773 _is_vault_health fails for unhealthy status in kubectl run output
ok 1774 _is_vault_health retries unhealthy statuses before succeeding
ok 1775 _is_vault_health fails after three unhealthy statuses
ok 1776 _vault_enable_pki skips enabling when mount exists
ok 1777 _vault_pki_issue_tls_secret forwards overrides to secret issuance
ok 1778 _vault_issue_pki_tls_secret revokes existing certificate
ok 1779 _vault_issue_pki_tls_secret skips revoke when secret missing
ok 1780 _vault_post_revoke_request skips revoke when cert is already gone
ok 1781 Full deployment
ok 1782 _vault_seed_ldap_service_accounts seeds secret and policy when missing
ok 1783 _vault_bootstrap_ha uses release selector and unseals listed pods
ok 1784 _vault_bootstrap_ha errors when vault health check fails
ok 1785 _vault_bootstrap_ha reports ready when health check succeeds
ok 1786 _vault_is_sealed returns 0 when Vault is sealed
ok 1787 _vault_is_sealed returns 1 when Vault is unsealed
ok 1788 _vault_is_sealed returns 2 when status cannot be determined
ok 1789 _vault_plan_report surfaces missing components
ok 1790 _vault_plan_report reports success when Vault ready
ok 1791 configure_vault_app_auth exits 1 when APP_CLUSTER_API_URL is unset
ok 1792 configure_vault_app_auth exits 1 when APP_CLUSTER_CA_CERT_PATH is unset
ok 1793 configure_vault_app_auth exits 1 when CA cert file missing
ok 1794 configure_vault_app_auth calls vault commands with correct args
ok 1795 configure_vault_app_auth skips policy creation if it exists
ok 1796 configure_vault_app_auth is idempotent
ok 1797 _vault_app_auth_mount derives mount from context
ok 1798 _vault_app_auth_mount sanitizes uppercase and invalid chars
ok 1799 _vault_app_auth_mount falls back to kubernetes-app for empty context
ok 1800 _vault_app_auth_mount honors APP_K8S_AUTH_MOUNT override
ok 1801 configure_vault_app_auth_for_context exits 1 when context arg is missing
ok 1802 configure_vault_app_auth_for_context skips when context has no server
ok 1803 configure_vault_app_auth_for_context returns non-zero when required and server missing
ok 1804 configure_vault_app_auth_for_context returns non-zero when required and CA missing
ok 1805 configure_vault_app_auth_for_context derives server and temp CA then cleans it up
ok 1806 vault app auth: skips enable when auth mount already exists
ok 1807 _vault_exec: passes VAULT_TOKEN as env arg instead of embedding it in shell command
ok 1808 sealed initialized Vault with rejected cache refuses destructive reinit
ok 1809 sealed initialized Vault with missing cache refuses destructive reinit
ok 1810 unsealed initialized Vault without root Secret refuses reset
ok 1811 exact opt-in permits rejected cache reinitialization
ok 1812 non-exact opt-in does not permit reinitialization
ok 1813 reset failure preserves unseal cache and Secrets
ok 1814 unreachable host data path fails without moving or creating anything
ok 1815 successful cached unseal still logs in
ok 1816 vault cache: override routes cache reads, writes, and clears to the drill service
ok 1817 vault cache: unset override preserves the host service
ok 1818 vault DR shards: save stores two shards under secrets/vault without exposing values
ok 1819 vault DR shards: K3DM_DR_SHARDS_PRESERVE keeps existing different shards
ok 1820 vault DR shards: without the flag, different shards are replaced
ok 1821 vault DR shards: K3DM_DR_SHARDS_PRESERVE still saves when none are stored
ok 1822 vault DR shards: export and import round-trip through stdin
ok 1823 vault DR shards: export refuses a terminal
ok 1824 vault DR shards: drill init does not save durable shards
ok 1825 vault DR shards: normal cache clear does not clear durable service
ok 1826 vault DR shards: export with no stored shards says why and prints nothing
ok 1827 vault DR shards: import rejects a stream whose first line is not a count
ok 1828 vault DR shards: import strips CRs from a copied export
ok 1829 vault DR shards: import refuses a malformed shard without storing or printing it
ok 1830 vault DR shards: export refuses a malformed stored shard without printing it
ok 1831 vault DR shards: the dispatcher banner stays off stdout
ok 1832 _vault_hub_fallback_profile maps hostinger -> laptop
ok 1833 _vault_hub_fallback_profile maps laptop (and default) -> hostinger
ok 1834 _vault_health_status_ok accepts 200/429/472/473, rejects others
ok 1835 vault_failover_hub_into_context requires an app cluster kube-context
ok 1836 vault_failover_hub_into_context rejects unknown kube-contexts
ok 1837 vault_failover_hub_into_context rejects unknown flags
ok 1838 vault init wait: returns once the API answers
ok 1839 vault init wait: gives up when the API never answers
ok 1840 vault init error lines: shows errors, never key material
ok 1841 vault init: never retries once Vault reports initialised
ok 1842 vault init: retries while Vault is still uninitialised
ok 1843 vault init: gives up after the attempt limit
ok 1844 vault is_initialized: reads the initialized field
ok 1845 vault init: a dropped read is retried and the keys come back
ok 1846 vault init: keys left in the pod when they cannot be read back
ok 1847 vault init: stops when init never finishes
ok 1848 _vault_role_merged_policies: desired first, existing extras appended, default and duplicates dropped
ok 1849 _vault_role_merged_policies: unreadable role yields desired only
ok 1850 _vault_role_merged_policies shell-escapes the role path in the read command
ok 1851 configure_vault_app_auth preserves an existing cosign-verify grant
ok 1852 _vault_configure_secret_reader_role preserves an existing cosign-verify grant
ok 1853 vault_seed_hub_into_context requires an app cluster kube-context
ok 1854 vault_seed_hub_into_context rejects unknown kube-contexts
ok 1855 vault_seed_hub_into_context canonical key list contains exactly 13 keys
ok 1856 _vault_exec keeps token out of kubectl argv and sends it on stdin
ok 1857 _vault_exec_stream --stdin multiplexes token line then payload
ok 1858 _vault_exec_stream session branch without --stdin sends only token line
ok 1859 __vault_exec_kubectl --exec-stdin replays stdin across a retry
ok 1860 __vault_exec_kubectl without --exec-stdin runs under set -u
ok 1861 watchdog uses the target context for image lookup and apply
ok 1862 vcluster_create: uses foundation-managed CLI path
ok 1863 _vcluster_check_prerequisites: stores the contract path
ok 1864 foundation contract failure stops before lifecycle work
ok 1865 empty foundation contract path stops before lifecycle work
ok 1866 vcluster_create: honors VCLUSTER_VALUES_FILE override
ok 1867 vcluster_create: fails without active host context
ok 1868 vcluster_create: dry-run prints plan without executing
ok 1869 vcluster_destroy: dry-run prints plan without executing
ok 1870 vcluster_destroy: fails on unknown cluster name
ok 1871 vcluster_destroy: a stale kubeconfig is not proof the vCluster exists
ok 1872 vcluster_destroy: a missing vCluster returns instead of exiting its caller
ok 1873 vcluster_list: uses the contract-returned CLI path
ok 1874 vcluster_destroy: uses the contract-returned CLI path
ok 1875 vcluster_use: fails when kubeconfig file missing
ok 1876 VCLUSTER_VERSION defaults to 0.32.1
ok 1877 VCLUSTER_NAMESPACE defaults to vclusters
ok 1878 VCLUSTER_LOCAL_PORT defaults to 11443
ok 1879 VCLUSTER_SKIP_VERSION_CHECK defaults to true and reaches the CLI environment
ok 1880 _vcluster_export_kubeconfig pins --local-port so the kubeconfig port survives proxy re-creation
ok 1881 _vcluster_export_kubeconfig honours VCLUSTER_LOCAL_PORT override
ok 1882 _vcluster_refresh_connection requires a name
ok 1883 _vcluster_refresh_connection removes the stale proxy and reconnects on the pinned port
ok 1884 _vcluster_deregister_from_hub: deletes hub cluster secret and preflight resources
ok 1885 vcluster_create deletes an orphan occupying the shared namespace
ok 1886 vcluster_create deletes the orphan before creating the new vCluster
ok 1887 vcluster_create warns when it clears an orphan so a teardown regression stays visible
ok 1888 vcluster_create does not delete a vCluster matching the name being created
ok 1889 vcluster_create issues no delete when the namespace holds no vCluster
ok 1890 vcluster_create dry-run clears no orphan
ok 1891 orphan cleanup falls back to helm uninstall when vcluster delete fails
ok 1892 reconcile: deletes only the non-kept JSON cluster
ok 1893 reconcile: empty JSON list does not delete
ok 1894 reconcile: colored table output does not delete
ok 1895 reconcile: delete failure falls back to helm uninstall
ok 1896 vectordb rules target the hub prometheus stack
ok 1897 vectordb alerts are present
ok 1898 automatic indexing alerts use the requested windows
ok 1899 drift alert uses kind counts and first-seen age
ok 1900 drift dashboard panels show kind counts and oldest age without overlaps
ok 1901 VectorDBMetricsStale watches push age, not absence alone
ok 1902 VectorDBMetricsStale still covers the never-published case
ok 1903 absence alone is not the whole staleness expression
ok 1904 VectorDBIndexStale keeps the seven-day index threshold
ok 1905 dashboard has six ingestion panels using emitted metrics
ok 1906 rows and corpus panel formats document counts as whole documents
ok 1907 rows and corpus remain distinguishable when their values overlap
ok 1908 vectordb dashboard is no longer in the app-cluster dashboard folder
ok 1909 every rule keeps string labels and its own annotations
ok 1910 dashboard has four ordered rows and unique panel ids
ok 1911 retrieval alerts use the specified expressions and windows
ok 1912 retrieval probe age panel keeps a daily probe green and matches the stale alert boundary
ok 1913 existing dashboard panel queries and presentation are unchanged

The following warnings were encountered during tests:
BW02: Using flags on `run` requires at least BATS_VERSION=1.5.0. Use `bats_require_minimum_version 1.5.0` to fix this message.
      (from function `bats_warn_minimum_guaranteed_version' in file /opt/homebrew/Cellar/bats-core/1.14.0/lib/bats-core/warnings.bash, line 32,
       from function `run' in file /opt/homebrew/Cellar/bats-core/1.14.0/lib/bats-core/test_functions.bash, line 359,
       in test file scripts/tests/plugins/e2e_sandbox_preflight.bats, line 372)
Test log saved to scratch/test-logs/all/20261028-093140.log
Collected artifacts in scratch/test-logs/all/20261028-093140
[tripwire] blocked 545 call(s) to host tools; none reached a real binary:
    113 kubectl	--context ubuntu-k3s --request-timeout=5s get --raw=/readyz
    113 kubectl	--context ubuntu-hostinger --request-timeout=5s get --raw=/readyz
    113 kubectl	--context ubuntu-gcp --request-timeout=5s get --raw=/readyz
    113 kubectl	--context ubuntu-azure --request-timeout=5s get --raw=/readyz
     37 security	find-generic-password -s k3dm-webhook-token-reader -a k3dm -w
     37 security	find-generic-password -s k3dm-webhook-token-cloud-runner -a k3dm -w
      6 gh	auth token
      5 aws	cloudformation describe-stacks --region us-west-2 --stack-name k3d-manager-cluster --query Stacks[0].StackStatus --output text
      4 launchctl	list com.k3d-manager.acg-watch
      1 security	find-generic-password -s platform-ops-git-writer -a k3dm -w
      1 security	find-generic-password -s platform-ops-app-rebuild -a k3dm -w
      1 security	find-generic-password -s k3dm-webhook-token -a k3dm -w
      1 kubectl	config get-contexts ubuntu-k3s
```
