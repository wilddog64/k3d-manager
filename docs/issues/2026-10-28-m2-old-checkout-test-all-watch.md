# Watched M2 test-all run uses older v1.43.1 checkout

## Host and pane identification

Operator supplied a tmux screenshot whose title identifies m2-air.local.
Coordinator tools are local to m4-air.local, explaining prior local tmux
lookup mismatch. Used existing m2jump alias (ssh -G resolves hostname
m2-air.local,usercliang,port22) with BatchMode=yes,StrictHostKeyChecking=yes,
ConnectTimeout5. Read-only SSH succeeded; no credentials retrieved or keys
sent to panes. First remote non-login command could not find tmux on PATH:

```text
zsh:2: command not found: tmux
m2-air.local
```

Retried with existing absolute /opt/homebrew/bin/tmux; no PATH config changes.
Actual inventory:

```text
20261012051512:1.0 %10 attached=1 command=make history=1259 path=/Users/cliang/src/gitrepo/personal/k3d-manager
20261012051512:2.0 %0 attached=1 command=ssh history=8137 path=/Users/cliang/src/gitrepo/personal/k3d-manager
work:1.0 %10 attached=0 command=make history=1259 path=/Users/cliang/src/gitrepo/personal/k3d-manager
work:2.0 %0 attached=0 command=ssh history=8137 path=/Users/cliang/src/gitrepo/personal/k3d-manager
```

Both session names reference the same pane IDs, not independent test runs.
Coordinator watched %10 read-only, did not interrupt/sync/switch the checkout.
Actual M2 git log -3 output:

```text
71ef4dea docs(bugs): kine stall bug gets an end-to-end alert regression test
9462589a docs(bugs): Hermes kine sensor misses a dead compaction loop (v1.43.2, P2)
f86264f3 docs(bugs): hub kine compaction died again 2026-10-08 after sleep; reopen
```

Actual branch: k3d-manager-v1.43.1. HEAD commit time:
2026-10-11T18:04:47-07:00. Git status --short output empty. This is not the
current M4 v1.43.9 checkout/fix cfb60be0; do not interpret this old branch's
failures as post-fix acceptance for the current P2.

## Completed result: FAIL on older checkout / not current acceptance

Observed run1583cases,23failed. Among diagnostics: ModuleNotFoundError No module
named yaml; other23case details below remain recorded rather than attributed
all to that one dependency. Full later stages did not execute after test failed.
Final actual terminal summary:

```text
make[1]: *** [test] Error 1
[k3dm-test-metrics] 1583 cases, 23 failed
[k3dm-test-metrics] push attempt 1/3 failed: <urlopen error [Errno 61] Connection refused> — retrying
[k3dm-test-metrics] push attempt 2/3 failed: <urlopen error [Errno 61] Connection refused> — retrying
[k3dm-test-metrics] metrics push skipped (non-fatal): <urlopen error [Errno 61] Connection refused>
[test-all] metrics log: /tmp/k3dm-test-all-1793212745.log
make: *** [test-all] Error 2
```

The metrics publication also failed; this is separate from test failures.
Retrieved actual M2 log by read-only SSH to coordinator-local
/private/tmp/k3dm-m2-test-all-1793212745.log:111622bytes,1583cases,23failed.
No further tests or metrics publication performed by coordinator.

Other pane %0 is SSH; latest prompt host label extracted from its tail:

```text
latest_prompt_host=m4-air
```

Recommended next operator action: run make test-all in tmux window2's M4 SSH
shell, using the current configured v1.43.9 checkout and its verified test dependencies. Do not
change M2's intentionally older branch/dependencies/publisher under this
watch-only task. If M2 itself should be updated, that is separate requested
work; current priority is current-fix acceptance on M4. No more pane-locator
questions needed: M2%10localoldmake, M2%0SSHtoM4.

Current P2 remains OPEN until current branch's fresh three stages and published
failed0/complete1 are verified. Docs-only watch report; no code change or
additional BATS/ShellCheck rerun. Normal docs lint/audit/hooks apply. No PR.

## Full actual M2 stage log

```text
scripts/tests/tripwire.sh ./scripts/k3d-manager test all
running under bash version 5.3.20(1)-release
1..1583
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
ok 38 _acg_extend_playwright: returns 0 when node script succeeds
ok 39 _acg_sync_known_hosts prunes stale managed AWS IPs and records current ones # skip Feature not yet implemented: see docs/issues/2026-05-13-acg-up-maintain-known-hosts-for-managed-aws-ips.md
ok 40 _acg_extend_playwright: returns 1 when node script fails
ok 41 acg_watch_start reloads the agent so retargeted run-dir logs take effect
ok 42 _agent_checkpoint: fails when git missing
ok 43 _agent_checkpoint: skips when working tree clean
ok 44 _agent_checkpoint: commits when working tree dirty
ok 45 _agent_lint: skips when AI disabled
ok 46 _agent_audit: detects test weakening (placeholder)
ok 47 _agent_audit: flags bare sudo in staged diff
ok 48 _agent_audit: ignores _run_command sudo in diff
ok 49 _agent_audit: flags kubectl exec with credential env var in staged diff
ok 50 _agent_audit: passes clean staged diff
ok 51 _agent_audit: k3d-manager honours the lib-foundation remote-sudo marker
ok 52 scripts/lib/agent_rigor.sh is a shim to the subtree copy
ok 53 _gemini_ensure_github_session: returns 0 when gemini succeeds
ok 54 _gemini_ensure_github_session: returns 1 when gemini fails
ok 55 _agy_prompt: succeeds on first model
ok 56 _agy_prompt: falls back to next model on 429
ok 57 _agy_prompt: fails when all models exhausted
ok 58 _agy_prompt: passes --dangerously-skip-permissions to agy when requested
ok 59 _agy_prompt: creates workspace temp dir
ok 60 no bare '! cmd' assertions in BATS suites (set -e ignores them)
ok 61 _cleanup_on_success removes every provided path
ok 62 cluster-down no longer removes the legacy active-provider path
ok 63 cluster-down unrecords the current provider
ok 64 _dirservice_activedirectory_config displays configuration
ok 65 _dirservice_activedirectory_validate_config succeeds in test mode
ok 66 _dirservice_activedirectory_validate_config fails when AD_DOMAIN not set
ok 67 _dirservice_activedirectory_validate_config fails when AD_SERVERS not set
ok 68 _dirservice_activedirectory_validate_config fails when AD_BIND_DN not set
ok 69 _dirservice_activedirectory_validate_config fails when AD_BIND_PASSWORD not set
ok 70 _dirservice_activedirectory_validate_config skips check when ldapsearch unavailable
ok 71 _dirservice_activedirectory_generate_jcasc creates valid YAML
ok 72 _dirservice_activedirectory_generate_jcasc requires namespace argument
ok 73 _dirservice_activedirectory_generate_jcasc requires secret_name argument
ok 74 _dirservice_activedirectory_generate_jcasc requires output_file argument
ok 75 _dirservice_activedirectory_generate_env_vars creates output file
ok 76 _dirservice_activedirectory_generate_env_vars requires secret_name argument
ok 77 _dirservice_activedirectory_generate_env_vars requires output_file argument
ok 78 _dirservice_activedirectory_generate_authz creates valid authorization config
ok 79 _dirservice_activedirectory_generate_authz includes custom permissions from env var
ok 80 _dirservice_activedirectory_generate_authz requires output_file argument
ok 81 _dirservice_activedirectory_get_groups returns test groups in test mode
ok 82 _dirservice_activedirectory_get_groups requires username argument
ok 83 _dirservice_activedirectory_get_groups fails when ldapsearch unavailable
ok 84 _dirservice_activedirectory_create_credentials validates AD_BIND_DN is set
ok 85 _dirservice_activedirectory_create_credentials validates AD_BIND_PASSWORD is set
ok 86 _dirservice_activedirectory_create_credentials fails when secret_backend_put unavailable
ok 87 _dirservice_activedirectory_create_credentials calls secret_backend_put when available
ok 88 _dirservice_activedirectory_init runs validation
ok 89 _dirservice_activedirectory_init fails when validation fails
ok 90 _dirservice_activedirectory_init fails when credential storage fails
ok 91 _dirservice_activedirectory_smoke_test_login requires jenkins_url argument
ok 92 _dirservice_activedirectory_smoke_test_login requires test_user argument
ok 93 _dirservice_activedirectory_smoke_test_login requires test_password argument
ok 94 _dirservice_activedirectory_smoke_test_login fails when curl unavailable
ok 95 _dirservice_activedirectory_smoke_test_login fails when authentication fails
ok 96 _dirservice_activedirectory_smoke_test_login succeeds with valid credentials
ok 97 AD_BASE_DN auto-detection from AD_DOMAIN
ok 98 AD_USER_SEARCH_BASE uses AD_BASE_DN
ok 99 AD_GROUP_SEARCH_BASE uses AD_BASE_DN
ok 100 canonical DRY_RUN disables commands and activates predicate
ok 101 legacy K3DM_DEPLOY_DRY_RUN remains a compatible alias
ok 102 dry-run predicate is inactive when both flags are unset or zero
ok 103 dry-run prints command instead of executing
ok 104 dry-run with --prefer-sudo shows sudo prefix
ok 105 dry-run with --require-sudo shows sudo prefix
ok 106 normal mode executes command when K3DM_DEPLOY_DRY_RUN unset
ok 107 normal mode executes command when K3DM_DEPLOY_DRY_RUN=0
ok 108 no-op when bats already meets requirement
ok 109 falls back to source install when sudo unavailable
ok 110 uses package manager when sudo available
ok 111 no-op when copilot binary already present
ok 112 installs via brew when available
ok 113 falls back to release installer when brew missing
ok 114 fails when copilot is not authenticated
ok 115 copilot binary is operational with COPILOT_GITHUB_TOKEN # skip K3DM_COPILOT_LIVE_TESTS not set — skipping live binary check
ok 116 no-op when kubeconform is already installed
ok 117 prefers Homebrew when available
ok 118 installs the pinned release into ~/.local/bin when the checksum matches
ok 119 refuses a download whose checksum does not match and installs nothing
ok 120 every supported platform has a pinned 64-hex checksum
ok 121 validate-manifests ensures kubeconform and pins the CRD catalog to a commit
ok 122 no-op when node already installed
ok 123 installs via brew when available
ok 124 installs via apt-get on Debian systems
ok 125 installs via dnf on RedHat systems
ok 126 falls back to release installer when no package manager works
ok 127 the pushgateway probe uses the installed service name
ok 128 no producer refers to the bare pushgateway service name
ok 129 all three sites agree on the pushgateway service name
ok 130 hub host resolver selects the IPv4 answer after Name
ok 131 hub host resolver returns empty for NXDOMAIN
ok 132 hub host resolver returns empty when docker fails
ok 133 hub host resolver skips IPv6 and selects IPv4
ok 134 hub host resolver source contains no getent
ok 135 installs kubectl via brew on macOS
ok 136 uses non-macOS installers when not on macOS
ok 137 istio-ingressclass manifest exists
ok 138 istio-ingressclass has the correct kind
ok 139 istio-ingressclass has the correct name
ok 140 istio-ingressclass has the correct controller
ok 141 Istio operator template renders valid YAML without HPAs
ok 142 Istio operator template preserves component resources
ok 143 fails when prompt requests forbidden shell cd
ok 144 invokes copilot with scoped prompt and guard rails
ok 145 name- and server-matched apps are both deleted; others are not
ok 146 Secret is deleted before the first Application
ok 147 in-cluster server is never used
ok 148 cluster-down keep-hub guard protects the Vault LaunchAgent
ok 149 _provider_k3s_aws_deploy_cluster --help prints k3s-aws usage
ok 150 _provider_k3s_aws_destroy_cluster --help prints k3s-aws usage
ok 151 _provider_k3s_aws_destroy_cluster without --confirm fails
ok 152 _provider_k3s_aws_deploy_cluster runs acg_provision once
ok 153 k3s-aws marks a newly created stack with its name and region
ok 154 k3s-aws does not mark a healthy reused stack
ok 155 k3s-aws dry-run does not write stack ownership
ok 156 k3s-aws retries app provisioning over SSH after SSM bootstrap fails
ok 157 k3s-aws uses SSH when the laptop Vault reverse bridge is required
ok 158 k3s-aws overrides explicit SSM when the laptop Vault reverse bridge is required
ok 159 k3s-aws fails when SSM bootstrap and SSH retry both fail
ok 160 k3s-aws derives four agent hosts and five total nodes from ACG_AGENT_COUNT
ok 161 k3s-aws preserves two-agent default and three-node total
ok 162 k3s-aws rejects a malformed ACG_AGENT_COUNT before provisioning
ok 163 _provider_k3s_aws_destroy_cluster --confirm runs acg_teardown
ok 164 _k3s_aws_deregister_cluster DRY_RUN describes the hub cleanup
ok 165 _k3s_aws_deregister_cluster deletes only ubuntu-k3s hub objects
ok 166 _k3s_aws_deregister_cluster is idempotent when hub objects are absent
ok 167 k3s-aws keeps SSM when registration and tunnel succeed
ok 168 k3s-aws falls back to SSH when SSM registration fails
ok 169 k3s-aws fails when both SSM and SSH tunnels fail
ok 170 k3s-aws SSM registration timeout returns instead of exiting the shell
ok 171 k3s-aws falls back to SSH when the real SSM registration wait times out
ok 172 _provider_k3s_oci_deploy_cluster --help prints k3s-oci usage
ok 173 _provider_k3s_oci_deploy_cluster -h prints k3s-oci usage
ok 174 _provider_k3s_oci_destroy_cluster --help prints destroy usage
ok 175 _provider_k3s_oci_destroy_cluster without --destroy-infra preserves instance
ok 176 _provider_k3s_oci_destroy_cluster --destroy-infra aborts when user does not type yes
ok 177 _provider_k3s_oci_destroy_cluster --destroy-infra proceeds when user types yes
ok 178 _oci_validate_prereqs fails when oci CLI not in PATH
ok 179 _oci_validate_prereqs fails when required env vars missing and no state file
ok 180 _oci_reconfigure removes env and image-id state files
ok 181 _provider_k3s_oci_deploy_cluster calls all twelve steps in order
ok 182 _provider_k3s_oci_deploy_cluster aborts when validate_prereqs fails
ok 183 _provider_k3s_oci_deploy_cluster aborts when install_cilium fails
ok 184 _oci_provision_instance skips launch when instance already running
ok 185 _oci_provision_instance launches instance when not running
ok 186 _oci_provision_infrastructure writes server-instance-id and agent-instance-id
ok 187 _oci_install_k3s_server skips when k3s already installed
ok 188 _oci_install_k3s_server sends --flannel-backend=none and --disable-network-policy
ok 189 _oci_install_cilium skips when Cilium already installed
ok 190 _oci_install_cilium includes cni.exclusive=false and kubeProxyReplacement=true
ok 191 _oci_install_k3s_agent skips when k3s-agent already active
ok 192 _oci_install_k3s_agent joins via server private IP, not public IP
ok 193 _oci_install_k3s_agent wait loop counts Ready nodes (not grep -v master)
ok 194 _oci_smoke_test fails when fewer than 2 nodes are Ready
ok 195 _oci_smoke_test fails when Cilium DaemonSet is not ready
ok 196 _oci_destroy_infrastructure terminates both server and agent instances
ok 197 oci_backup fails when etcd-snapshot SSH command fails
ok 198 oci_backup fails when snapshot download produces empty file
ok 199 oci_restore fails when snapshot name has invalid format
ok 200 oci_restore fails when scp upload to server fails
ok 201 oci_restore fails when remote restore SSH command fails
ok 202 deploy_observability calls envsubst with $ARGOCD_NAMESPACE and $K3D_MANAGER_BRANCH
ok 203 deploy_observability_acg calls envsubst with $ARGOCD_NAMESPACE, $K3D_MANAGER_BRANCH, and $APP_CLUSTER_NAME
ok 204 deploy_observability_acg falls back to generated Prometheus config when Vault bootstrap write fails
ok 205 observability exposes alertmanager login proxy and make targets
ok 206 observability restores alertmanager access layer when local agents are missing
ok 207 prometheus auth proxy keeps the public and raw backend ports separate
ok 208 prometheus login writes protected credentials without printing the password
ok 209 prometheus auth proxy skips unreadable Vault credentials and missing auth files
ok 210 prometheus auth proxy bootout precedes bootstrap
ok 211 trivy_scan_report calls kubectl get vulnerabilityreports -A for Hub context
ok 212 trivy_scan_report prints an explicit no-report note when empty
ok 213 trivy_scan_report calls kubectl get vulnerabilityreports -A --context ubuntu-k3s for ACG
ok 214 trivy_infra_security_report queries Prometheus for compliance and RBAC findings
ok 215 trivy_infra_security_report tolerates unreachable Prometheus backends
ok 216 observability_status iterates over monitoring trivy-system for both contexts
ok 217 observability exposes alertmanager via cloudflared and make targets
ok 218 prometheus basic-auth never seeds the weak 'password' default
ok 219 Prometheus rotation entrypoint and launchd template are value-free
ok 220 _acg_record_provider writes a set marker and the legacy scalar
ok 221 _acg_record_provider normalizes aliases into the set
ok 222 _acg_list_active_providers lists every live marker
ok 223 _acg_unrecord_provider removes only its own marker; siblings survive
ok 224 _acg_unrecord_provider clears the legacy scalar only when it names that provider
ok 225 _acg_list_active_providers falls back to the legacy scalar when no dir markers
ok 226 _acg_resolve_provider uses the single live set member when offline
ok 227 _acg_resolve_provider on multiple live members falls back to the legacy scalar
ok 228 _acg_resolve_provider back-compat: legacy scalar only, no dir, resolves it
ok 229 _acg_resolve_provider defaults to k3s-hostinger with no set and no scalar
ok 230 _acg_migrate_flat_state moves flat state under the legacy owner
ok 231 _acg_migrate_flat_state claims flat state for the run provider when its context is reachable (no marker)
ok 232 _acg_migrate_flat_state leaves flat state untouched when no marker AND run provider context unreachable
ok 233 _acg_migrate_flat_state is a no-op when there is no flat state
ok 234 _acg_migrate_flat_state skips when the target subdir already exists
ok 235 _acg_provider_state_dir returns the scoped per-provider path
ok 236 _acg_lock_acquire creates the lock and records the pid; release removes it
ok 237 _acg_lock_acquire reclaims a stale lock whose owner is dead
ok 238 _acg_lock_acquire with an empty lock dir is a no-op success
ok 239 _acg_lock_acquire creates a missing parent directory instead of spinning
ok 240 _acg_provider_port_offset is 0 for the default provider (k3s-aws)
ok 241 _acg_provider_port_offset gives distinct non-zero offsets to other providers
ok 242 _acg_provider_port_offset defaults to 0 for unknown providers
ok 243 require-unambiguous-provider refuses when >1 live and provider not explicit
ok 244 require-unambiguous-provider allows >1 live when provider is explicit
ok 245 require-unambiguous-provider allows a single live provider
ok 246 require-unambiguous-provider down allows aws plus hostinger
ok 247 require-unambiguous-provider down refuses two sandboxes plus hostinger
ok 248 require-unambiguous-provider down allows hostinger only
ok 249 require-unambiguous-provider status still refuses aws plus hostinger
ok 250 _acg_normalize_provider normalizes short aliases
ok 251 _acg_provider_context maps providers to app contexts
ok 252 _acg_resolve_provider prefers Hostinger when both providers are reachable
ok 253 _acg_resolve_provider ignores a stale active-provider file
ok 254 _acg_resolve_provider prefers live Hostinger over a stale ACG active-provider file
ok 255 _acg_resolve_provider honors a live Hostinger active-provider file
ok 256 _acg_context_reachable is true when the context answers /readyz
ok 257 _acg_context_reachable is false for an unreachable context
ok 258 _acg_context_reachable is false for an empty context
ok 259 _acg_resolve_provider falls back to k3s-hostinger when nothing is reachable and no file exists
ok 260 _hostinger_set_active_app_cluster is additive by default
ok 261 _hostinger_set_active_app_cluster strips other labels in exclusive mode
ok 262 _argocd_set_active_app_cluster is additive by default
ok 263 _argocd_set_active_app_cluster strips other labels in exclusive mode
ok 264 _hostinger_register_cluster routes through register_app_cluster labels
ok 265 _provider_k3s_hostinger_refresh_cluster reapplies observability and refreshes frontend DNS on the hostinger context
ok 266 _provider_k3s_hostinger_refresh_registration registers only and never touches gitops, edge, or vault
ok 267 _provider_k3s_hostinger_refresh_registration refuses exclusive mode
ok 268 _provider_k3s_hostinger_refresh_registration propagates register failure
ok 269 _hostinger_reapply_gitops_applicationsets reapplies data, services, platform, istio-ambient, and CVE reader appsets from the current branch
ok 270 _hostinger_clear_stale_platform_tracking_ids strips stale basket/product-catalog ownership and refreshes apps
ok 271 _hostinger_reconcile_vault_cluster_store seeds hub Vault data before ExternalSecret reconcile
ok 272 register_app_cluster falls back to insecure tlsClientConfig when CA data is unset
ok 273 register_app_cluster fails closed when managed metadata is incomplete
ok 274 register_app_cluster emits managed labels and annotations when metadata is complete
ok 275 _hostinger_refresh_access_layer restarts argocd port-forward before cloudflared
ok 276 _hostinger_reconcile_vault_cluster_store bootstraps vault-backend when ESO is present
ok 277 _provider_k3d_exec is defined
ok 278 _provider_k3d_cluster_exists is defined
ok 279 _provider_k3d_list_clusters is defined
ok 280 _provider_k3d_apply_cluster_config is defined
ok 281 _provider_k3d_install is defined
ok 282 _provider_k3d_create_cluster is defined
ok 283 _provider_k3d_destroy_cluster is defined
ok 284 _provider_k3d_deploy_cluster is defined
ok 285 _provider_k3d_configure_istio is defined
ok 286 _provider_k3d_expose_ingress is defined
ok 287 _provider_k3s_exec is defined
ok 288 _provider_k3s_cluster_exists is defined
ok 289 _provider_k3s_list_clusters is defined
ok 290 _provider_k3s_apply_cluster_config is defined
ok 291 _provider_k3s_install is defined
ok 292 _provider_k3s_create_cluster is defined
ok 293 _provider_k3s_destroy_cluster is defined
ok 294 _provider_k3s_deploy_cluster is defined
ok 295 _provider_k3s_configure_istio is defined
ok 296 _provider_k3s_expose_ingress is defined
ok 297 _provider_orbstack_exec is defined
ok 298 _provider_orbstack_cluster_exists is defined
ok 299 _provider_orbstack_list_clusters is defined
ok 300 _provider_orbstack_apply_cluster_config is defined
ok 301 _provider_orbstack_install is defined
ok 302 _provider_orbstack_create_cluster is defined
ok 303 _provider_orbstack_destroy_cluster is defined
ok 304 _provider_orbstack_deploy_cluster is defined
ok 305 _provider_orbstack_configure_istio is defined
ok 306 _provider_orbstack_expose_ingress is defined
ok 307 read_lines reads file into array
ok 308 read_lines handles quotes and backslashes
ok 309 read_lines falls back on bash <4 # skip legacy bash not available
ok 310 --prefer-sudo uses sudo when available
ok 311 --prefer-sudo falls back when sudo unavailable
ok 312 --interactive-sudo without a TTY passes -n and the system binary
ok 313 --require-sudo --interactive-sudo without a TTY passes -n and the system binary
ok 314 --require-sudo fails when sudo -n unavailable and no TTY
ok 315 --require-sudo fails when sudo unavailable
ok 316 --probe supports multi-word subcommands
ok 317 --probe escalates to sudo when user probe fails
ok 318 _safe_path: world-writable dir is rejected
ok 319 _safe_path: relative path entry is rejected
ok 320 _safe_path: empty PATH component is rejected
ok 321 _safe_path: standard absolute non-writable dirs pass
ok 322 _safe_path: sticky-bit world-writable dir is rejected
ok 323 _sha256_12 trims digest from argument
ok 324 _sha256_12 reads from stdin when no argument
ok 325 stale-ref check is executable
ok 326 stale-ref check flags the f03df202 data-layer rename # skip fixture commit f03df202 not reachable in this clone (orphaned by branch cleanup)
ok 327 stale-ref check flags the 4c89dabb trivy split # skip fixture commit 4c89dabb not reachable in this clone (orphaned by branch cleanup)
ok 328 stale-ref check is quiet on a commit that touched no etc files # skip fixture commit e3a75f1f not reachable in this clone (orphaned by branch cleanup)
ok 329 system overrides: failure handler redacts inline VAULT_TOKEN commands
ok 330 system.sh shim: _run_command_resolve_sudo is the lib-foundation definition
ok 331 system.sh shim: no-TTY interactive sudo resolves to sudo -n and the system binary
ok 332 system.sh shim: defines only the k3d-manager kubeconform helpers itself
ok 333 system.sh shim: SCRIPT_DIR defaults to the k3d-manager scripts dir
ok 334 system.sh shim: loads with no external commands on PATH
ok 335 _run_command_resolve_sudo: no sudo flags → plain runner
ok 336 _run_command_resolve_sudo: require_sudo unavailable → returns 127
ok 337 _run_command_resolve_sudo: probe succeeds as user → plain runner
ok 338 _run_command: missing program → exits 127
ok 339 _run_command: succeeds for simple command
ok 340 _run_command: --quiet suppresses error output on missing program
ok 341 _run_command: --interactive-sudo flag is accepted without error
ok 342 _run_command: --prefer-sudo flag is accepted without error
ok 343 test_jenkins trap removes auth file
ok 344 hub ESO rows use the hub context and prefix
ok 345 app ESO rows keep legacy names
ok 346 absent ESO CRD is skipped rather than failed
ok 347 kubeconfig error is not reported as not installed
ok 348 absent ESO CRD still reports not installed
ok 349 smoke test ESO wiring samples app and hub through helper
ok 350 the harness neutralizes the Pushgateway so tests cannot write live metrics
ok 351 POST with wrong token returns 401
ok 352 POST with no auth header returns 401
ok 353 POST with correct token returns 202 and job_id
ok 354 POST body over 4KB returns 413
ok 355 GET /status with invalid job_id (not hex8) returns 400
ok 356 GET /status with invalid job_id containing special chars returns 400
ok 357 GET /status with valid hex8 job_id that does not exist returns 404
ok 358 GET unknown path returns 404
ok 359 POST with missing stage field returns 400
ok 360 POST with invalid stage value returns 400
ok 361 POST with JSON-injection attempt in chart_version queues job safely
ok 362 POST /cluster with provider=gcp returns 202 and job_id
ok 363 POST /cluster with unknown provider defaults to aws (202)
ok 364 POST /cluster-status with correct token returns 202 and job_id
ok 365 POST /cve-remediate requires auth, creates one job, and cooldown-skips repeat
ok 366 webhook hostinger status handler accepts provider dispatch
ok 367 Slack signature verification rejects malformed timestamps and bodies
ok 368 status smoke Keycloak admin login uses the operator keycloak-secrets account
ok 369 Slack ignores signed unknown and user-less commands without creating anchors
ok 370 Slack event larger than 4 KB is verified on the full body
ok 371 Slack event over the Slack cap returns 413
ok 372 Slack reports an authorization failure in the originating command thread
ok 373 Slack allowlisted reader can dispatch cluster-status
ok 374 Slack cluster parser accepts tokens in any order and dry-run isolates execution
ok 375 hostinger status keeps report header and final health sections when long
ok 376 POST /cluster-status with wrong token returns 401
ok 377 POST /cluster-status with reader role returns 202
ok 378 POST /diagnostics with reader role returns 202
ok 379 POST /diagnostics rejects non-approved namespaces
ok 380 POST /diagnostics ArgoCD requests must target hub
ok 381 POST /cluster-refresh with reader role returns 403
ok 382 POST /cluster-refresh with operator role returns 202
ok 383 POST /cluster up with operator role returns 403
ok 384 webhook remote operator access defines policy and audit log
ok 385 webhook diagnostics endpoint is reader-scoped and namespace-guarded
ok 386 webhook analysis uses ordered candidates and a safe sentinel
ok 387 webhook cluster status classifies absent ACG sandboxes explicitly
ok 388 webhook ask subprocess captures transcripts in the k3d-manager run dir
ok 389 webhook ask subprocess ensures the run dir exists before capturing
ok 390 POST /analyze with correct token returns 202 and job_id
ok 391 POST /analyze with wrong token returns 401
ok 392 POST /cluster with response_url stored in job dir
ok 393 POST /cluster with wrong token returns 401
ok 394 POST /cluster with action=up returns 202 and job_id
ok 395 POST /cluster with action=down returns 202 and job_id
ok 396 POST /cluster with invalid action returns 400
ok 397 POST /cluster with missing action returns 400
ok 398 Level 1: POST queues job and GET /status returns job output # skip set K3DM_WEBHOOK_LIVE=1 to enable
ok 399 Level 1: GET /status output field is non-empty after job completes # skip set K3DM_WEBHOOK_LIVE=1 to enable
ok 400 Level 2: POST current chart version returns success without running make up # skip set K3DM_WEBHOOK_LEVEL2=1 to enable (requires cluster)
ok 401 Level 3: tunnel rejects wrong token with 401 # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
ok 402 Level 3: tunnel unknown path returns 404 (auth passes, routing fails) # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
ok 403 Level 3: tunnel POST with real token queues job and returns 202 # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
ok 404 k3dm-ask-bash denies general-purpose interpreters
ok 405 k3dm-ask-bash denies output redirection
ok 406 k3dm-ask-bash denies nested shells and command maskers
ok 407 k3dm-ask-bash allows a plain kubectl read
ok 408 k3dm-ask-bash denies outbound network clients
ok 409 k3dm-ask-bash denies git network subcommands
ok 410 k3dm-ask-bash allows local read-only git inspection
ok 411 k3dm-ask-bash denies credential-dir reads
ok 412 k3dm-ask-bash denies editors and find -exec
ok 413 k3dm-ask-bash denies awk system
ok 414 k3dm-ask-bash denies make in read-only mode
ok 415 webhook role helpers preserve token admin and fail closed
ok 416 webhook fix mode requires operator+ role, not question phrasing
ok 417 webhook _slack_post only targets https Slack hosts
ok 418 acg_provision prints help with --help
ok 419 acg_provision requires --confirm
ok 420 acg_provision fails when aws credentials invalid
ok 421 acg_status prints help with --help
ok 422 acg_status exits 1 when no instance found
ok 423 acg_extend prints help with --help
ok 424 acg_extend_playwright prints help with --help
ok 425 acg_extend opens browser on macOS
ok 426 acg_extend prints URL on Linux
ok 427 acg_teardown prints help with --help
ok 428 acg_teardown requires --confirm
ok 429 acg_teardown is idempotent when no stack found
ok 430 acg_teardown deletes stack when found
ok 431 agent dispatch dashboard: valid ConfigMap JSON and datasource
ok 432 agent dispatch dashboard: every queried metric is exported
ok 433 agent dispatch dashboard: panel rectangles do not overlap
ok 434 kube-prometheus-stack values point Alertmanager at the SMTP secret
ok 435 Grafana ServiceMonitors carry the release label Prometheus selects
ok 436 Alertmanager routes Trivy critical CVE alerts to null before SMS
ok 437 Alertmanager sends ACG sandbox criticals to email, not SMS
ok 438 Alertmanager amtool routes ACG sandbox criticals to email # skip amtool is not installed
ok 439 Alertmanager routes KubeJobFailed to platform-warning
ok 440 Alertmanager platform-warning has a non-empty recipient after envsubst
ok 441 Alertmanager keeps the critical route before platform-warning
ok 442 make alertmanager-secret rejects empty input without calling Vault
ok 443 observability treats empty Alertmanager Vault values as absent
ok 444 Alertmanager config helper applies the secret without exposing the password
ok 445 missing Alertmanager Vault secret fails the helper and public command
ok 446 Alertmanager config helper does not leak credentials into the calling shell
ok 447 Alertmanager template has one render site
ok 448 make alertmanager-config invokes the public command
ok 449 the dashboard is a sidecar-loaded ConfigMap in monitoring with valid JSON
ok 450 the integration variable lists only integrations that have sent something
ok 451 the dashboard names no integration this stack does not use
ok 452 every panel uses the hub Prometheus datasource
ok 453 argocd platform-ops deploy applies the Alertmanager delivery dashboard
ok 454 alert categories and pipeline panels use scoped selectors
ok 455 security, synthetic, and noisiest panel contracts match retention
ok 456 dashboard panel rectangles do not overlap and ids are unique
ok 457 missing Application logs a failed promotion and returns zero
ok 458 missing Application emits no remediation event
ok 459 successful Application patch emits one remediation event
ok 460 git-persisted promotion clears the live image override
ok 461 live-patch-only promotion keeps the live image override
ok 462 app_cve_scan_trigger rejects an unsupported cronjob name
ok 463 app_cve_scan_trigger fails when the cronjob is absent
ok 464 app_cve_scan_trigger creates a job from the cronjob
ok 465 app_cve_scan_trigger defaults to app-cve-scan with no argument
ok 466 app_cve_scan_trigger returns non-zero when the wait times out
ok 467 app_cve_scan_trigger honours K3DM_CVE_SCAN_WAIT
ok 468 all-skipped run exits 1 with the fatal zero-match diagnostic
ok 469 vulnerable deployed image with vulnerable latest dispatches rebuild instead of promotion
ok 470 rebuild dispatched within the cooldown is skipped without notifying
ok 471 rebuild dispatched after the cooldown expires dispatches and records the time
ok 472 vulnerable deployed image with clean latest promotes exact digest via application patch
ok 473 COSIGN_VERIFY=1: signed clean candidate is cosign-verified then promoted
ok 474 COSIGN_VERIFY=1: unsigned clean candidate is refused (no promotion)
ok 475 COSIGN_VERIFY_ATTESTATION=1: signed + attested clean candidate is promoted
ok 476 COSIGN_VERIFY_ATTESTATION=1: signed but unattested candidate is refused (no promotion)
ok 477 registry-less trivy-operator repository form still matches and promotes
ok 478 digest resolution reads busybox-style indented lowercase headers
ok 479 clean frontend image is scanned and skipped
ok 480 clean payment image is scanned and skipped
ok 481 missing immutable candidate notifies without failing the batch
ok 482 rebuild dispatch failure notifies without failing the batch
ok 483 missing immutable sha candidate notifies without retrying the batch
ok 484 appset deploy derives envsubst vars from each file
ok 485 every appset variable is defaulted in the argocd bootstrap scope
ok 486 argocd app cluster generator: no static ubuntu-k3s ApplicationSet destination remains
ok 487 argocd app cluster generator: services-git uses matrix clusters label selector
ok 488 argocd app cluster generator: data-git exists and targets shopping-cart-data
ok 489 argocd app cluster generator: data-git ignores controller-injected volumeClaimTemplates fields
ok 490 argocd app cluster generator: data-git requires the shopping-cart opt-in label
ok 491 argocd app cluster generator: services-git requires the shopping-cart opt-in label
ok 492 argocd app cluster generator: eso and acg dashboards stay opt-in-free so the hub keeps them
ok 493 hostinger registration sets the k3s-hostinger provider label
ok 494 an explicit provider override still wins
ok 495 register_app_cluster warns when the provider is unset
ok 496 hostinger registration sets the shopping-cart label by default
ok 497 an explicit shopping-cart override still wins
ok 498 register_app_cluster keeps the false shopping-cart default
ok 499 missing secret and present context dispatches the row provider
ok 500 present secret does not dispatch
ok 501 missing kubeconfig context is skipped successfully
ok 502 dispatcher failure keeps reconcile successful and emits a gap banner
ok 503 exclusive mode refuses to reconcile
ok 504 comment header and blank lines are skipped
ok 505 platform AppProject has no orphaned-resource monitoring
ok 506 shopping-cart AppProject has no orphaned-resource monitoring
ok 507 AppProjects retain required project fields
ok 508 k3s provider wins over generic live CNI dirs
ok 509 orbstack provider wins over live CNI dirs
ok 510 usable live CNI dirs remain the fallback
ok 511 no source emits no CNI override and returns zero
ok 512 k3s refuses generic CNI dirs
ok 513 generic live dirs are refused for a k3d target
ok 514 an unknown provider warns that generic dirs are being written
ok 515 live APP_CLUSTER_NAME override remains unchanged
ok 516 provider is resolved for the live destination, not the shell APP_CLUSTER_NAME
ok 517 non-JSON live read still returns zero
ok 518 ApplicationSet logging says resolved overrides
ok 519 ApplicationSet reapply preserves live destination and CNI dirs
ok 520 ApplicationSet reapply uses CNI resolver when no live set exists
ok 521 ApplicationSet reapply keeps CNI environment defaults without a provider label
ok 522 ApplicationSet reapply ignores live values when requested
ok 523 ApplicationSet reapply leaves sets without live overrides untouched
ok 524 appsets reapply confirmation: retries until the values branch passes
ok 525 appsets reapply confirmation: final stale output is shown after timeout
ok 526 appsets reapply confirmation: invalid timing values fall back to the defaults
ok 527 appsets reapply confirmation: does not wait when the first check passes
ok 528 appsets reapply confirmation: --no-verify skips the check
ok 529 appsets reapply confirmation: dry-run skips the check
ok 530 appset rollout stage: every manifest has a valid stage label
ok 531 appset rollout stage: hub applies before app-cluster
ok 532 appset rollout stage: direct deploy prepares when no stage is supplied
ok 533 appset rollout stage: failed hub confirmation prevents app-cluster apply
ok 534 appset rollout stage: hub applies only the hub stage
ok 535 appset rollout stage: unlabelled manifest aborts before apply
ok 536 appset rollout stage: confirmation checks only its owners
ok 537 appset rollout stage: Degraded owned Application fails hub confirmation
ok 538 appset rollout stage: all confirms and applies app-cluster after hub
ok 539 appset rollout stage: owners matching nothing fails closed
ok 540 appset rollout stage: a stage with no manifests fails instead of checking every Application
ok 541 appset rollout stage: an unknown stage refuses before preparing
ok 542 argocd.sh has no shared browser listener log default
ok 543 argocd.sh has no shared browser listener wrapper default
ok 544 cluster-up keeps the per-provider browser listener log fallback
ok 545 _argocd_deploy_key_policy_hcl includes deploy key paths
ok 546 _argocd_deploy_key_policy_hcl uses read capability
ok 547 _argocd_deploy_key_policy_hcl avoids write/delete
ok 548 configure_vault_argocd_repos errors when namespace missing
ok 549 configure_vault_argocd_repos errors when ESO CRDs missing
ok 550 configure_vault_argocd_repos --dry-run makes no kubectl calls
ok 551 configure_vault_argocd_repos --seed-vault writes placeholders
ok 552 configure_vault_argocd_repos --dry-run --seed-vault prints actions only
ok 553 image-updater: image-list annotation is absent
ok 554 image-updater: digest auto-update strategy is absent
ok 555 image-updater: argocd write-back method is absent
ok 556 image-updater: shopping-cart apps are no longer hard enrolled
ok 557 services-git ApplicationSet ignores kustomize image overrides via jqPathExpressions
ok 558 product-catalog kustomization declares an image override anchor
ok 559 image-updater install: deploy function defined
ok 560 image-updater install: targets image-updater config dir
ok 561 image-updater install: applies kustomize dir
ok 562 image-updater install: honors ARGOCD_SKIP_IMAGE_UPDATER
ok 563 image-updater install: invoked from post-deploy bootstrap
ok 564 image-updater pull-secret: ensure function defined
ok 565 image-updater pull-secret: ensure invoked before install
ok 566 image-updater pull-secret: secret created in ARGOCD_NAMESPACE
ok 567 image-updater pull-secret: credentials point at cicd
ok 568 image-updater pull-secret: no shopping-cart-apps reference in kustomization
ok 569 loki: observability-acg includes a loki application
ok 570 loki: hub observability includes a loki application
ok 571 loki: hub observability forces the helm release name back to loki
ok 572 loki: values pin monolithic filesystem mode
ok 573 loki: hub grafana provisions a loki datasource
ok 574 loki: promtail ships pod logs to Loki
ok 575 loki: observability deploy applies promtail manifest
ok 576 loki: hub observability deploy applies the argocd image updater dashboard
ok 577 metrics: serviceMonitor enabled for all four components
ok 578 metrics: prometheus-operator discovery label present per component
ok 579 metrics: dashboard ConfigMap carries grafana sidecar label
ok 580 metrics: dashboard targets monitoring namespace
ok 581 metrics: dashboard applied from argocd.sh platform-ops deploy
ok 582 metrics: dashboard includes image updater deployment readiness panels
ok 583 metrics: dashboard focuses sync activity on watched apps and infra services
ok 584 alerts: argocd rules cover degraded, out-of-sync, and image flapping for watched apps
ok 585 alerts: alertmanager routes argocd and image-updater alert names to the webhook analyzer
ok 586 metrics: dashboard includes image-updater stat tiles from loki processing results
ok 587 metrics: dashboard includes app-cve-scan job and decision visibility
ok 588 metrics: dashboard includes trivy infra security panels
ok 589 metrics: dashboard has exactly one trivy drilldown table and banner
ok 590 metrics: dashboard banner uses real newlines not literal backslash-n
ok 591 metrics: loki logs panel filters the app-cve-scan stream; other loki panels are stat/graph
ok 592 deploy_argocd_bootstrap invokes deploy_argocd_platform_ops
ok 593 the platform-ops bootstrap call is guarded so it cannot abort the bootstrap
ok 594 argocd reclaim ownership: plan strips foreign ownership from release objects
ok 595 argocd reclaim ownership: plan separates removable and review-only orphans
ok 596 argocd reclaim ownership: dry run reports without changing objects
ok 597 argocd reclaim ownership: confirm patches, removes tracking, and deletes only serviceaccounts
ok 598 argocd reclaim ownership: failed patch leaves tracking label untouched
ok 599 argocd reclaim ownership: unreadable objects return 2
ok 600 argocd reclaim ownership: unknown option returns 2
ok 601 _argocd_ensure_servicemonitors renders with api-versions and applies only ServiceMonitors
ok 602 _argocd_ensure_servicemonitors is a no-op when the ServiceMonitor CRD is absent
ok 603 deploy_argocd_bootstrap calls _argocd_deploy_image_updater
ok 604 argocd values branch: reports drift and returns 1 when an Application is stale
ok 605 argocd values branch: the up-to-date Application is not reported as drifted
ok 606 argocd values branch: returns 0 when every Application matches
ok 607 argocd values branch: owners are included in the success scope
ok 608 argocd values branch: returns 2 instead of a false green when Applications cannot be read
ok 609 argocd values branch: chart sources without the k3d-manager repo are ignored
ok 610 argocd values branch: unparseable input fails closed
ok 611 argocd values branch: zero k3d-manager references fails closed
ok 612 argocd values branch: manifest sources without ref are checked
ok 613 argocd values branch: HEAD sources are ignored as tracking sources
ok 614 argocd values branch: without owners Degraded Applications remain unreported
ok 615 argocd values branch: counter reports checked and ignored HEAD references
ok 616 argocd values branch: dry-run skips confirmation
ok 617 vectordb ApplicationSet is hub-scoped without an app-cluster selector
ok 618 vectordb uses the pinned pgvector pg17 image and not latest
ok 619 vectordb defines no Role, RoleBinding, or ClusterRole
ok 620 vectordb destination and manifests use namespace vectordb, never default
ok 621 vectordb credentials use secretKeyRef and never plaintext trust auth
ok 622 vectordb ExternalSecret uses vault-backend and vectordb/postgres
ok 623 vectordb destination is permitted by the platform AppProject
ok 624 vectordb Application template enables server-side diff
ok 625 vectordb ApplicationSet retains server-side apply and masks no differences
ok 626 the ESO Vault policy grants the prefix the vectordb ExternalSecret reads
ok 627 vectordb Vault seed function is defined
ok 628 bootstrap seeds vectordb before deploying the AppProject
ok 629 vectordb Vault seed checks for an existing secret before putting
ok 630 vectordb Vault seed sends generated credentials on stdin, not argv
ok 631 vectordb Vault seed generates the value from urandom inside remote sh
ok 632 vectordb Vault seed pins the secret KV mount on get and put
ok 633 browser TLS defaults to the k3s-aws provider-scoped state dir
ok 634 browser TLS dirs differ between k3s-aws and k3s-hostinger
ok 635 explicit browser TLS dir overrides the provider-scoped default
ok 636 browser TLS files are inside the selected directory
ok 637 deploy_argocd --help shows usage
ok 638 ArgoCD credential rotator is namespaced and least privilege
ok 639 ArgoCD rotator bcrypt is runtime-correct and pod excludes istio sidecar
ok 640 deploy_argocd skips when CLUSTER_ROLE=app
ok 641 deploy_argocd_bootstrap --help shows usage
ok 642 deploy_argocd_bootstrap no-ops when skipping all resources
ok 643 deploy_argocd_applicationsets --help shows usage
ok 644 deploy_argocd_applicationsets reapplies then verifies the values-branch pin
ok 645 deploy_argocd_applicationsets --no-verify skips the values-branch check
ok 646 deploy_argocd_applicationsets rejects unknown options
ok 647 _argocd_bootstrap_is_ready returns 0 when AppProject and ApplicationSets exist
ok 648 _argocd_bootstrap_is_ready returns 1 when an ApplicationSet is missing
ok 649 _argocd_ensure_logged_in uses plaintext non-interactive login
ok 650 _argocd_wait_for_local_port_forward returns 0 when healthz is reachable
ok 651 _argocd_wait_for_local_port_forward returns 1 when healthz never becomes reachable
ok 652 _argocd_write_port_forward_wrapper includes a self-healing loop
ok 653 _argocd_write_port_forward_wrapper falls back when the requested context is missing
ok 654 port-forward wrapper scopes listener sweeps and refreshes context
ok 655 _argocd_write_browser_https_wrapper includes a canonical HTTPS listener
ok 656 _argocd_issue_browser_tls_material writes Vault-issued TLS files
ok 657 _argocd_deploy_appproject fails when template missing
ok 658 ARGOCD_NAMESPACE defaults to cicd
ok 659 register_app_cluster: permits token-less in-cluster registration
ok 660 register_app_cluster: in-cluster secret does not match platform-helm
ok 661 register_app_cluster: remote secret keeps platform-helm labels
ok 662 register_app_cluster: requires a token for remote registrations
ok 663 ArgoCD Helm values substitute Keycloak OIDC settings
ok 664 ArgoCD public URL override is passed to Helm independently of routing host
ok 665 register_app_cluster: shopping-cart label defaults to false
ok 666 register_app_cluster: shopping-cart label opts in when explicitly true
ok 667 register_app_cluster: rejects a non-boolean shopping-cart value
ok 668 _argocd_deploy_applicationsets surfaces the kubectl error when an apply fails
ok 669 _argocd_deploy_applicationsets returns success when every apply lands
ok 670 aws_import_credentials parses simple CSV (Access key ID,Secret access key)
ok 671 aws_import_credentials parses CSV with User name column
ok 672 aws_import_credentials parses quoted export values
ok 673 aws_import_credentials returns 1 on unparseable input
ok 674 aws_import_credentials --help exits 0
ok 675 deploy_cert_manager fails when ACME_EMAIL is unset
ok 676 deploy_cert_manager --help prints usage
ok 677 _cert_manager_helm_install skips repo ops for local chart path
ok 678 _cert_manager_apply_issuer renders staging ClusterIssuer
ok 679 _cert_manager_apply_issuer renders production ClusterIssuer
ok 680 _cert_manager_apply_issuer fails when ACME_EMAIL empty
ok 681 deploy_cert_manager warns for production on k3d
ok 682 deploy_cert_manager warns for production on orbstack
ok 683 deploy_cert_manager --skip-issuer avoids ClusterIssuer apply
ok 684 deploy_cert_manager --skip-issuer waits for webhook only
ok 685 copilot_triage_pod prints help with --help
ok 686 copilot_triage_pod fails when namespace is missing
ok 687 copilot_triage_pod fails when pod is missing
ok 688 copilot_triage_pod fails when K3DM_ENABLE_AI is not 1
ok 689 copilot_triage_pod invokes _ai_agent_review with kubectl context
ok 690 copilot_draft_spec prints help with --help
ok 691 copilot_draft_spec fails when description is missing
ok 692 copilot_draft_spec fails when K3DM_ENABLE_AI is not 1
ok 693 copilot_draft_spec invokes _ai_agent_review with git context
ok 694 cve scan reads the Hub chart label from argocd-server
ok 695 cve scan does not create or patch an infra cluster-secret stage
ok 696 cve scanner is authorized only to read the Hub deployment
ok 697 cve scan runs end-to-end with wget, kubectl and trivy
ok 698 cve scan treats no newer chart as a finding, but lookup failure as fatal
ok 699 cve scan downloads kubectl when absent
ok 700 cve scanner has no curl invocation
ok 701 cve scan holds major chart upgrades but patches same-major ones
ok 702 cve scan cronjob gives trivy a writable HOME
not ok 703 DR rules: failed and stale alerts are warning alerts in dr.alerts
# (in test file scripts/tests/plugins/dr_alert_rules.bats, line 11)
#   `[ "$status" -eq 0 ]' failed
not ok 704 DR rules: rendered Alertmanager routes both alerts to platform-warning
# (in test file scripts/tests/plugins/dr_alert_rules.bats, line 24)
#   `[ "$status" -eq 0 ]' failed
ok 705 freshness: newest successful run passes
ok 706 freshness: nine-day-old run fails
ok 707 freshness: newest failed run fails
ok 708 freshness: empty results fails
not ok 709 freshness: chooses newest run timestamp instead of filename order
# (in test file scripts/tests/plugins/dr_drill_freshness.bats, line 37)
#   `[ "$status" -eq 0 ]' failed
ok 710 freshness: workflow runs the script from the data repo main checkout, where the how-to installs it
ok 711 e2e_prune_images is a public function (no leading underscore)
ok 712 e2e_prune_images --help prints usage and exits 0
ok 713 e2e_prune_images rejects a non-integer --days
ok 714 _e2e_kustomization_images pairs newName with newTag from the real substrate
ok 715 _e2e_kustomization_images skips an entry that has newTag but no newName
ok 716 _e2e_substrate_images unions kustomize overrides with literal manifest images
ok 717 _e2e_image_epoch parses a docker CreatedAt timestamp
ok 718 _e2e_image_epoch returns non-zero on an unparseable timestamp
ok 719 dry run flags an old unprotected image and removes nothing
ok 720 dry run does not flag a pinned substrate image even when old
ok 721 exporter declares the e2e reader and label selector
ok 722 Hermes dashboard exposes current findings and history
ok 723 Hermes dashboard exposes failure evidence and status meanings
ok 724 exporter emits all five e2e_* gauges
ok 725 exporter emits grouped e2e failure metric and dashboard table
ok 726 exporter emits test-level failure metric and dashboard table
not ok 727 exporter normalizes nested JSON and skips invalid E2E payloads
# (in test file scripts/tests/plugins/e2e_observability.bats, line 75)
#   `[ "${status}" -eq 0 ]' failed
not ok 728 exporter labels e2e gauges with the runner dimension
# (in test file scripts/tests/plugins/e2e_observability.bats, line 96)
#   `[ "${status}" -eq 0 ]' failed
not ok 729 embedded exporter.py compiles cleanly
# (in test file scripts/tests/plugins/e2e_observability.bats, line 115)
#   `[ "${status}" -eq 0 ]' failed
not ok 730 exporter RBAC is not widened (still get,list on configmaps only)
# (in test file scripts/tests/plugins/e2e_observability.bats, line 132)
#   `[ "${status}" -eq 0 ]' failed
not ok 731 exporter maps UNKNOWN Trivy severity from CVSS score
# (in test file scripts/tests/plugins/e2e_observability.bats, line 148)
#   `[ "${status}" -eq 0 ]' failed
not ok 732 exporter preserves remediation cache when refresh fails
# (in test file scripts/tests/plugins/e2e_observability.bats, line 166)
#   `[ "${status}" -eq 0 ]' failed
not ok 733 terminal remediation outcomes are excluded from current status
# (in test file scripts/tests/plugins/e2e_observability.bats, line 181)
#   `[ "${status}" -eq 0 ]' failed
not ok 734 e2e dashboard CM parses and its embedded JSON references e2e_* metrics
# (in test file scripts/tests/plugins/e2e_observability.bats, line 206)
#   `[ "${status}" -eq 0 ]' failed
not ok 735 prometheusrule defines the e2e alerts group and both alerts
# (in test file scripts/tests/plugins/e2e_observability.bats, line 223)
#   `[ "${status}" -eq 0 ]' failed
not ok 736 e2e alerts aggregate away the scrape target and name the exported service
# (in test file scripts/tests/plugins/e2e_observability.bats, line 241)
#   `[ "${status}" -eq 0 ]' failed
ok 737 argocd platform-ops deploy applies the e2e dashboard
ok 738 Alertmanager has a non-null severity warning route
ok 739 Alertmanager warning catch-all follows the named allowlist
not ok 740 e2e runs carry a run date and say whether a failure was fixed later
# (in test file scripts/tests/plugins/e2e_observability.bats, line 298)
#   `[ "${status}" -eq 0 ]' failed
ok 741 public runner functions are dispatchable (no leading underscore)
ok 742 e2e_remote.sh sources cleanly under set -euo pipefail
ok 743 eval_gates accepts a healthy runner
ok 744 eval_gates reports docker_down when Docker is unresponsive
ok 745 eval_gates reports busy when the runner lock is held
ok 746 eval_gates fails when the mean CPU idle is below the floor
ok 747 one dipped sample does not refuse a mostly idle runner
ok 748 eval_gates refuses a blob with no CPU samples
ok 749 preflight retry retries capacity refusal and then succeeds
ok 750 preflight retry does not retry busy refusal
ok 751 preflight retry stops after the configured capacity retries
ok 752 dispatch uses retry preflight and probe takes six top samples
ok 753 eval_gates fails on low memory
ok 754 eval_gates fails on low disk
ok 755 eval_gates treats missing metrics as a capacity stop, not available
ok 756 num_lt compares decimals
ok 757 SSH options never weaken host verification and keep BatchMode
ok 758 remote SSH command injects the homebrew+local PATH so tools resolve
ok 759 preflight reports unreachable when the probe yields nothing
ok 760 preflight surfaces the pure gate verdict from a live probe
ok 761 cluster reconcile refuses to operate on the hub cluster name
ok 762 cluster reconcile targets the dedicated runner context, never the hub
ok 763 bootstrap returns unreachable without mutating when SSH is down
ok 764 valid_digest accepts empty, bare, and repo-qualified sha256 digests
ok 765 valid_digest rejects malformed or injection-y digests
ok 766 runner_allowed enforces the allowlist
ok 767 dispatch rejects a runner outside the allowlist
ok 768 dispatch rejects an invalid digest
not ok 769 dispatch refuses to run and never falls back locally when preflight fails
# (in test file scripts/tests/plugins/e2e_remote.bats, line 257)
#   `[[ "$output" == *"status=busy"* ]]' failed
ok 770 dispatch reports the held lock holder and preserves the lock
ok 771 dispatch builds the correct remote command and records a transcript
ok 772 dispatch streams the GHCR token on stdin and not in the command string
ok 773 the dispatch transcript never contains the GHCR token
ok 774 dispatch returns the remote exit code when a token is streamed
ok 775 dispatch sends an empty credential when no token source is available
ok 776 an empty forwarded credential is treated as absent by the env resolver
ok 777 the token resolver never prints the token value
ok 778 dispatch refuses an unpushed SHA before SSH
ok 779 dispatch refuses a malformed runner repository URL
ok 780 dispatch uses an explicit runner repository override
not ok 781 dispatch returns the remote exit code unchanged
# (in test file scripts/tests/plugins/e2e_remote.bats, line 472)
#   `[ "$status" -eq 7 ]' failed
ok 782 publish-back host loads from the operator conf file and env wins
ok 783 publish-back conf ignores shell metacharacters and warns when absent
ok 784 dispatch copies remote result files and preserves a non-zero exit code
ok 785 make e2e-remote requires RUNNER and wires to the dispatcher
ok 786 publish_build accepts a valid m2 payload and emits a deterministic name
ok 787 publish_build accepts a real null-heavy summary (no digest, unparsed results)
ok 788 publish_build rejects the local-m4 runner (local publishes itself)
ok 789 publish_build rejects unexpected keys (namespace/kubeconfig/labels injection)
ok 790 publish_build rejects missing required fields
ok 791 publish_build rejects a malformed digest and a bad exit code
ok 792 publish_build rejects an invalid result value
ok 793 publish_build rejects non-JSON payloads
ok 794 e2e_result_publish applies to the hub context and audits the outcome
ok 795 e2e_result_publish rejects an empty stdin payload
ok 796 e2e_result_publish rejects a bad payload and does not apply
ok 797 publisher install builds a restricted forced-command authorized_keys entry
ok 798 publisher install refuses a non-key file
ok 799 remote path never exfiltrates M4 kubeconfig, Vault, or Cloudflare secrets
ok 800 public failure/ops functions are dispatchable (no leading underscore)
ok 801 lock token carries only owner/pid/ts and no shell metacharacters
ok 802 the runner lock is a directory (atomic mkdir), probed with -e
ok 803 lock acquire records the owner token via mkdir + meta
ok 804 lock release only removes when the owner meta matches (never blind rm)
not ok 805 dispatch refuses and never falls back locally when the lock is held
# (in test file scripts/tests/plugins/e2e_remote.bats, line 788)
#   `[[ "$output" == *"busy"* ]]' failed
not ok 806 dispatch chains publish-back after the E2E and preserves the exit code
# (in test file scripts/tests/plugins/e2e_remote.bats, line 801)
#   `[ "$status" -eq 0 ]' failed
ok 807 newest_summary returns the latest run json and skips retention markers
ok 808 synth_summary writes a schema-valid failed summary carrying the exit code
ok 809 synth_summary clamps an out-of-range exit code
ok 810 publish_back_push fails when no M4 target is configured
ok 811 publish_back_push uses the dedicated key and streams the file over stdin
ok 812 publish_back synthesizes a summary when the run left none, and returns 0
ok 813 publish_back retains a publication_pending marker when M4 is unavailable
ok 814 publish_replay pushes retained results and renames them published, idempotently
ok 815 publish_replay reports still-pending (non-zero) when a push fails
ok 816 M4 replay enforces the allowlist and the reachability guard
ok 817 M4 replay drives the remote publish_replay when the runner is reachable
ok 818 unlock reports nothing to clear when no lock is present
ok 819 unlock refuses while an E2E run is still active
ok 820 unlock refuses a fresh (not-yet-stale) lock
ok 821 unlock clears a stale lock past the max age with no live run
ok 822 unlock enforces the allowlist
ok 823 health reports a hub outage as critical, distinct from runner state
ok 824 health is ok when the hub is up and the runner is available
ok 825 an unavailable runner is a warning, but critical when a run was requested
ok 826 the failure path never auto-restarts OrbStack, deletes a cluster, or blind-clears the lock
ok 827 make targets wire the failure/ops entry points
ok 828 preflight fails when _ACG_SANDBOX_URL is empty
ok 829 preflight refuses to run when K3DM_ACG_SKIP_SESSION_CHECK is set
ok 830 preflight reads no credential when it refuses on K3DM_ACG_SKIP_SESSION_CHECK
ok 831 preflight fails when the credential entry is absent
ok 832 preflight fails when the entry exists but the login keychain is locked
ok 833 preflight fails when the entry exists but the stored value is empty
ok 834 preflight still fails when the credential is unreadable but the profile dir EXISTS
ok 835 preflight fails when only the username account is readable
ok 836 preflight loads both credential accounts by name
ok 837 preflight leaks no credential value into its output
ok 838 preflight prints no placeholder credential command
ok 839 preflight arms the fail-closed credential gate for the session check
ok 840 preflight arms the fail-closed gate as an exported variable
ok 841 preflight passes when url, credentials and env are all sane
ok 842 make e2e-sandbox wires to the sandbox dispatcher and passes DIGEST through
ok 843 cluster preflight fails when the sandbox kubecontext is absent
ok 844 cluster preflight does not match a context by prefix
ok 845 cluster preflight fails when the context exists but the API server is dead
ok 846 cluster preflight passes when the context exists and answers readyz
ok 847 cluster preflight runs before the sandbox extension burns a browser step
ok 848 every substrate pod spec disables service links
ok 849 e2e_verify_vcluster is a public function (no leading underscore)
ok 850 e2e_verify_sandbox is a public function (no leading underscore)
ok 851 sandbox verification never invokes register_app_cluster
ok 852 sandbox job manifest exports OAuth2 and Stripe mode before Job creation
ok 853 sandbox Job uses the real Tier 2 Service hostnames
ok 854 sandbox Job preserves all four service ports
ok 855 sandbox Job command emits result markers and preserves Playwright status
ok 856 sandbox summary parser extracts marked Playwright results
ok 857 sandbox preflight creates both Secrets before completion
ok 858 sandbox preflight is idempotent
ok 859 sandbox preflight rejects a missing Stripe Keychain item
ok 860 sandbox preflight never places the Stripe key in kubectl argv
ok 861 sandbox rendered overrides contain the three substrate changes
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
ok 915 deploy_eso -h shows usage
ok 916 Skips install if ESO already present
ok 917 Fresh install
ok 918 Skips Helm install if ESO is externally managed
ok 919 Local ESO chart skips repo add
ok 920 gcp_login --help exits 0
ok 921 gcp_login skips gcloud when already active account
ok 922 gcp_login uses config set when account in store but not active
ok 923 gcp_login calls gcloud auth login when playwright available
ok 924 gcp_login falls back to manual gcloud when node unavailable
ok 925 gcp_login returns 1 when account not set
ok 926 gcp_login returns 1 when gcloud not found
ok 927 gcp_get_credentials calls _ensure_node when node is missing
ok 928 gcp_login.js passes node --check
ok 929 acg dashboard appset targets app-cluster role
ok 930 acg dashboard appset syncs the dashboards directory
ok 931 acg dashboard appset excludes hub collisions by server
ok 932 acg dashboard appset does not manage the hub-owned k3dm tests dashboard
ok 933 acg dashboard appset collision guard rejects a missing exclude
ok 934 acg dashboard appset collision guard rejects a name-keyed condition
ok 935 acg dashboard appset collision guard derives a second platform collision
ok 936 hub dashboard appset includes all grafana-dashboard configmaps
ok 937 hub dashboard appset imports the k3dm tests dashboard
ok 938 k3dm tests dashboard uses the hub Prometheus datasource
ok 939 k3dm tests failing-suite table has human-readable columns
ok 940 k3dm tests dashboard preserves failed cases across the selected range
ok 941 both dashboard appsets self-heal
ok 942 Checkout Load Test CPU saturation uses a window that spans several scrapes
ok 943 observability plugin applies both dashboard appsets
ok 944 CVE remediation outcome panels preserve the affected service
ok 945 Grafana Overview uses readable request labels
ok 946 Grafana Overview dashboard count names what it counts
ok 947 hub Grafana Overview uses the same readable dashboard contract
ok 948 readable Overview title does not collide with the stock Grafana Overview
ok 949 Grafana Health dashboard has a fixed uid and k3dm tags
ok 950 Grafana Overview Build Info panels use the positive table contract
ok 951 Grafana Overview Build Info panels stay byte-identical
ok 952 Grafana Overview query panels use live metrics and rate interval
ok 953 Grafana Overview Firing Alerts and Request Rate panels stay byte-identical
ok 954 Grafana Overview Firing Alerts by Category panels satisfy the table contract
ok 955 Grafana Overview panels do not overlap
ok 956 Grafana Overview category mutation rejects a missing Trivy category
ok 957 Grafana Overview category mutation rejects a time-series format
ok 958 Grafana Overview query mutation rejects a fixed one-minute window
ok 959 Grafana Overview query mutation rejects the removed alert metric
ok 960 Grafana Overview query mutation rejects missing alert exclusion
ok 961 Grafana Overview query mutation rejects the old Request Rate description
ok 962 Grafana Overview Build Info mutation guards reject a missing include
ok 963 Grafana Overview Build Info mutation guards reject an extra include name
ok 964 Grafana Overview Build Info mutation guards reject missing width overrides
ok 965 k3dm tests dashboard shows the latest run classification
ok 966 k3dm tests freshness stats aggregate to one latest value
ok 967 every provisioned Grafana dashboard carries at least one tag
ok 968 bug dashboard is valid JSON with uid and Prometheus datasource
ok 969 every bug metric queried by dashboard is emitted
ok 970 bug dashboard panels have non-overlapping positions inside 24 columns
ok 971 bug dashboard bar charts blank the labels of empty segments
ok 972 bug dashboard pins one colour per priority and state, independent of data order
ok 973 bug dashboard stacked bars give counts in the tooltip, not on-bar labels
ok 974 HermesNotRunning alerts on a missing or stale heartbeat
ok 975 hub data restore: decrypts every claim and uses metadata
ok 976 hub data restore: node mismatch stops before extraction
ok 977 hub data restore: automatic stage is removed and caller stage survives
ok 978 hub data restore: empty context returns 2 without kubectl
ok 979 hub data restore: scales live workloads down and up
ok 980 hub data restore: applies the drill postgres before scaling any claim down
ok 981 hub data restore: drill postgres starts at zero replicas and carries no password
ok 982 hub data restore: a workload that cannot be scaled stops the restore with its name
ok 983 hub data export: streams each claim from its own node and path
ok 984 hub data export: encrypted contents, checksums, and split limit
ok 985 hub data vault: executing stub proves order, stdin hygiene, and cancel
ok 986 hub data vault: revoke runs after a post-root KV failure
ok 987 hub data vault: invalid path is rejected before any exec
ok 988 hub-data: the dispatcher finds every public hub_data function
ok 989 hub data inventory: walks nested Vault folders by their full path
ok 990 hub data inventory: a failed nested list names the path instead of failing silently
ok 991 hub data inventory: a zero LDAP count names LDAP
ok 992 hub data export setup: the policy grants list below secret/metadata so nested folders can be walked
ok 993 hub data inventory: counts Keycloak users and LDAP entries with the pod's own credentials
ok 994 hub data inventory: records the bare array vault kv list prints
ok 995 hub data inventory: an empty Vault listing or no root token fails instead of recording null
ok 996 hub data vault: an inventory without Vault paths fails before any Vault call
ok 997 hub data vault: a recorded path missing from the restored Vault fails and names it
ok 998 hub data vault: an empty root token fails before listing
ok 999 hub data export: an inventory failure stops the export before anything is pushed
ok 1000 1 inventory uses Kubernetes login JWT on stdin only
ok 1001 2 export never loads DR shards or generate-root
ok 1002 3 empty login fails with setup guidance and pushes nothing
ok 1003 4 missing pinned context fails before docker or git clone
not ok 1004 5 prune keeps recent exports and the last passing export
# (in test file scripts/tests/plugins/hub_data.bats, line 443)
#   `source_plugin; export DR_TEST_RESULT_EXPORT=20261002T120000Z; run hub_data_prune; [ "$status" -eq 0 ]; [[ "$output" == *'keep: 20261009T120000Z'* ]]; [[ "$output" == *'keep: 20261007T120000Z'* ]]; [[ "$output" == *'keep: 20261002T120000Z'* ]]; [[ "$output" == *'prune: 20261004T120000Z'* ]]; [[ "$output" == *'prune: 20260928T120000Z'* ]]' failed
ok 1005 6 prune keeps the newest when all exports are old
ok 1006 7 results fetch failure is nonzero and does not push
ok 1007 8 prune force-pushes snapshots only
ok 1008 8b export passes its existing clone to prune
ok 1009 9a manifest detects edited, extra, missing, and bad-age files
ok 1010 9b remote mismatch writes no success metric and does not prune
ok 1011 9c prune refuses a kept export with a bad manifest
ok 1012 9 dry-run prune prints keep and prune without pushing
ok 1013 11 rendered plist has scheduled command and calendar
ok 1014 12 alert manifest contains all three export alerts
ok 1015 13 legacy export verifies and one-sided metadata listing fails
ok 1016 14 split export first part must have an age header
ok 1017 15 unparseable export timestamp stops prune without push
ok 1018 10 scheduled run posts newline-delimited metrics and kept count
ok 1019 19 a lock left by a dead run is taken over; a live owner's lock is not
ok 1020 17 setup self-test passes and revokes its single token
ok 1021 17b setup binds the role to the API server audience (required from Vault 1.21)
ok 1022 18 lock semantics distinguish manual, scheduled, and delegated ownership
ok 1023 hub-data: repo file defaults resolve from the plugin, not the caller's directory
ok 1024 recover B4-13: approval is typed and mismatches are refused
ok 1025 recover B4-13a: target validation checks the local serverlb and server-0
ok 1026 recover B4-13b: destructive checkpoints require explicit redo on resume
ok 1027 recover B4-13c: compatibility requires format 2 and all claims
ok 1028 recover B4-13d: verification uses metadata proof fields
ok 1029 recover B4-13e: drill delegates verification to hub_data
ok 1030 recover B4-15: hub mode skips the drill postgres manifest
ok 1031 recover B4-17: ArgoCD resume patches the child before the parent with the recorded values
ok 1032 recover K2: a drill target skips the Keycloak and ESO refresh; the hub runs it
ok 1033 recover K3: a missing ArgoCD Application is skipped, not a fatal kubectl exit
ok 1034 recover K4: the Keychain age identity is drill-only and never prompts
ok 1035 recover K5: V5 reads pv-pvc.yaml from the recovery's export dir, and names a missing one
ok 1036 recover K6: RTO runs from approval across resumes, not from the last resume
ok 1037 recover K1: a drill target never caches unseal keys in the Keychain; the hub does
ok 1038 recover B4-18: Vault re-point order is config, shards, vault-root, root
ok 1039 recover B4-20: refused preflight prevents hub-recover
ok 1040 recover B4-D1: a failed step records its rc and does not run the next step
ok 1041 recover B4-D2: empty ArgoCD jsonpath is paused and auto-sync is rejected
ok 1042 recover B4-D3: vault-root is JSON from stdin and no literal dash is used
ok 1043 recover B4-R1: finished steps are skipped and unfinished step 4 needs redo
ok 1044 recover B4-R2: restore uses the recorded export and never clones
ok 1045 recover B4-R3: verification passes context to kubectl
ok 1046 recover B4-R4: resume failure is logged and report records false
ok 1047 recover B4-14: without a TTY approval is refused before the prompt
ok 1048 recover B4-16: age identity is not sent in command argv
ok 1049 recover B4-17a: ArgoCD read-back stops before destructive work
ok 1050 recover B4-19: V8 records SecretSyncedError as false
ok 1051 recover B4-21: drill unseal uses the moved hub function
ok 1052 dr credential shim: stdin is recorded and forwarded byte-for-byte without -w value
ok 1053 dr credential shim: argv -w is skipped and never written under the run directory
ok 1054 dr credential shim: enforce exits 44 and does not reach real security
ok 1055 dr credential scope: a drill may not touch the unseal-key cache or another context's root token
ok 1056 dr credential scope: a hub restore may cache unseal keys; a drill rehearsal may not; root token only for the target context
ok 1057 dr credential guard: hub_data_recover records in its own process, also on RESUME, and scopes by target
ok 1058 dr restore: an out-of-cluster docker target is refused before exec
ok 1059 recover F1: the preflight summary is on stderr so it shows before the approval; stdout is only RUN_ID
ok 1060 recover F2: a resumed run pauses ArgoCD again and keeps the value recorded before the first pause
ok 1061 recover F3: step 2 prompts on every run and hub mode never reads the age identity from the Keychain
ok 1062 hub Pushgateway values use the stable service name
ok 1063 hub port-forward template uses 19094 and never 9091 to 9091
ok 1064 make target renders the hub template without launching launchd
not ok 1065 hub Prometheus scrapes the Pushgateway with honor_labels
# (in test file scripts/tests/plugins/hub_pushgateway.bats, line 39)
#   `[ "${status}" -eq 0 ]' failed
not ok 1066 hub Prometheus imports k3dm test metrics from the laptop Pushgateway
# (in test file scripts/tests/plugins/hub_pushgateway.bats, line 55)
#   `[ "${status}" -eq 0 ]' failed
ok 1067 observability ApplicationSet pins the hub chart
ok 1068 only the two vectordb publishers left the app-cluster Pushgateway
ok 1069 hub recovery records: maps five restorable claims without Trivy
ok 1070 hub_recovery_validate: accepts the complete five-claim source map
ok 1071 hub_recovery_validate: a pre-2026-10-09 snapshot with retired ldap claims still validates
ok 1072 hub recovery records: retired osixia ldap claims are not captured
ok 1073 _hub_recovery_sync_vault_root_token: accepts a matching Keychain read-back
ok 1074 _hub_recovery_sync_vault_root_token: rejects a mismatching Keychain read-back
ok 1075 _hub_recovery_sync_vault_root_token: rejects a failed Keychain read-back without exposing the token
ok 1076 hub_recovery_plan: emits the dependency map by logical claim
ok 1077 hub_recovery_validate: rejects a duplicate captured claim
ok 1078 hub_recovery_validate: rejects an unexpected PVC tree
ok 1079 hub_recovery_validate: ignores files below a mapped PVC root
ok 1080 hub_recovery_restore: plans all mapped claims by default
ok 1081 hub_recovery_restore: rejects a target with the wrong logical claim
ok 1082 hub_recovery_targets: renders exactly one current PV target per claim
ok 1083 hub_recovery_targets: rejects a PV assigned to the wrong node
ok 1084 _hub_recovery_render_cloudflared_config: k3d overrides only the frontend origin
ok 1085 _hub_recovery_render_cloudflared_config: hostinger and unknown providers preserve config
ok 1086 _hub_recovery_install_cloudflared_config: app context frontend uses k3s-hostinger
ok 1087 _hub_recovery_install_cloudflared_config: only hub frontend uses k3d
ok 1088 _hub_recovery_install_cloudflared_config: missing frontend keeps k3s-hostinger with warning
ok 1089 _hub_recovery_install_cloudflared_config: explicit provider override wins
ok 1090 hub_recovery_reconcile: dry run prints steps and invokes no operations
ok 1091 _hub_recovery_retry_failed_identity_sync: Failed phase requests one cicd patch
ok 1092 _hub_recovery_retry_failed_identity_sync: Succeeded, Running and empty phases do not patch
ok 1093 _hub_recovery_retry_failed_identity_sync: patch failure is non-fatal
ok 1094 hub_recovery_reconcile: hostnet drift runs after serverlb and failure is non-fatal
ok 1095 hub_recovery_reconcile: confirm invokes app-cluster registration reconcile
ok 1096 hub_recovery_reconcile: restores signing after ESO policy with a pinned context
ok 1097 hub_recovery_reconcile: signing restore failure warns and continues
ok 1098 _hub_recovery_restore_signing: pins the hub context and removes the temp kubeconfig
ok 1099 _hub_recovery_restore_signing: a pin failure warns, skips the restore and leaves no temp file
ok 1100 hub_recovery_reconcile: the dry list names the cosign step
ok 1101 hub_recovery never generates or rotates a signing key
ok 1102 _hub_recovery_render_serverlb_values: servers on 6443, servers then agents on 80/443
ok 1103 _hub_recovery_render_serverlb_values: fails with no server container
ok 1104 _hub_recovery_serverlb_upstream_pairs: empty inline lists yield no pairs
ok 1105 _hub_recovery_ensure_serverlb_upstreams: matching upstreams do not restart the LB
ok 1106 _hub_recovery_ensure_serverlb_upstreams: empty upstreams rewrite values and restart only the LB
ok 1107 _hub_recovery_ensure_serverlb_upstreams: fails when the host API never becomes ready
ok 1108 _hub_recovery_ensure_serverlb_upstreams: unreadable LB values fail without restart
ok 1109 _hub_recovery_mirror_argocd_admin: skips a Vault entry that already has a password
ok 1110 _hub_recovery_mirror_argocd_admin: stores an ArgoCD-verified initial password
ok 1111 _hub_recovery_mirror_argocd_admin: does not store a rejected initial password
ok 1112 _hub_recovery_mirror_argocd_admin: skips an absent initial secret
ok 1113 _hub_recovery_mirror_argocd_admin: retries until the initial secret appears
ok 1114 _hub_recovery_mirror_argocd_admin: exhausted secret retry stays non-fatal
ok 1115 _hub_recovery_mirror_argocd_admin: fails when the Vault root token is absent
ok 1116 hub_recovery_reconcile: hub self-registration uses its own cluster name, not ubuntu-k3s
ok 1117 hub snapshot: guard accepts a fresh verified snapshot
ok 1118 hub snapshot: delete guard accepts a fresh data-repo export without SSH
ok 1119 hub snapshot: guard reads verified snapshots during dry-run
ok 1120 hub snapshot: guard refuses an old verified snapshot
ok 1121 hub snapshot: old data export and unreachable M2 fail
ok 1122 hub snapshot: inaccessible data repo falls through to M2
ok 1123 hub snapshot: guard refuses incomplete-only snapshots
ok 1124 hub snapshot: guard refuses an unreachable M2
ok 1125 hub snapshot: malformed age name fails
ok 1126 hub snapshot: capture emits the restore layout
ok 1127 hub snapshot: tree names satisfy hub recovery claim tree
ok 1128 hub snapshot: claim archive lists fixture files
ok 1129 hub snapshot: node placement comes from the PV
ok 1130 hub snapshot: PV hostname maps to one logical docker container
ok 1131 hub snapshot: unbound claim fails closed
ok 1132 hub snapshot: capture probes remote free space once
ok 1133 hub snapshot: checksum mismatch marks incomplete
ok 1134 hub snapshot: rsync stages under incomplete and renames after verification
ok 1135 hub snapshot: failing rsync leaves incomplete without rename or stamp
ok 1136 hub snapshot: capture writes stamp after verification
ok 1137 hub snapshot: prune keeps the configured verified snapshots
ok 1138 hub snapshot: capture auto-prunes to newest verified snapshots
ok 1139 hub snapshot: auto-prune leaves incomplete entries
ok 1140 hub snapshot: auto-prune can be disabled
ok 1141 hub snapshot: auto-prune failure does not fail capture
ok 1142 hub snapshot: insufficient space fails before rsync
ok 1143 hub snapshot: non-numeric free space fails closed
ok 1144 hub snapshot: rename failure leaves capture unverified
ok 1145 hub snapshot: prune removes incomplete snapshots first
ok 1146 hub snapshot: prune refuses zero verified snapshots
ok 1147 hub snapshot: unreachable M2 names the host and leaves no remote directory
ok 1148 hub snapshot: staging is removed after a mid-capture failure
ok 1149 hub snapshot: staging directory is 0700
ok 1150 hub snapshot: Loki record is present
ok 1151 hub snapshot: remote dir default survives single-quoting on the remote shell
ok 1152 hub snapshot: retain patches Delete and skips Retain
ok 1153 hub snapshot: retain processes remaining claims after missing PVC
ok 1154 _istio_ambient_cni_dirs returns k3d paths
ok 1155 _istio_ambient_cni_dirs returns k3s-hostinger paths
ok 1156 _istio_ambient_cni_dirs defaults unknown providers to Cilium paths
ok 1157 _istio_ambient_cni_provider_is_specific accepts k3d and k3s-hostinger
ok 1158 _istio_ambient_cni_provider_is_specific rejects unknown, empty and bare k3s
ok 1159 deploy_istio_ambient skips provider lookup when CNI dirs are preset
ok 1160 deploy_jenkins skips when ENABLE_JENKINS unset
ok 1161 deploy_jenkins skips when ENABLE_JENKINS=0
ok 1162 keycloak rotator: CronJob has identity schedule and concurrency policy
ok 1163 keycloak rotator: Vault payload preserves db_password
ok 1164 keycloak rotator: never mutates keycloak-secrets ExternalSecret
ok 1165 keycloak rotator: uses the master realm
ok 1166 keycloak rotator: rollback trap precedes reset-password
ok 1167 keycloak rotator: password is not placed in URL or -u argv
ok 1168 keycloak rotator: no request body carrying a password is passed in argv
ok 1169 keycloak rotator: every curl is captured or redirected
ok 1170 keycloak rotator: apply path applies the manifest
ok 1171 keycloak rotator: apply path configures the exact Vault role
ok 1172 keycloak rotator: absent manifest is a no-op
ok 1173 keycloak rotator: absent Vault role helper is safe
ok 1174 keycloak RETURN traps are self-clearing
ok 1175 deploy_keycloak --help shows usage
ok 1176 deploy_keycloak skips when CLUSTER_ROLE=app
ok 1177 KEYCLOAK_NAMESPACE defaults to identity
ok 1178 KEYCLOAK_HELM_RELEASE defaults to keycloak
ok 1179 deploy_keycloak rejects unknown option
ok 1180 _keycloak_seed_vault_admin_secret function exists
ok 1181 _keycloak_reconcile_realm_client function exists
ok 1182 smoke admin Secret falls back to keycloak-secrets
ok 1183 smoke admin Secret keeps preferred Secret when both exist
ok 1184 smoke admin Secret keeps preferred Secret when neither exists
ok 1185 _keycloak_reconcile_realm_client updates argocd redirect URIs # skip shopping-cart-infra realm fixture not reachable: /Users/cliang/src/gitrepo/personal/k3d-manager/scripts/tests/plugins/../../../../shopping-carts/shopping-cart-infra/identity/keycloak/realm-shopping-cart.json
ok 1186 smoke admin token supports the deployed password-only admin Secret
ok 1187 _keycloak_remove_client_attribute deletes stale pkce attribute rows
ok 1188 KEYCLOAK_CONFIG_CLI_ENABLED defaults to false
ok 1189 test_keycloak function exists
ok 1190 smoke seed prefers Vault password and does not run openssl
ok 1191 smoke Vault preseed writes absent entry with four fields and a 48-hex password
ok 1192 smoke Vault preseed leaves present entry untouched
ok 1193 smoke Vault preseed forces ESO refresh after a successful put
ok 1194 smoke Vault preseed skips ESO refresh when ExternalSecret is absent
ok 1195 smoke Vault preseed skips ESO refresh when the put fails
ok 1196 smoke seed reuses legacy password and writes all Vault fields
ok 1197 smoke seed generates a password when Vault and legacy Secret are empty
ok 1198 smoke seed and provision never create the smoke Secret
ok 1199 smoke Vault hygiene keeps token and password out of kubectl argv
ok 1200 smoke Vault write failure warns and returns zero
ok 1201 smoke cleanup deletes an unowned legacy Secret
ok 1202 smoke cleanup preserves an ESO-owned Secret
ok 1203 LDAP chart passwords: only sed-safe values are retained
ok 1204 LDAP chart passwords: generated values are delimiter-safe hex
ok 1205 rendered rotator uses portable password generation
ok 1206 generate_password returns 48 lowercase hexadecimal characters without openssl
ok 1207 empty password guard precedes the LDAP update
ok 1208 Vault preflight precedes the user loop and does not use the token
ok 1209 password rotator deploy derives the Vault address from VAULT_NS
ok 1210 loadtest: green gates increase and reset breach count
ok 1211 loadtest: first breach holds with hysteresis
ok 1212 loadtest: second consecutive breach stops
ok 1213 loadtest: each hard stop condition appears in breach list
ok 1214 loadtest: strict thresholds keep 2/2/80 green
ok 1215 loadtest: stage ladder caps at 5000
ok 1216 loadtest: confirmation gate refuses without explicit opt-in
ok 1217 loadtest: token endpoint is derived from the issuer
ok 1218 loadtest: mint token refuses without user credentials
ok 1219 loadtest: default PromQL gate queries are well-formed
ok 1220 loadtest: prom query returns 0 for empty/failed result
ok 1221 loadtest: prom query parses a scalar value
ok 1222 loadtest: prom flag maps positive to 1 and zero to 0
ok 1223 loadtest: fetch metrics emits the 8-positional snapshot
ok 1224 loadtest: dry-run ramps through green stages and writes a summary each
ok 1225 loadtest: dry-run stops after hysteresis on a persistent breach
ok 1226 loadtest: stage summary is valid and immutable
ok 1227 ACG PrometheusRule CRD wait reads Established condition
ok 1228 ACG PrometheusRule CRD wait no longer invokes kubectl wait
ok 1229 ACG discovery check accepts a served Prometheus kind
ok 1230 ACG discovery check warns when Prometheus kind is unserved
ok 1231 ACG Step 14b recovery hint escapes the port-forward PID
ok 1232 ACG discovery warning follows successful PrometheusRule apply
ok 1233 ACG Step 14b puts Prometheus port-forward inside the Service guard
ok 1234 no Alertmanager CR returns zero
ok 1235 empty configSecret returns zero
ok 1236 present config secret returns zero and logs info
ok 1237 absent config secret returns one and warns every alert is discarded
ok 1238 failure names the Alertmanager and secret
ok 1239 apiserver scrape timeout: patches unset endpoint to 45s
ok 1240 apiserver scrape timeout: skips an already matching endpoint
ok 1241 apiserver scrape timeout: honors the environment override
ok 1242 apiserver scrape timeout: missing ServiceMonitor is non-fatal
ok 1243 apiserver scrape timeout: patch payload changes only scrapeTimeout
ok 1244 deploy_observability: ensures apiserver timeout after ArgoCD ServiceMonitors
ok 1245 every deployment panel aggregates job_id away
ok 1246 the webhook harness neutralizes the Pushgateway
ok 1247 hub istiod keeps only http-monitoring
ok 1248 hub istiod port rule action is keep
ok 1249 hub istiod service-name keep remains additive
ok 1250 acg istiod keeps only http-monitoring
ok 1251 acg istiod port rule action is keep
ok 1252 acg istiod service-name keep remains additive
ok 1253 federate-acg drops self-scraped samples
ok 1254 federate-acg selects raw series only
ok 1255 federate-acg excludes k3s control-plane histograms
ok 1256 federate-acg timeout stays below interval
ok 1257 federate-acg job selector is unchanged
ok 1258 federate-acg labels the target acg and honors source labels
ok 1259 image updater replica stats aggregate
ok 1260 argocd dashboard JSON parses
ok 1261 _observability_seed_grafana_if_absent skips a present credential
ok 1262 _observability_seed_grafana_if_absent writes an absent credential once
ok 1263 observability_seed_grafana is a declared function
ok 1264 observability_seed_grafana logs in and delegates to the private seed
ok 1265 _observability_apply_grafana_rotator logs in to Vault before seeding
ok 1266 observability ServiceMonitors: renders live release values and applies only ServiceMonitors
ok 1267 observability ServiceMonitors: exits cleanly when the CRD never appears
ok 1268 observability ServiceMonitors: exits cleanly when the release is missing
ok 1269 deploy_observability: promotes credential-free hub setup before Vault reads
ok 1270 k3dm-tests rules select the app-cluster stack, not the hub stack
ok 1271 k3dm-tests rules live on the app cluster only
ok 1272 all six k3dm test-suite alerts are present
ok 1273 OfflineSuiteVacuous names the result label value
ok 1274 every k3dm alert carries a non-empty expr
ok 1275 OfflineSuiteRunMissed keys on the per-run timestamp, not the last success
ok 1276 the ACG rules dir is applied to the app cluster by the observability plugin
ok 1277 PrometheusRule CRD wait allows rules apply after delayed creation
ok 1278 PrometheusRule CRD wait skips apply when creation never completes
ok 1279 keep-list predicate: in-list returns 0
ok 1280 keep-list predicate: not-in-list returns 1
ok 1281 keep-list predicate: empty keep-list returns 1
ok 1282 keep-list predicate: whole-word guard returns 1 both directions
ok 1283 keep-list predicate: multi-entry list returns 0
ok 1284 observability remove dashboard: missing configmap does not abort
ok 1285 prometheus reseed: healthy Vault credential does not write
ok 1286 prometheus reseed: readable cache password is reused
ok 1287 prometheus reseed: missing cache generates and writes a credential
ok 1288 prometheus reseed: literal password cache value is unusable
ok 1289 prometheus reseed: failed write remains a failure through refresh
ok 1290 values file does not fully qualify the repository
ok 1291 vars file exports CF_DOMAIN with an environment override
ok 1292 rules apply path runs envsubst
ok 1293 every rules placeholder is in the rules envsubst allowlist
ok 1294 every Probe target is CF_DOMAIN-suffixed
ok 1295 the ACG PrometheusRules apply cannot report success on failure
ok 1296 layer normalizer: 1 stays 1
ok 1297 layer normalizer: 2 stays 2
ok 1298 layer normalizer: empty defaults to 2
ok 1299 layer normalizer: 9 defaults to 2
ok 1300 layer normalizer: foo defaults to 2
ok 1301 platform-ops Application template enables server-side diff
ok 1302 platform-ops ApplicationSet retains server-side apply
ok 1303 platform-ops ExternalSecret and ApplicationSet do not mask differences
ok 1304 platform-ops rotators use BusyBox-compatible base64 -d
ok 1305 platform-ops rotators decode Kubernetes Secret data
ok 1306 new bug doc without Priority is rejected
ok 1307 new bug doc with P2 is accepted
ok 1308 modified legacy bug doc without Priority is accepted
ok 1309 the staged copy is checked, not the working tree
ok 1310 credential drift: no drift matches all stores in check mode
ok 1311 credential drift: postgres drift is reported in check mode
ok 1312 credential drift: postgres apply fixes and restarts only its consumer
ok 1313 credential drift: rabbitmq apply restarts each consumer once
ok 1314 credential drift: redis apply restarts the store and basket consumer
ok 1315 credential drift: apply keeps secret values out of kubectl calls
ok 1316 credential drift: context is required
ok 1317 token mode emits tokenSecretRef block
ok 1318 default (no arg) is token mode
ok 1319 kubernetes mode emits kubernetes auth block with defaults
ok 1320 kubernetes mode honors mount/role overrides
ok 1321 kubernetes mode reflects derived per-context mount when override unset
ok 1322 shopping cart GHCR pull secret keeps the PAT off kubectl argv
ok 1323 shopping-cart-namespace app owns the namespace and ghcr pull secret manifests
ok 1324 shopping-cart-frontend deployment uses ghcr pull secret
ok 1325 reuses existing redis and rabbitmq secrets without PUT for those paths
ok 1326 puts redis and rabbitmq secrets when absent
ok 1327 seed helpers honor SEED_VAULT_ADDR instead of localhost port
ok 1328 copies redis/cart from canonical source Vault when absent in target
ok 1329 copies minio/credentials (multi-field) from canonical source Vault when absent in target
ok 1330 reuses existing payment/encryption without PUT
ok 1331 reuses existing payment/stripe without PUT
ok 1332 reuses existing payment/paypal without PUT
ok 1333 copies payment/encryption from canonical source instead of writing the default
ok 1334 copies payment/stripe from canonical source instead of writing the placeholder
ok 1335 copies payment/paypal from canonical source instead of writing the sandbox default
ok 1336 seed URL carries _vault_local_port set after the plugin was sourced (no empty-port freeze)
ok 1337 vault helpers work without prior seed-local temp state
ok 1338 put surfaces HTTP status and path on a non-2xx write, then fails
ok 1339 deploy_app_cluster prints help with --help
ok 1340 deploy_app_cluster requires --confirm
ok 1341 deploy_app_cluster fails if k3sup not found
ok 1342 local k3s kubeconfig keeps loopback endpoint for tunneled TLS
ok 1343 keeps default when a context still references it
ok 1344 prunes default when nothing references it
ok 1345 add_ubuntu_k3s_cluster does not unconditionally delete default kubeconfig entries
ok 1346 register_shopping_cart_apps fails if argocd dir missing # skip shopping-cart-infra repo detected alongside k3d-manager
ok 1347 _ensure_k3sup returns 0 when k3sup is already installed
ok 1348 _ensure_k3sup errors when k3sup absent and no installer available
ok 1349 shopping_cart bootstrap helpers exist
ok 1350 _shopping_cart_resolve_app_context follows the active provider context
ok 1351 _shopping_cart_vault_externalsecrets includes the GHCR pull secret
ok 1352 _ensure_k3sup returns 0 after successful brew install
ok 1353 _ensure_k3sup returns 0 after successful curl install on debian
ok 1354 SSH readiness fails after the configured budget with offline stubs
ok 1355 SSH readiness succeeds when the second probe answers
ok 1356 server install does not invoke k3sup when SSH preflight fails
ok 1357 agent joins fan out in parallel and wait for every worker
ok 1358 agent join failures are collected without aborting other workers
ok 1359 already-ready agents are skipped on an idempotent rerun
ok 1360 _k3sup_join_agent reserves kubelet memory by default
ok 1361 _k3sup_join_agent honours K3S_KUBELET_RESERVED_ARGS
ok 1362 deploy_app_cluster passes kubelet reservations to k3sup install
ok 1363 _k3s_agent_is_ready matches node InternalIP, not ssh alias or public IP
ok 1364 _k3s_agent_is_ready is false when the matched node is NotReady
ok 1365 GHCR pull probe succeeds after token exchange and tags list
ok 1366 GHCR pull probe rejects a 403 tags list
ok 1367 GHCR pull probe rejects an empty token exchange
ok 1368 gh CLI PAT is not stored when the pull probe fails
ok 1369 gh CLI pull failure names gh auth refresh
ok 1370 prompt reports HTTP 401 for a dead pasted token
ok 1371 prompt reports missing scope for a valid pasted token
ok 1372 resolve error names gh auth refresh
ok 1373 GHCR path does not pass Vault token or PAT in curl argv
ok 1374 deploy_image_signing --help prints usage
ok 1375 deploy_image_signing --enforce is gated behind SIGNING_ALLOW_ENFORCE
ok 1376 deploy_image_signing rejects unknown option
ok 1377 deploy_image_signing --help documents --app-cluster
ok 1378 _signing_install_kyverno pins the chart version (no floating latest)
ok 1379 _signing_install_kyverno appends --set for each SIGNING_KYVERNO_HELM_SET entry
ok 1380 _signing_install_kyverno emits no --set when SIGNING_KYVERNO_HELM_SET is empty
ok 1381 _signing_install_kyverno skips repo ops for a local chart path
ok 1382 _signing_render_policy injects the public key under publicKeys
ok 1383 _signing_render_policy never leaks a private key
ok 1384 rendered policy is namespace-scoped to app namespaces only
ok 1385 rendered policy gates workload controllers, not bare Pod (401 root-cause fix)
ok 1386 rendered policy scopes verifyImages to first-party registry, not wildcard
ok 1387 rendered policy uses Kyverno 1.19 tlog/SCT field names (not bare 'ignore')
ok 1388 rendered policy defaults to Audit (never Enforce by default)
ok 1389 rendered policy honors Enforce when explicitly requested
ok 1390 rendered policy requires a cosign vuln attestation (ADMIT latch)
ok 1391 rendered policy is valid YAML with the key injected at BOTH depths
ok 1392 attestation block inherits the staged failureAction (no separate gate)
ok 1393 signing.sh never passes cosign key/password as a bare CLI argument
ok 1394 signing_restore is a declared function
ok 1395 _signing_grant_eso_read honors the configured ESO auth mount
ok 1396 _signing_grant_eso_read fails without writing when the role read is not JSON
ok 1397 _signing_grant_eso_read fails and does not log granted when the role write fails
ok 1398 _signing_grant_eso_read appends the policy without a leading comma on an empty policy list
ok 1399 signing_restore returns non-zero when the ESO grant fails but still applies the ExternalSecret
ok 1400 signing_restore preserves present key material and reapplies configuration
ok 1401 signing_restore restores absent key material from a backup
ok 1402 signing_restore fails without Vault key or Keychain backup
ok 1403 _signing_apply_pub_externalsecret skips when admission namespace is absent
ok 1404 _signing_apply_pub_externalsecret applies when admission namespace exists
ok 1405 signing_restore logs into Vault before probing key material
ok 1406 signing_init prefers restore over regenerate when a backup exists
ok 1407 ask-docs relay is allowed and reader-scoped
ok 1408 ask-docs relay validates text and sends its own endpoint
ok 1409 ask-docs webhook route and policy are reader-scoped
ok 1410 ask-docs does not alter the ask endpoint
ok 1411 slack relay uses waitUntil for slash command dispatch
ok 1412 slack relay cluster-status acks before webhook completes
ok 1413 slack relay can post a fallback response_url error
ok 1414 slack commands doc lists the cluster-status slash commands
ok 1415 slack commands doc manifest matches the relay command set
ok 1416 slack commands doc gives a concrete example for each command
ok 1417 slack commands doc fix mode names the real FIX_CONTEXT override
ok 1418 slack relay allowlist includes cluster-status and hostinger-status
ok 1419 slack relay assigns remote-operator roles to cluster commands
ok 1420 slack relay forwards remote-operator metadata headers
ok 1421 slack relay parses cluster-diagnose payloads
ok 1422 smoke: all checks pass
ok 1423 smoke: failing offline check fails
ok 1424 smoke: unreachable context skips cluster
ok 1425 smoke: reachable failing cluster fails
ok 1426 smoke: offline filter never invokes cluster
ok 1427 smoke: invalid filter prints usage
ok 1428 smoke: later checks run after a failure
ok 1429 ssm_wait prints help with --help
ok 1430 ssm_exec prints help with --help
ok 1431 ssm_tunnel prints help with --help
ok 1432 _ssm_get_instance_id returns error for unknown alias
ok 1433 ssm_exec fails when jq is absent
ok 1434 ssm_wait timeout returns 1 so callers can fall back
ok 1435 trivy observability: charts pin trivy-operator 0.34.0 in both application sets
ok 1436 trivy observability: chart values enable serviceMonitor scraping
ok 1437 trivy observability: scanner image tag is explicitly pinned in both values files
ok 1438 trivy observability: both values files enable the built-in trivy server (ClientServer mode)
ok 1439 trivy observability: acg trivy application set uses the acg-specific values file
ok 1440 trivy observability: dashboard exposes log and metric panels for trivy-system
ok 1441 trivy observability: prometheus rule and alertmanager route cover scan job failures
ok 1442 trivy observability: acg values skip kube-system and run one scan job at a time
ok 1443 trivy observability: hub values skip the ephemeral e2e vCluster namespace
ok 1444 tunnel_status reports not running when process absent
ok 1445 tunnel_status reports running when process present
ok 1446 tunnel_start fails when autossh not installed
ok 1447 tunnel_start is idempotent when already running
ok 1448 tunnel_stop is idempotent when not running
ok 1449 tunnel_start writes plist and calls launchctl load
ok 1450 main tunnel plist contains only the API forward
ok 1451 vault agent clears stale 8200 and owns the reverse forward
ok 1452 tunnel_start migrates a running main plist that still has the reverse forward
ok 1453 tunnel_stop unloads the vault agent when loaded
ok 1454 tunnel.sh does not disguise sudo
ok 1455 vault app auth: skips enable when auth mount already exists
ok 1456 _vault_exec: passes VAULT_TOKEN as env arg instead of embedding it in shell command
ok 1457 configure_vault_app_auth exits 1 when APP_CLUSTER_API_URL is unset
ok 1458 configure_vault_app_auth exits 1 when APP_CLUSTER_CA_CERT_PATH is unset
ok 1459 configure_vault_app_auth exits 1 when CA cert file missing
ok 1460 configure_vault_app_auth calls vault commands with correct args
ok 1461 configure_vault_app_auth skips policy creation if it exists
ok 1462 configure_vault_app_auth is idempotent
ok 1463 _vault_app_auth_mount derives mount from context
ok 1464 _vault_app_auth_mount sanitizes uppercase and invalid chars
ok 1465 _vault_app_auth_mount falls back to kubernetes-app for empty context
ok 1466 _vault_app_auth_mount honors APP_K8S_AUTH_MOUNT override
ok 1467 configure_vault_app_auth_for_context exits 1 when context arg is missing
ok 1468 configure_vault_app_auth_for_context skips when context has no server
ok 1469 configure_vault_app_auth_for_context returns non-zero when required and server missing
ok 1470 configure_vault_app_auth_for_context returns non-zero when required and CA missing
ok 1471 configure_vault_app_auth_for_context derives server and temp CA then cleans it up
ok 1472 vault cache: override routes cache reads, writes, and clears to the drill service
ok 1473 vault cache: unset override preserves the host service
ok 1474 vault DR shards: save stores two shards under secrets/vault without exposing values
ok 1475 vault DR shards: export and import round-trip through stdin
ok 1476 vault DR shards: export refuses a terminal
ok 1477 vault DR shards: drill init does not save durable shards
ok 1478 vault DR shards: normal cache clear does not clear durable service
ok 1479 vault DR shards: export with no stored shards says why and prints nothing
ok 1480 vault DR shards: import rejects a stream whose first line is not a count
ok 1481 vault DR shards: import strips CRs from a copied export
ok 1482 vault DR shards: import refuses a malformed shard without storing or printing it
ok 1483 vault DR shards: export refuses a malformed stored shard without printing it
ok 1484 vault DR shards: the dispatcher banner stays off stdout
ok 1485 _vault_hub_fallback_profile maps hostinger -> laptop
ok 1486 _vault_hub_fallback_profile maps laptop (and default) -> hostinger
ok 1487 _vault_health_status_ok accepts 200/429/472/473, rejects others
ok 1488 vault_failover_hub_into_context requires an app cluster kube-context
ok 1489 vault_failover_hub_into_context rejects unknown kube-contexts
ok 1490 vault_failover_hub_into_context rejects unknown flags
ok 1491 vault init wait: returns once the API answers
ok 1492 vault init wait: gives up when the API never answers
ok 1493 vault init error lines: shows errors, never key material
ok 1494 vault init: never retries once Vault reports initialised
ok 1495 vault init: retries while Vault is still uninitialised
ok 1496 vault init: gives up after the attempt limit
ok 1497 vault is_initialized: reads the initialized field
ok 1498 vault init: a dropped read is retried and the keys come back
ok 1499 vault init: keys left in the pod when they cannot be read back
ok 1500 vault init: stops when init never finishes
ok 1501 _vault_role_merged_policies: desired first, existing extras appended, default and duplicates dropped
ok 1502 _vault_role_merged_policies: unreadable role yields desired only
ok 1503 _vault_role_merged_policies shell-escapes the role path in the read command
ok 1504 configure_vault_app_auth preserves an existing cosign-verify grant
ok 1505 _vault_configure_secret_reader_role preserves an existing cosign-verify grant
ok 1506 vault_seed_hub_into_context requires an app cluster kube-context
ok 1507 vault_seed_hub_into_context rejects unknown kube-contexts
ok 1508 vault_seed_hub_into_context canonical key list contains exactly 13 keys
ok 1509 _vault_exec keeps token out of kubectl argv and sends it on stdin
ok 1510 _vault_exec_stream --stdin multiplexes token line then payload
ok 1511 _vault_exec_stream session branch without --stdin sends only token line
ok 1512 __vault_exec_kubectl --exec-stdin replays stdin across a retry
ok 1513 __vault_exec_kubectl without --exec-stdin runs under set -u
ok 1514 deploy_vault -h shows usage
ok 1515 _vault_build_policy_hcl: eso-apps prefixes are read-only and scoped
ok 1516 deploy_vault loads optional config when vars file exists
ok 1517 Namespace setup
ok 1518 Helm repo setup
ok 1519 _is_vault_health treats healthy HTTP statuses as success
ok 1520 _is_vault_health ignores prompts and deletion digits for healthy status
ok 1521 _is_vault_health fails for unhealthy HTTP statuses
ok 1522 _is_vault_health fails for unhealthy status in kubectl run output
ok 1523 _is_vault_health retries unhealthy statuses before succeeding
ok 1524 _is_vault_health fails after three unhealthy statuses
ok 1525 _vault_enable_pki skips enabling when mount exists
ok 1526 _vault_pki_issue_tls_secret forwards overrides to secret issuance
ok 1527 _vault_issue_pki_tls_secret revokes existing certificate
ok 1528 _vault_issue_pki_tls_secret skips revoke when secret missing
ok 1529 _vault_post_revoke_request skips revoke when cert is already gone
ok 1530 Full deployment
ok 1531 _vault_seed_ldap_service_accounts seeds secret and policy when missing
ok 1532 _vault_bootstrap_ha uses release selector and unseals listed pods
ok 1533 _vault_bootstrap_ha errors when vault health check fails
ok 1534 _vault_bootstrap_ha reports ready when health check succeeds
ok 1535 _vault_is_sealed returns 0 when Vault is sealed
ok 1536 _vault_is_sealed returns 1 when Vault is unsealed
ok 1537 _vault_is_sealed returns 2 when status cannot be determined
ok 1538 _vault_plan_report surfaces missing components
ok 1539 _vault_plan_report reports success when Vault ready
ok 1540 reconcile: deletes only the non-kept JSON cluster
ok 1541 reconcile: empty JSON list does not delete
ok 1542 reconcile: colored table output does not delete
ok 1543 reconcile: delete failure falls back to helm uninstall
ok 1544 vcluster_create: uses foundation-managed CLI path
ok 1545 _vcluster_check_prerequisites: stores the contract path
ok 1546 foundation contract failure stops before lifecycle work
ok 1547 empty foundation contract path stops before lifecycle work
ok 1548 vcluster_create: honors VCLUSTER_VALUES_FILE override
ok 1549 vcluster_create: fails without active host context
ok 1550 vcluster_create: dry-run prints plan without executing
ok 1551 vcluster_destroy: dry-run prints plan without executing
ok 1552 vcluster_destroy: fails on unknown cluster name
ok 1553 vcluster_destroy: a stale kubeconfig is not proof the vCluster exists
ok 1554 vcluster_destroy: a missing vCluster returns instead of exiting its caller
ok 1555 vcluster_list: uses the contract-returned CLI path
ok 1556 vcluster_destroy: uses the contract-returned CLI path
ok 1557 vcluster_use: fails when kubeconfig file missing
ok 1558 VCLUSTER_VERSION defaults to 0.32.1
ok 1559 VCLUSTER_NAMESPACE defaults to vclusters
ok 1560 VCLUSTER_LOCAL_PORT defaults to 11443
ok 1561 VCLUSTER_SKIP_VERSION_CHECK defaults to true and reaches the CLI environment
ok 1562 _vcluster_export_kubeconfig pins --local-port so the kubeconfig port survives proxy re-creation
ok 1563 _vcluster_export_kubeconfig honours VCLUSTER_LOCAL_PORT override
ok 1564 _vcluster_refresh_connection requires a name
ok 1565 _vcluster_refresh_connection removes the stale proxy and reconnects on the pinned port
ok 1566 _vcluster_deregister_from_hub: deletes hub cluster secret and preflight resources
ok 1567 vcluster_create deletes an orphan occupying the shared namespace
ok 1568 vcluster_create deletes the orphan before creating the new vCluster
ok 1569 vcluster_create warns when it clears an orphan so a teardown regression stays visible
ok 1570 vcluster_create does not delete a vCluster matching the name being created
ok 1571 vcluster_create issues no delete when the namespace holds no vCluster
ok 1572 vcluster_create dry-run clears no orphan
ok 1573 orphan cleanup falls back to helm uninstall when vcluster delete fails
ok 1574 vectordb rules target the hub prometheus stack
ok 1575 both vectordb alerts are present
ok 1576 automatic indexing alerts use the requested windows
ok 1577 VectorDBMetricsStale watches push age, not absence alone
ok 1578 VectorDBMetricsStale still covers the never-published case
not ok 1579 absence alone is not the whole staleness expression
# (in test file scripts/tests/plugins/vectordb_rules.bats, line 49)
#   `' "${RULES}")"' failed
# Traceback (most recent call last):
#   File "<string>", line 2, in <module>
# ModuleNotFoundError: No module named 'yaml'
ok 1580 VectorDBIndexStale keeps the seven-day index threshold
ok 1581 dashboard has six ingestion panels using emitted metrics
ok 1582 vectordb dashboard is no longer in the app-cluster dashboard folder
not ok 1583 every rule keeps string labels and its own annotations
# (in test file scripts/tests/plugins/vectordb_rules.bats, line 108)
#   `[ "${status}" -eq 0 ]' failed
Test log saved to scratch/test-logs/all/20261028-113906.log
Collected artifacts in scratch/test-logs/all/20261028-113906
[tripwire] blocked 426 call(s) to host tools; none reached a real binary:
     84 kubectl	--context ubuntu-k3s --request-timeout=5s get --raw=/readyz
     84 kubectl	--context ubuntu-hostinger --request-timeout=5s get --raw=/readyz
     84 kubectl	--context ubuntu-gcp --request-timeout=5s get --raw=/readyz
     84 kubectl	--context ubuntu-azure --request-timeout=5s get --raw=/readyz
     37 security	find-generic-password -s k3dm-webhook-token-reader -a k3dm -w
     37 security	find-generic-password -s k3dm-webhook-token-cloud-runner -a k3dm -w
      5 gh	auth token
      5 aws	cloudformation describe-stacks --region us-west-2 --stack-name k3d-manager-cluster --query Stacks[0].StackStatus --output text
      1 security	find-generic-password -s platform-ops-git-writer -a k3dm -w
      1 security	find-generic-password -s platform-ops-app-rebuild -a k3dm -w
      1 security	find-generic-password -s k3dm-webhook-token -a k3dm -w
      1 security	find-generic-password -s k3dm-slack-signing-secret -a k3dm -w
      1 security	find-generic-password -s k3dm-slack-role-map -a k3dm -w
      1 kubectl	config get-contexts ubuntu-k3s
make[1]: *** [test] Error 1
```

## Python environment correction after operator feedback

Operator states Python3.11. Coordinator verified actual active M2 pane %10
contains these version labels/output (filtered read-only capture):

```text
%10 visible_python_labels=['python-3.11', 'Python 3.11.6', 'python-3.11']
```

Existing interpreter binaries checked without installation or environment
changes; actual output:

```text
/opt/homebrew/bin/python3 Python 3.15.1
/opt/homebrew/opt/python@3.11/bin/python3.11 Python 3.11.18
/Users/cliang/src/gitrepo/personal/.direnv/python-3.11/bin/python3 Python 3.11.6
```

Non-login SSH resolves /usr/bin/python3 as Python3.9.6, which is not the
operator's active interactive environment. Its optional python command is
absent; that diagnostic command exited127 after reporting python3:

```text
/usr/bin/python3
Python 3.9.6
zsh:4: command not found: python
```

Coordinator acknowledges the earlier3.13 instruction was an assumption.
Active M2 uses3.11.6; no Python replacement is requested or performed. The
old branch HEAD71ef4dea and missing yaml finding remain valid. Check each
host's actual test environment; do not infer it from non-login SSH defaults
or older prompt labels. M4 has no matching personal/.direnv/python-3.11
path; that does not establish its active shell interpreter.

No code, dependency installation, tests, metrics publication or terminal
keystrokes during version verification. Docs lint/audit/hooks only.
