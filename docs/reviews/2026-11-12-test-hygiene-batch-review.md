# Review brief: test-hygiene batch: tripwire catches host writes, fresh-clone fixes (Luna) — cross-vendor diff review

**Role:** review child of `test-hygiene-batch`.
**Intent approved:** operator, 2026-11-12
**Approval basis:** "dispatch as you suggest"; first-pass quality trial: cross-vendor diff review
**Spec under review:** `docs/bugs/2026-11-12-test-hygiene-batch-tripwire-host-writes-and-fresh-clone.md` (read it in full first).

## Files

Read-only: review these, change none of them.
- `Makefile`
- `scripts/ci/fast_gate.sh`
- `scripts/tests/bin/cluster_status_app_cluster_registration.bats`
- `scripts/tests/bin/machine_secrets.bats`
- `scripts/tests/bin/test_cloud_bridge.py`
- `scripts/tests/bin/test_test_tripwire.py`
- `scripts/tests/core/suite_discovery.bats`
- `scripts/tests/fixtures/agent-dispatch-dashboard-028b898f.yaml`
- `scripts/tests/host/machine_secrets_real_keychain.bats`
- `scripts/tests/lib/fast_gate.bats`
- `scripts/tests/lib/observability.bats`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `scripts/tests/tripwire.sh`

## Task

Review the worker's diff below against the spec: its Fix, Contract readers and Acceptance block. Report findings only. Do not edit, commit or keep any file. You may `git apply` the diff in your own worktree to run the touched suites and try mutations, but leave the worktree clean at exit (`git checkout -- . && git clean -fd`). Never touch the real Keychain, LaunchAgents, `launchctl`, GitHub, or a live Pushgateway.

For each finding give: severity (blocker / should-fix / nit); file:line in the diff; a concrete input or state that breaks it; the spec line (Fix item or M/N id) it violates.

Check in particular:
1. Each must_not (N1-N11): is there a test for exactly that state, and would it fail on the pre-fix code at 64b5fe27?
2. The tripwire plist watch: creation, removal, content change and identical-byte rewrite are all reported; a real run with no plist change reports nothing (positive control). Can a test still write to the real ~/Library/LaunchAgents or call real launchctl without the tripwire failing?
3. `make test-host` and the real-Keychain suite: never reachable from `make test`, `make test-bin`, fast-gate or CI; cleanup restores the keychain search list on every failure path; `test-host` is in NEVER_EXPOSED.
4. fast-gate: `BASE` no longer leaks into workers; host suites excluded; nothing else excluded by accident.
5. The committed dashboard fixture `scripts/tests/fixtures/agent-dispatch-dashboard-028b898f.yaml` (omitted from the diff below, sha256 607f2208...): the test now passes in a clone without commit 028b898f and still fails when the dashboard drifts.

End with a one-line verdict: `land`, `land after fixes`, or `rework`. Under 500 words.

## Worker diff (uncommitted, against `k3d-manager-v1.44.0` at the worker's base `64b5fe27`)

```diff
diff --git a/Makefile b/Makefile
index a584c7af..778a3991 100644
--- a/Makefile
+++ b/Makefile
@@ -107,7 +107,7 @@ install-test-metrics:
 	    "$(HOME)/Library/LaunchAgents/com.k3d-manager.test-metrics.plist"; \
 	fi
 
-.PHONY: check-agent-docs fast-gate up hub-up hub-restore hub-recover argocd-admin-resync down refresh fleet-render fleet-validate fleet-plan fleet-up cleanup-stale-sandbox cleanup-stale-clusters cleanup-stale-registration cleanup-stale-resources status status-full status-json status-public preflight creds chrome-cdp chrome-cdp-stop acg-watch acg-watch-stop acg-watch-check acg-restart acg-recover argocd-registration sync-apps sync-branch sync-main ssm provision install-sudoers setup-worker deploy-worker gh-secret gh-secret-sync-relay cloudflared-backup cloudflared-config alertmanager-secret alertmanager-config restore-google-app-password argocd-hermes-token hermes-approvals-kv hermes-drain-token hermes-approvers hermes-approvals-setup signing-restore backup restore test test-bin test-python-unit test-pytest test-alertmanager-behaviour check-doc-links check-release-milestones validate-manifests index-docs embed-cache-backup embed-cache-seed embed-cache-stats embed-cache-prune embed-cache-restore find-similar-docs check-repo-root test-python test-all test-metrics e2e e2e-sandbox e2e-sandbox-provision help observability platform-ops observability-acg observability-status monitoring-pause monitoring-resume vuln-scan trivy-scan-report app-cve-scan show-service-passwords shopping-cart-credential-drift update-webhook-slack update-webhook-slack-roles update-webhook-slack-secret webhook-log-level job-log harvest-job-failures restart-webhook restart-cloud-bridge install-vault-port-forward uninstall-vault-port-forward install-prometheus-port-forward uninstall-prometheus-port-forward install-hub-pushgateway-port-forward uninstall-hub-pushgateway-port-forward install-hub-loki-port-forward uninstall-hub-loki-port-forward dispatch-logs install-node-health-watch uninstall-node-health-watch install-sandbox-reaper uninstall-sandbox-reaper init-cloud-requests install-cloud-bridge uninstall-cloud-bridge clean-tmp e2e-remote e2e-runner-health e2e-replay e2e-republish e2e-runner-unlock refresh-registration vault-dr-shards-save vault-dr-shards-export vault-dr-shards-import hub-data-export dr-drill dr-drill-publish
+.PHONY: check-agent-docs fast-gate up hub-up hub-restore hub-recover argocd-admin-resync down refresh fleet-render fleet-validate fleet-plan fleet-up cleanup-stale-sandbox cleanup-stale-clusters cleanup-stale-registration cleanup-stale-resources status status-full status-json status-public preflight creds chrome-cdp chrome-cdp-stop acg-watch acg-watch-stop acg-watch-check acg-restart acg-recover argocd-registration sync-apps sync-branch sync-main ssm provision install-sudoers setup-worker deploy-worker gh-secret gh-secret-sync-relay cloudflared-backup cloudflared-config alertmanager-secret alertmanager-config restore-google-app-password argocd-hermes-token hermes-approvals-kv hermes-drain-token hermes-approvers hermes-approvals-setup signing-restore backup restore test test-bin test-host test-python-unit test-pytest test-alertmanager-behaviour check-doc-links check-release-milestones validate-manifests index-docs embed-cache-backup embed-cache-seed embed-cache-stats embed-cache-prune embed-cache-restore find-similar-docs check-repo-root test-python test-all test-metrics e2e e2e-sandbox e2e-sandbox-provision help observability platform-ops observability-acg observability-status monitoring-pause monitoring-resume vuln-scan trivy-scan-report app-cve-scan show-service-passwords shopping-cart-credential-drift update-webhook-slack update-webhook-slack-roles update-webhook-slack-secret webhook-log-level job-log harvest-job-failures restart-webhook restart-cloud-bridge install-vault-port-forward uninstall-vault-port-forward install-prometheus-port-forward uninstall-prometheus-port-forward install-hub-pushgateway-port-forward uninstall-hub-pushgateway-port-forward install-hub-loki-port-forward uninstall-hub-loki-port-forward dispatch-logs install-node-health-watch uninstall-node-health-watch install-sandbox-reaper uninstall-sandbox-reaper init-cloud-requests install-cloud-bridge uninstall-cloud-bridge clean-tmp e2e-remote e2e-runner-health e2e-replay e2e-republish e2e-runner-unlock refresh-registration vault-dr-shards-save vault-dr-shards-export vault-dr-shards-import hub-data-export dr-drill dr-drill-publish
 
 ## Export Hub Vault PKI root CA and trust it in macOS System Keychain (local GUI session required)
 trust-vault-ca:
@@ -1456,6 +1456,14 @@ test-bin:
 	   echo "[make] bats not found — install with: brew install bats-core" >&2; exit 2; }; \
 	 scripts/tests/tripwire.sh bats scripts/tests/bin
 
+## Run the real-host BATS suites under scripts/tests/host (macOS only, no tripwire)
+test-host:
+	@set -euo pipefail; \
+	 [ "$$(uname -s)" = Darwin ] || { echo "[make] test-host is macOS only" >&2; exit 2; }; \
+	 command -v bats >/dev/null 2>&1 || { echo "[make] bats not found — install with: brew install bats-core" >&2; exit 2; }; \
+	 echo "[make] test-host uses the real Keychain tool and your keychain search list; the suite restores the list"; \
+	 bats scripts/tests/host
+
 ## Run the stdlib-unittest Python suites (scripts/tests/bin/*.py, excluding test_*.py)
 test-python-unit:
 	@set -euo pipefail; \
@@ -1748,6 +1756,7 @@ help:
 	@echo "    make find-similar-docs Q=\"...\" [K=5]  Find prior art by similarity (advisory)"
 	@echo "    make test-all      Run every offline suite (BATS dispatcher + bin BATS + Python)"
 	@echo "    make test-bin      Run the BATS suites under scripts/tests/bin"
+	@echo "    make test-host     Run real-host BATS suites (macOS; real Keychain tool, restores your keychain search list)"
 	@echo "    make test-python   Run every Python suite (unittest + pytest)"
 	@echo "    make lint-python   Lint tracked Python files with Ruff (pyflakes)"
 	@echo "    make e2e           Run Tier 1 e2e harness (vCluster + Playwright Job; DIGEST=<image digest> optional)"
diff --git a/scripts/ci/fast_gate.sh b/scripts/ci/fast_gate.sh
index 2396a27a..5ea5a8f8 100755
--- a/scripts/ci/fast_gate.sh
+++ b/scripts/ci/fast_gate.sh
@@ -29,6 +29,7 @@ run_limited() {
   ' "${FAST_GATE_SUITE_TIMEOUT:-900}" "$@"
 }
 worker() {
+  unset BASE
   local work=$1 index=$2 kind=$3 file=$4 label="" begin=$SECONDS rc=0 no_tests=0
   local -a command=() pytest_cmd=() docs=()
   case "$kind" in
@@ -137,7 +138,7 @@ done <<< "$fixture_commits"
 git diff --name-only --diff-filter=ACMR "$base" HEAD > "$work/changed"
 : > "$work/tests"
 add_test() {
-  case "$1" in scripts/tests/*.bats|scripts/tests/test_*.py|scripts/tests/*/test_*.py) [[ -f "$1" ]] && printf '%s\n' "$1" >> "$work/tests" ;; esac
+  case "$1" in scripts/tests/host/*) return 0 ;; scripts/tests/*.bats|scripts/tests/test_*.py|scripts/tests/*/test_*.py) [[ -f "$1" ]] && printf '%s\n' "$1" >> "$work/tests" ;; esac
   return 0
 }
 while IFS= read -r file || [[ -n "$file" ]]; do
@@ -157,7 +158,7 @@ while IFS= read -r file; do
 done < "$work/changed"
 : > "$work/matched"
 if [[ -s "$work/patterns" ]]; then
-  find scripts/tests -type f \( -name '*.bats' -o -name 'test_*.py' \) -print0 |
+  find scripts/tests -type f -not -path 'scripts/tests/host/*' \( -name '*.bats' -o -name 'test_*.py' \) -print0 |
     xargs -0 grep -lF -f "$work/patterns" > "$work/matched" || true
 fi
 sort -u "$work/tests" -o "$work/tests"
diff --git a/scripts/tests/bin/cluster_status_app_cluster_registration.bats b/scripts/tests/bin/cluster_status_app_cluster_registration.bats
index 1843415d..f2bdb316 100644
--- a/scripts/tests/bin/cluster_status_app_cluster_registration.bats
+++ b/scripts/tests/bin/cluster_status_app_cluster_registration.bats
@@ -1,8 +1,27 @@
 #!/usr/bin/env bats
+bats_require_minimum_version 1.5.0
 
 setup() {
+  export REAL_HOME="$HOME"
+  export HOME="${BATS_TEST_TMPDIR}/home"
+  mkdir -p "$HOME"
   export STUB_BIN="${BATS_TEST_TMPDIR}/bin"
   mkdir -p "${STUB_BIN}"
+  export LAUNCHCTL_LOG="${BATS_TEST_TMPDIR}/launchctl.log"
+  : > "$LAUNCHCTL_LOG"
+  cat >"${STUB_BIN}/launchctl" <<'STUB'
+#!/usr/bin/env bash
+printf '%s\n' "$*" >> "$LAUNCHCTL_LOG"
+exit 0
+STUB
+  cat >"${STUB_BIN}/lsof" <<'STUB'
+#!/usr/bin/env bash
+exit 0
+STUB
+  cat >"${STUB_BIN}/security" <<'STUB'
+#!/usr/bin/env bash
+exit 1
+STUB
   cat >"${STUB_BIN}/kubectl" <<'STUB'
 #!/usr/bin/env bash
 if [[ "$*" == *"get secret cluster-ubuntu-k3s"* ]]; then
@@ -35,6 +54,14 @@ STUB
   export ARGOCD_NAMESPACE=cicd
 }
 
+@test "cluster-status restore path bootstraps launch agents under the test HOME" {
+  [[ "$(uname -s)" == Darwin ]] || skip "macOS only"
+  run bin/cluster-status
+  [ "$status" -eq 0 ]
+  grep -F "bootstrap gui/" "$LAUNCHCTL_LOG" | grep -F "$HOME/Library/LaunchAgents/com.k3d-manager.alertmanager-port-forward.plist"
+  run ! grep -F "$REAL_HOME/Library/LaunchAgents" "$LAUNCHCTL_LOG"
+}
+
 @test "cluster-status reports a present app-cluster registration" {
   APP_SECRET_PRESENT=true run bin/cluster-status
   [ "$status" -eq 0 ]
diff --git a/scripts/tests/bin/machine_secrets.bats b/scripts/tests/bin/machine_secrets.bats
index 8317c674..54fb9a8d 100644
--- a/scripts/tests/bin/machine_secrets.bats
+++ b/scripts/tests/bin/machine_secrets.bats
@@ -372,66 +372,6 @@ SH
   grep -Fq "this Mac's login Keychain password if that Keychain is locked" "$ROOT/docs/howto/machine-setup.md"
 }
 
-@test "machine secrets: real throwaway keychain round trip is macOS only" {
-  require_macos
-  rm -f "$TMP/bin/security"
-  [ "$(command -v security)" = /usr/bin/security ]
-  project="$TMP/project"
-  mkdir -p "$project/bin" "$project/scripts/etc/machine"
-  cp "$SCRIPT" "$project/bin/k3dm-machine-secrets"
-  printf 'svc-roundtrip|*|fixture|operator: fixture\n' > "$project/scripts/etc/machine/secrets.hub.list"
-  source_keychain="$TMP/source.keychain-db"
-  target_keychain="$TMP/target.keychain-db"
-  if ! security create-keychain -p fixture-pass "$source_keychain"; then skip 'throwaway Keychain creation unavailable in this environment'; fi
-  if ! security create-keychain -p fixture-pass "$target_keychain"; then security delete-keychain "$source_keychain" >/dev/null 2>&1 || true; skip 'throwaway Keychain creation unavailable in this environment'; fi
-  security unlock-keychain -p fixture-pass "$source_keychain"
-  security unlock-keychain -p fixture-pass "$target_keychain"
-  security add-generic-password -s svc-roundtrip -a account-one -X 7370616365202271756f746564220a6e65776c696e65 "$source_keychain"
-  security add-generic-password -s svc-roundtrip -a account-two -X 73617920226869220a "$source_keychain"
-  security add-generic-password -s svc-roundtrip -a account-three -X 7361792022686922 "$source_keychain"
-  security add-generic-password -s svc-other -a account-four -X 6e6f74206c6973746564 "$source_keychain"
-  encrypted="$TMP/roundtrip.enc"
-  run "$project/bin/k3dm-machine-secrets" export --role hub --out "$encrypted" --keychain "$source_keychain"
-  [ "$status" -eq 0 ]
-  run "$project/bin/k3dm-machine-secrets" import --in "$encrypted" --keychain "$target_keychain"
-  [ "$status" -eq 0 ]
-  source_one="$(security find-generic-password -s svc-roundtrip -a account-one -g "$source_keychain" 2>&1 | sed -n 's/.*password: //p')"
-  target_one="$(security find-generic-password -s svc-roundtrip -a account-one -g "$target_keychain" 2>&1 | sed -n 's/.*password: //p')"
-  source_two="$(security find-generic-password -s svc-roundtrip -a account-two -g "$source_keychain" 2>&1 | sed -n 's/.*password: //p')"
-  target_two="$(security find-generic-password -s svc-roundtrip -a account-two -g "$target_keychain" 2>&1 | sed -n 's/.*password: //p')"
-  source_three="$(security find-generic-password -s svc-roundtrip -a account-three -g "$source_keychain" 2>&1 | sed -n 's/.*password: //p')"
-  target_three="$(security find-generic-password -s svc-roundtrip -a account-three -g "$target_keychain" 2>&1 | sed -n 's/.*password: //p')"
-  [ -n "$source_one" ] && [ -n "$source_two" ] && [ "$source_three" = '"say "hi""' ]
-  [ "$source_one" = "$target_one" ]
-  [ "$source_two" = "$target_two" ]
-  [ "$source_three" = "$target_three" ]
-  run security find-generic-password -s svc-other -a account-four "$target_keychain"
-  [ "$status" -ne 0 ]
-  security delete-keychain "$source_keychain"
-  security delete-keychain "$target_keychain"
-}
-
-@test "M6: stream unlock round trip uses throwaway keychains on macOS" {
-  require_macos
-  rm -f "$TMP/bin/security"
-  source_keychain="$TMP/stream-source.keychain-db"
-  target_keychain="$TMP/stream-target.keychain-db"
-  if ! security create-keychain -p fixture-pass "$source_keychain"; then skip 'throwaway Keychain creation unavailable in this environment'; fi
-  if ! security create-keychain -p fixture-pass "$target_keychain"; then security delete-keychain "$source_keychain" >/dev/null 2>&1 || true; skip 'throwaway Keychain creation unavailable in this environment'; fi
-  security unlock-keychain -p fixture-pass "$source_keychain"
-  security unlock-keychain -p fixture-pass "$target_keychain"
-  security add-generic-password -s k3dm-cloudflare-api-token -a k3dm -X 746f6b656e "$source_keychain"
-  security lock-keychain "$source_keychain"
-  run bash -c "printf 'fixture-pass\\n' | '$SCRIPT' export --role hub --stream --unlock --keychain '$source_keychain' | '$SCRIPT' import --in - --keychain '$target_keychain'"
-  [ "$status" -eq 0 ]
-  source_value="$(security find-generic-password -s k3dm-cloudflare-api-token -a k3dm -g "$source_keychain" 2>&1 | sed -n 's/.*password: //p')"
-  target_value="$(security find-generic-password -s k3dm-cloudflare-api-token -a k3dm -g "$target_keychain" 2>&1 | sed -n 's/.*password: //p')"
-  [ -n "$source_value" ]
-  [ "$source_value" = "$target_value" ]
-  security delete-keychain "$source_keychain"
-  security delete-keychain "$target_keychain"
-}
-
 @test "machine secrets: export with no listed item fails and writes no file" {
   printf 'svc-other\tacct\t6869\n' > "$FIXTURE"
   project="$TMP/project"
diff --git a/scripts/tests/bin/test_cloud_bridge.py b/scripts/tests/bin/test_cloud_bridge.py
index fe79c1e5..01c3de03 100644
--- a/scripts/tests/bin/test_cloud_bridge.py
+++ b/scripts/tests/bin/test_cloud_bridge.py
@@ -933,6 +933,7 @@ TEST_SUITE_ACTIONS = {
     "make-test-all": ("test-all", 1800),
 }
 NEVER_EXPOSED = {
+    "test-host",
     "up", "down", "cluster", "cluster-up", "cluster-down", "fix-delete-pod", "fix-force-sync",
     "e2e-sandbox", "e2e-sandbox-provision", "e2e-replay", "e2e-runner-unlock", "cleanup-stale-sandbox",
     "argocd-upgrade", "index-docs", "sync-apps",
diff --git a/scripts/tests/bin/test_test_tripwire.py b/scripts/tests/bin/test_test_tripwire.py
index f5e42775..7729b289 100644
--- a/scripts/tests/bin/test_test_tripwire.py
+++ b/scripts/tests/bin/test_test_tripwire.py
@@ -44,6 +44,7 @@ def test_aggregate_targets_only_compose_tripwired_targets():
     makefile = (ROOT / "Makefile").read_text()
     assert re.search(r"^test-python: test-python-unit test-pytest$", makefile, re.M)
     assert re.search(r"^test-all: test test-bin test-python$", makefile, re.M)
+    assert "scripts/tests/tripwire.sh" not in _recipe("test-host")
 
 
 def test_the_tripwire_covers_the_cluster_cloud_and_credential_tools():
@@ -106,3 +107,58 @@ def test_offline_subcommands_pass_through_to_the_real_binary(real_tools):
 
 def test_the_command_exit_code_is_preserved(real_tools):
     assert _tripwire("exit 3", real_tools).returncode == 3
+
+
+@pytest.mark.parametrize("mutation", ["create", "modify", "same-bytes", "remove", "create-dir"])
+def test_launch_agent_plist_changes_fail_and_name_the_sentinel(tmp_path, mutation):
+    watch = tmp_path / "home" / "Library" / "LaunchAgents"
+    watch.mkdir(parents=True)
+    target = watch / "com.k3d-manager.fixture.plist"
+    if mutation in {"modify", "same-bytes", "remove"}:
+        target.write_text("before\n")
+    assert watch == tmp_path / "home" / "Library" / "LaunchAgents"
+    if mutation == "create-dir":
+        watch.rmdir()
+    command = {
+        "create": f"printf after > '{target}'",
+        "modify": f"printf after > '{target}'",
+        "same-bytes": f"cat '{target}' > '{target}.tmp' && mv '{target}.tmp' '{target}'",
+        "remove": f"rm '{target}'",
+        "create-dir": f"mkdir -p '{watch}' && printf after > '{target}'",
+    }[mutation]
+    result = subprocess.run([str(TRIPWIRE), "bash", "-c", command], cwd=ROOT,
+                            env={**os.environ, "K3DM_TRIPWIRE_WATCH_DIR": str(watch)},
+                            capture_output=True, text=True, timeout=60, check=False)
+    assert result.returncode != 0
+    assert f"[tripwire] FAIL: {target}" in result.stderr
+
+
+def test_launch_agent_watch_is_green_when_unchanged_or_missing(tmp_path):
+    missing = tmp_path / "not-created"
+    assert not missing.exists()
+    env = {**os.environ, "K3DM_TRIPWIRE_WATCH_DIR": str(missing)}
+    result = subprocess.run([str(TRIPWIRE), "bash", "-c", "true"], cwd=ROOT, env=env,
+                            capture_output=True, text=True, timeout=60, check=False)
+    assert result.returncode == 0
+    assert not result.stderr
+    assert not missing.exists()
+    unchanged = tmp_path / "home" / "Library" / "LaunchAgents"
+    unchanged.mkdir(parents=True)
+    (unchanged / "com.k3d-manager.fixture.plist").write_text("stable\n")
+    result = subprocess.run([str(TRIPWIRE), "bash", "-c", "true"], cwd=ROOT,
+                            env={**os.environ, "K3DM_TRIPWIRE_WATCH_DIR": str(unchanged)},
+                            capture_output=True, text=True, timeout=60, check=False)
+    assert result.returncode == 0
+    assert not result.stderr
+
+
+def test_launch_agent_watch_preserves_nonzero_command_status(tmp_path):
+    watch = tmp_path / "home" / "Library" / "LaunchAgents"
+    watch.mkdir(parents=True)
+    target = watch / "com.k3d-manager.fixture.plist"
+    assert watch.is_dir()
+    result = subprocess.run([str(TRIPWIRE), "bash", "-c", f"printf x > '{target}'; exit 3"], cwd=ROOT,
+                            env={**os.environ, "K3DM_TRIPWIRE_WATCH_DIR": str(watch)},
+                            capture_output=True, text=True, timeout=60, check=False)
+    assert result.returncode == 3
+    assert f"[tripwire] FAIL: {target} created" in result.stderr
diff --git a/scripts/tests/core/suite_discovery.bats b/scripts/tests/core/suite_discovery.bats
index b7facaac..805a3583 100644
--- a/scripts/tests/core/suite_discovery.bats
+++ b/scripts/tests/core/suite_discovery.bats
@@ -3,7 +3,7 @@
 
 setup() {
   REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
-  TESTS_ROOT="${REPO_ROOT}/scripts/tests"
+  TESTS_ROOT="${TESTS_ROOT:-${REPO_ROOT}/scripts/tests}"
 }
 
 @test "every BATS suite lives in a directory some target globs" {
@@ -13,8 +13,8 @@ setup() {
   while IFS= read -r _file; do
     _rel="${_file#"${TESTS_ROOT}"/}"
     case "${_rel}" in
-      lib/*/*|core/*/*|plugins/*/*|etc/*/*|bin/*/*) _orphans+=("${_rel}") ;;
-      lib/*|core/*|plugins/*|etc/*|bin/*) ;;
+      lib/*/*|core/*/*|plugins/*/*|etc/*/*|bin/*/*|host/*/*) _orphans+=("${_rel}") ;;
+      lib/*|core/*|plugins/*|etc/*|bin/*|host/*) ;;
       *) _orphans+=("${_rel}") ;;
     esac
   done < <(find "${TESTS_ROOT}" -type f -name '*.bats' | sort)
@@ -24,6 +24,16 @@ setup() {
     printf '  scripts/tests/%s\n' "${_orphans[@]}" >&2
     printf 'make test globs scripts/tests/{lib,core,plugins,etc} at -maxdepth 1;\n' >&2
     printf 'make test-bin globs scripts/tests/bin. Move the file into one of those.\n' >&2
+    printf 'make test-host globs scripts/tests/host (macOS, real host tools, not offline).\n' >&2
     return 1
   fi
 }
+
+@test "an unlisted test directory remains an orphan" {
+  local fixture="${BATS_TEST_TMPDIR}/tests"
+  mkdir -p "${fixture}/newdir"
+  printf '#!/usr/bin/env bats\n@test "orphan" { true; }\n' > "${fixture}/newdir/orphan.bats"
+  run env TESTS_ROOT="${fixture}" bats -f 'every BATS suite lives in a directory' "${BATS_TEST_FILENAME}"
+  [ "$status" -ne 0 ]
+  [[ "$output" == *'scripts/tests/newdir/orphan.bats'* ]]
+}
diff --git a/scripts/tests/host/machine_secrets_real_keychain.bats b/scripts/tests/host/machine_secrets_real_keychain.bats
new file mode 100644
index 00000000..b06a7078
--- /dev/null
+++ b/scripts/tests/host/machine_secrets_real_keychain.bats
@@ -0,0 +1,101 @@
+#!/usr/bin/env bats
+
+setup() {
+  ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
+  # shellcheck source=../test_helpers.bash
+  source "${ROOT}/scripts/tests/test_helpers.bash"
+  TMP="$BATS_TEST_TMPDIR"
+  mkdir -p "$TMP/bin" "$TMP/home"
+  export PATH="$TMP/bin:$PATH" HOME="$TMP/home" K3DM_SECRETS_PASSPHRASE_FILE="$TMP/pass"
+  printf 'test passphrase\n' > "$K3DM_SECRETS_PASSPHRASE_FILE"
+  SCRIPT="${MACHINE_SECRETS_SOURCE:-$ROOT/bin/k3dm-machine-secrets}"
+  source_keychain='' target_keychain=''
+  if [[ "$(uname -s)" == Darwin ]]; then
+    security list-keychains -d user > "$TMP/search-list.before"
+  fi
+}
+
+teardown() {
+  [[ "$(uname -s)" == Darwin ]] || return 0
+  local key after saved_line
+  local -a saved=()
+  for key in "${source_keychain:-}" "${target_keychain:-}"; do
+    [[ -n "$key" ]] && security delete-keychain "$key" >/dev/null 2>&1 || true
+  done
+  security list-keychains -d user > "$TMP/search-list.after"
+  if ! cmp -s "$TMP/search-list.before" "$TMP/search-list.after"; then
+    while IFS= read -r saved_line; do
+      saved+=("$saved_line")
+    done < <(sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//' "$TMP/search-list.before")
+    security list-keychains -d user -s "${saved[@]}"
+    security list-keychains -d user > "$TMP/search-list.after"
+    if ! cmp -s "$TMP/search-list.before" "$TMP/search-list.after"; then
+      printf 'keychain search list differs after cleanup\nBEFORE:\n' >&2
+      cat "$TMP/search-list.before" >&2
+      printf 'AFTER:\n' >&2
+      cat "$TMP/search-list.after" >&2
+      return 1
+    fi
+  fi
+}
+
+@test "machine secrets: real throwaway keychain round trip is macOS only" {
+  require_macos
+  rm -f "$TMP/bin/security"
+  [ "$(command -v security)" = /usr/bin/security ]
+  project="$TMP/project"
+  mkdir -p "$project/bin" "$project/scripts/etc/machine"
+  cp "$SCRIPT" "$project/bin/k3dm-machine-secrets"
+  printf 'svc-roundtrip|*|fixture|operator: fixture\n' > "$project/scripts/etc/machine/secrets.hub.list"
+  source_keychain="$TMP/source.keychain-db"
+  target_keychain="$TMP/target.keychain-db"
+  security create-keychain -p fixture-pass "$source_keychain"
+  security create-keychain -p fixture-pass "$target_keychain"
+  security unlock-keychain -p fixture-pass "$source_keychain"
+  security unlock-keychain -p fixture-pass "$target_keychain"
+  security add-generic-password -s svc-roundtrip -a account-one -X 7370616365202271756f746564220a6e65776c696e65 "$source_keychain"
+  security add-generic-password -s svc-roundtrip -a account-two -X 73617920226869220a "$source_keychain"
+  security add-generic-password -s svc-roundtrip -a account-three -X 7361792022686922 "$source_keychain"
+  security add-generic-password -s svc-other -a account-four -X 6e6f74206c6973746564 "$source_keychain"
+  encrypted="$TMP/roundtrip.enc"
+  run "$project/bin/k3dm-machine-secrets" export --role hub --out "$encrypted" --keychain "$source_keychain"
+  [ "$status" -eq 0 ]
+  run "$project/bin/k3dm-machine-secrets" import --in "$encrypted" --keychain "$target_keychain"
+  [ "$status" -eq 0 ]
+  source_one="$(security find-generic-password -s svc-roundtrip -a account-one -g "$source_keychain" 2>&1 | sed -n 's/.*password: //p')"
+  target_one="$(security find-generic-password -s svc-roundtrip -a account-one -g "$target_keychain" 2>&1 | sed -n 's/.*password: //p')"
+  source_two="$(security find-generic-password -s svc-roundtrip -a account-two -g "$source_keychain" 2>&1 | sed -n 's/.*password: //p')"
+  target_two="$(security find-generic-password -s svc-roundtrip -a account-two -g "$target_keychain" 2>&1 | sed -n 's/.*password: //p')"
+  source_three="$(security find-generic-password -s svc-roundtrip -a account-three -g "$source_keychain" 2>&1 | sed -n 's/.*password: //p')"
+  target_three="$(security find-generic-password -s svc-roundtrip -a account-three -g "$target_keychain" 2>&1 | sed -n 's/.*password: //p')"
+  [ -n "$source_one" ] && [ -n "$source_two" ] && [ "$source_three" = '"say "hi""' ]
+  [ "$source_one" = "$target_one" ]
+  [ "$source_two" = "$target_two" ]
+  [ "$source_three" = "$target_three" ]
+  run security find-generic-password -s svc-other -a account-four "$target_keychain"
+  [ "$status" -ne 0 ]
+  security delete-keychain "$source_keychain"
+  security delete-keychain "$target_keychain"
+}
+
+@test "M6: stream unlock round trip uses throwaway keychains on macOS" {
+  require_macos
+  rm -f "$TMP/bin/security"
+  source_keychain="$TMP/stream-source.keychain-db"
+  target_keychain="$TMP/stream-target.keychain-db"
+  security create-keychain -p fixture-pass "$source_keychain"
+  security create-keychain -p fixture-pass "$target_keychain"
+  security unlock-keychain -p fixture-pass "$source_keychain"
+  security unlock-keychain -p fixture-pass "$target_keychain"
+  security add-generic-password -s k3dm-cloudflare-api-token -a k3dm -X 746f6b656e "$source_keychain"
+  security lock-keychain "$source_keychain"
+  run bash -c "printf 'fixture-pass\\n' | '$SCRIPT' export --role hub --stream --unlock --keychain '$source_keychain' | '$SCRIPT' import --in - --keychain '$target_keychain'"
+  [ "$status" -eq 0 ]
+  source_value="$(security find-generic-password -s k3dm-cloudflare-api-token -a k3dm -g "$source_keychain" 2>&1 | sed -n 's/.*password: //p')"
+  target_value="$(security find-generic-password -s k3dm-cloudflare-api-token -a k3dm -g "$target_keychain" 2>&1 | sed -n 's/.*password: //p')"
+  [ -n "$source_value" ]
+  [ "$source_value" = "$target_value" ]
+  security delete-keychain "$source_keychain"
+  security delete-keychain "$target_keychain"
+}
+
diff --git a/scripts/tests/lib/fast_gate.bats b/scripts/tests/lib/fast_gate.bats
index d8b6dcca..1944e63b 100644
--- a/scripts/tests/lib/fast_gate.bats
+++ b/scripts/tests/lib/fast_gate.bats
@@ -82,6 +82,35 @@ setup() {
   [[ "$output" != *'ok 1 '* && "$output" == *'SLOWEST scripts/tests/lib/'* ]]
 }
 
+@test "fast gate: excludes host suites and removes caller BASE from workers" {
+  mkdir -p "$fixture/scripts/tests/host"
+  printf '#!/usr/bin/env bats\n# thing.txt\n@test "host probe" { touch %s; }\n' "$fixture/host-ran" > "$fixture/scripts/tests/host/probe.bats"
+  git -C "$fixture" add scripts/tests/host/probe.bats
+  git -C "$fixture" commit -qm host-probe
+  base=$(git -C "$fixture" rev-parse HEAD^)
+  printf 'new\n' >> "$fixture/thing.txt"
+  git -C "$fixture" add thing.txt
+  git -C "$fixture" commit -qm change-and-host-file
+  run env BASE=deadbeef bash -c 'cd "$1" && scripts/ci/fast_gate.sh "$2"' _ "$fixture" "$base"
+  [ "$status" -eq 0 ]
+  [[ "$output" != *'scripts/tests/host/'* ]]
+  [ ! -e "$fixture/host-ran" ]
+  run bats "$fixture/scripts/tests/host/probe.bats"
+  [ "$status" -eq 0 ]
+  [ -e "$fixture/host-ran" ]
+  rm -f "$fixture/host-ran"
+
+  printf '#!/usr/bin/env bats\n@test "base is absent" { [ -z "${BASE+x}" ]; }\n' > "$fixture/scripts/tests/lib/base-env.bats"
+  git -C "$fixture" add scripts/tests/lib/base-env.bats
+  git -C "$fixture" commit -qm base-env-test
+  base=$(git -C "$fixture" rev-parse HEAD^)
+  printf 'another\n' >> "$fixture/thing.txt"
+  git -C "$fixture" commit -qam trigger-base-env
+  run env BASE=deadbeef bash -c 'cd "$1" && scripts/ci/fast_gate.sh "$2"' _ "$fixture" "$base"
+  [ "$status" -eq 0 ]
+  [[ "$output" == *'PASS scripts/tests/lib/base-env.bats'* ]]
+}
+
 @test "fast gate: managed venv python leads PATH and supplies suite modules" {
   local scratch="$BATS_TEST_TMPDIR/scratch" caller_bin="$BATS_TEST_TMPDIR/caller-bin"
   mkdir -p "$scratch/home" "$scratch/data/k3d-manager/venv/bin" "$caller_bin"
diff --git a/scripts/tests/lib/observability.bats b/scripts/tests/lib/observability.bats
index a1780027..406420a2 100644
--- a/scripts/tests/lib/observability.bats
+++ b/scripts/tests/lib/observability.bats
@@ -19,6 +19,7 @@ setup() {
   envsubst_log="${BATS_TEST_TMPDIR}/envsubst.log"
   kubectl_log="${BATS_TEST_TMPDIR}/kubectl.log"
   export ENVSTUB_LOG="${envsubst_log}" KUBE_STUB_LOG="${kubectl_log}"
+  export HTPASSWD_STUB_LOG="${BATS_TEST_TMPDIR}/htpasswd.log"
   run bash -c '
     set -e
     REPO_ROOT="$(pwd)"
@@ -69,12 +70,17 @@ EOF
     launchctl() {
       printf "%s\n" "$*" >> "${KUBE_STUB_LOG}"
     }
+    htpasswd() {
+      cat >/dev/null
+      printf "%s\n" "$*" >> "${HTPASSWD_STUB_LOG}"
+      printf "admin:\$2y\$12\$abcdefghijklmnopqrstuu0123456789ABCDEFGHIJKLMNOPQRSTU\n"
+    }
     _is_mac() { return 0; }
     _observability_seed_grafana_if_absent() { :; }
     _vault_login() { :; }
     _observability_ensure_argocd_servicemonitors() { :; }
     _observability_ensure_apiserver_scrape_timeout() { :; }
-    export -f envsubst _kubectl curl kubectl launchctl _is_mac _observability_seed_grafana_if_absent _vault_login \
+    export -f envsubst _kubectl curl kubectl launchctl htpasswd _is_mac _observability_seed_grafana_if_absent _vault_login \
       _observability_ensure_argocd_servicemonitors _observability_ensure_apiserver_scrape_timeout
     export K3D_MANAGER_BRANCH=feature-branch
     deploy_observability
diff --git a/scripts/tests/plugins/agent_dispatch_dashboard.bats b/scripts/tests/plugins/agent_dispatch_dashboard.bats
index 99902240..9c1451ee 100644
--- a/scripts/tests/plugins/agent_dispatch_dashboard.bats
+++ b/scripts/tests/plugins/agent_dispatch_dashboard.bats
@@ -1,11 +1,12 @@
 #!/usr/bin/env bats
 
-BASE="${BASE:-${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops}"
+AGENT_DASHBOARD_DIR="${AGENT_DASHBOARD_DIR:-${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops}"
 FIXTURE="${BATS_TEST_DIRNAME}/../fixtures/agent-dispatch-dashboard-pre-split.yaml"
+BASELINE_FIXTURE="${BATS_TEST_DIRNAME}/../fixtures/agent-dispatch-dashboard-028b898f.yaml"
 EXPORTER="${BATS_TEST_DIRNAME}/../../../bin/k3dm-dispatch-metrics"
 
 @test "agent dispatch dashboard: valid ConfigMap JSON and datasource" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json, sys
 from pathlib import Path
 base=Path(sys.argv[1])
@@ -22,10 +23,10 @@ PY
 }
 
 @test "agent dispatch dashboard: verification ladder contract" {
-  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" "${BATS_TEST_DIRNAME}/../../../docs/guides/grafana-dashboards/k3dm-agent-dispatch.md" <<'PY'
-import json, re, subprocess, sys
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-dispatch.yaml" "${BATS_TEST_DIRNAME}/../../../docs/guides/grafana-dashboards/k3dm-agent-dispatch.md" "$BASELINE_FIXTURE" <<'PY'
+import json, re, sys
 from pathlib import Path
-dashboard_path, guide_path = map(Path, sys.argv[1:])
+dashboard_path, guide_path, baseline_path = map(Path, sys.argv[1:])
 def load(path):
     text = path.read_text()
     return json.loads("\n".join(line[4:] for line in text.split("  agent-dispatch.json: |\n", 1)[1].splitlines()))
@@ -57,8 +58,7 @@ for phrase in ("offline_tested", "deployed", "live_verified", "gate_coverage_sta
 section = guide_path.read_text().split("## Verification ladder", 1)[1].split("\n## ", 1)[0]
 for phrase in ("implemented", "offline_tested", "deployed", "live_verified", "independently_verified", "landed", "gate_coverage_start", "evidence hash"):
     assert phrase in section, phrase
-dashboard_repo_path = "scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml"
-baseline_text = subprocess.run(["git", "-C", str(dashboard_path.parent), "show", f"028b898f:{dashboard_repo_path}"], check=True, capture_output=True, text=True).stdout
+baseline_text = baseline_path.read_text()
 baseline_json = json.loads("\n".join(line[4:] for line in baseline_text.split("  agent-dispatch.json: |\n", 1)[1].splitlines()))
 assert next(item for item in baseline_json["panels"] if item["id"] == 105)["type"] == "bargauge"
 old = {item["id"]: item for item in baseline_json["panels"]}
@@ -73,7 +73,7 @@ PY
 }
 
 @test "agent dispatch dashboard: every queried metric is exported" {
-  run python3 - "$BASE" "$EXPORTER" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" "$EXPORTER" <<'PY'
 import json,re,sys
 from pathlib import Path
 base=Path(sys.argv[1]); dashboards=[]
@@ -90,7 +90,7 @@ PY
 }
 
 @test "agent dispatch dashboard: Claude context and compaction row panels exist below existing rows" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json,sys
 from pathlib import Path
 text=(Path(sys.argv[1])/"grafana-dashboard-agent-activity.yaml").read_text()
@@ -115,7 +115,7 @@ PY
 }
 
 @test "agent dispatch dashboard: landing success aggregates both sides" {
-  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-dispatch.yaml" <<'PY'
 import json,sys
 text=open(sys.argv[1]).read(); d=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))
 panel=next(p for p in d["panels"] if p["id"]==2); numerator,denominator=[side.strip() for side in panel["targets"][0]["expr"].split(" / ")]
@@ -127,7 +127,7 @@ PY
 }
 
 @test "agent dispatch dashboard: panel rectangles do not overlap" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json,sys
 from pathlib import Path
 base=Path(sys.argv[1])
@@ -146,7 +146,7 @@ PY
 }
 
 @test "agent dispatch dashboard: Codex API cost shows priced total and excluded sessions" {
-  run python3 - "$BASE/grafana-dashboard-agent-activity.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-activity.yaml" <<'PY'
 import json,sys
 text=open(sys.argv[1]).read(); d=json.loads("\n".join(x[4:] for x in text.split("  agent-activity.json: |\n",1)[1].splitlines()))
 by_id={p["id"]:p for p in d["panels"]}
@@ -163,7 +163,7 @@ PY
 }
 
 @test "agent dispatch dashboard: per-spec panels use readable units and grouped targets" {
-  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-dispatch.yaml" <<'PY'
 import json,sys
 text=open(sys.argv[1]).read(); panels=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))["panels"]
 panel5=next(p for p in panels if p["id"]==5); assert panel5["fieldConfig"]["defaults"]["unit"]=="short"
@@ -176,7 +176,7 @@ PY
 }
 
 @test "agent dispatch dashboard: final exit gap and operator coverage are exposed" {
-  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-dispatch.yaml" <<'PY'
 import json,sys
 text=open(sys.argv[1]).read(); d=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))
 panels={p["title"]:p for p in d["panels"]}
@@ -200,7 +200,7 @@ PY
 }
 
 @test "agent dispatch dashboard: window is a query over the exported scopes and defaults to 7d" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json,sys
 from pathlib import Path
 for filename,key in (("grafana-dashboard-agent-dispatch.yaml","agent-dispatch.json"),("grafana-dashboard-agent-cost.yaml","agent-cost.json")):
@@ -216,7 +216,7 @@ PY
 }
 
 @test "agent dispatch dashboard: rework rate stat reads the selected window" {
-  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-dispatch.yaml" <<'PY'
 import json,sys
 text=open(sys.argv[1]).read(); d=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))
 p=next(p for p in d["panels"] if p["title"]=="Rework rate")
@@ -227,7 +227,7 @@ PY
 }
 
 @test "agent dispatch dashboard: verified delivery stats use exported metrics without overlap" {
-  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-dispatch.yaml" <<'PY'
 import json,sys
 text=open(sys.argv[1]).read(); panels=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))["panels"]
 by_id={p["id"]:p for p in panels}; tokens=by_id[40]; awaiting=by_id[41]
@@ -241,7 +241,7 @@ PY
 }
 
 @test "agent dispatch dashboard: stat and bar gauge panels use explicit colours" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json,sys
 from pathlib import Path
 base=Path(sys.argv[1]); dashboards=[]
@@ -267,7 +267,7 @@ PY
 }
 
 @test "agent dashboards: panel ids exactly match the pre-split dashboard and assigned groups" {
-  run python3 - "$BASE" "$FIXTURE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" "$FIXTURE" <<'PY'
 import json,sys
 from pathlib import Path
 base,fixture=Path(sys.argv[1]),Path(sys.argv[2])
@@ -288,7 +288,7 @@ PY
 }
 
 @test "agent dashboards: panel targets, fieldConfig and options match the pre-split fixture" {
-  run python3 - "$BASE" "$FIXTURE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" "$FIXTURE" <<'PY'
 import json,sys
 from pathlib import Path
 base,fixture=Path(sys.argv[1]),Path(sys.argv[2])
@@ -322,7 +322,7 @@ PY
 }
 
 @test "agent activity: repo gauge height, row layout, and protected panel data" {
-  run python3 - "$BASE/grafana-dashboard-agent-activity.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-activity.yaml" <<'PY'
 import json,sys
 from pathlib import Path
 text=Path(sys.argv[1]).read_text()
@@ -354,7 +354,7 @@ PY
 }
 
 @test "agent dashboards: each dashboard has unique panel ids and no overlapping rectangles" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json,sys
 from pathlib import Path
 base=Path(sys.argv[1])
@@ -373,7 +373,7 @@ PY
 }
 
 @test "agent dashboards: all dashboards have the tag-based Agents link" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json,sys
 from pathlib import Path
 base=Path(sys.argv[1])
@@ -389,7 +389,7 @@ PY
 }
 
 @test "agent dashboards: Activity has three time windows and Dispatch and Cost keep the query variable" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json,sys
 from pathlib import Path
 base=Path(sys.argv[1])
@@ -410,7 +410,7 @@ PY
 }
 
 @test "agent activity: Claude row fills the width and bar gauge names read beside each bar" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json,sys
 from pathlib import Path
 text=(Path(sys.argv[1])/"grafana-dashboard-agent-activity.yaml").read_text()
@@ -440,7 +440,7 @@ PY
 }
 
 @test "agent dispatch: run outcomes read beside each bar, first-pass verification bars with fixed fonts sit beside per run evidence, and each slug links to its spec" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json,re,sys
 from pathlib import Path
 text=(Path(sys.argv[1])/"grafana-dashboard-agent-dispatch.yaml").read_text()
@@ -515,7 +515,7 @@ PY
 }
 
 @test "agent dispatch: failed startup evidence is local-only and the Loki link is scoped to shipped logs" {
-  run python3 - "$BASE" <<'PYTEST'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PYTEST'
 import json,sys
 from pathlib import Path
 base=Path(sys.argv[1])
@@ -543,7 +543,7 @@ PYTEST
 }
 
 @test "agent dispatch: per spec shows which agent landed each spec" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json,sys
 from pathlib import Path
 text=(Path(sys.argv[1])/"grafana-dashboard-agent-dispatch.yaml").read_text()
@@ -564,7 +564,7 @@ PY
 }
 
 @test "agent dispatch dashboard: Log opens the filtered run log dashboard" {
-  run python3 - "$BASE" <<'PYTEST'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PYTEST'
 import json,re,sys
 from pathlib import Path
 from urllib.parse import quote, urlsplit, parse_qs
@@ -604,7 +604,7 @@ PYTEST
 }
 
 @test "agent cost: Claude tokens by kind splits the selected window by cache kind" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json,sys
 from pathlib import Path
 text=(Path(sys.argv[1])/"grafana-dashboard-agent-cost.yaml").read_text()
@@ -622,7 +622,7 @@ PY
 }
 
 @test "agent cost: daily Claude tokens and cost panels split by kind" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json,sys
 from pathlib import Path
 text=(Path(sys.argv[1])/"grafana-dashboard-agent-cost.yaml").read_text()
@@ -659,7 +659,7 @@ PY
 }
 
 @test "agent dashboards: labels and titles stay readable and release-only stats say why they are empty" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json,sys
 from pathlib import Path
 base=Path(sys.argv[1])
@@ -687,7 +687,7 @@ PY
 }
 
 @test "agent dispatch dashboard: Per spec exposes unknown worker and coordinator identities" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json,sys
 from pathlib import Path
 text=(Path(sys.argv[1])/"grafana-dashboard-agent-dispatch.yaml").read_text()
@@ -705,7 +705,7 @@ PY
 }
 
 @test "agent dispatch dashboard: Per spec shows handoff and measured cost fields within width budget" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json,sys
 from pathlib import Path
 text=(Path(sys.argv[1]) / "grafana-dashboard-agent-dispatch.yaml").read_text()
@@ -734,7 +734,7 @@ PY
 }
 
 @test "agent dispatch dashboard: Per spec spans the full width and its columns fit without scrolling" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json,sys
 from pathlib import Path
 text=(Path(sys.argv[1])/"grafana-dashboard-agent-dispatch.yaml").read_text()
@@ -749,7 +749,7 @@ PY
 }
 
 @test "agent dispatch: blank evidence paths remain visible clickable links and gaps are explicit" {
-  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-dispatch.yaml" <<'PY'
 import json,sys
 text=open(sys.argv[1]).read(); d=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))
 panel=next(p for p in d["panels"] if p["id"]==47)
@@ -769,7 +769,7 @@ PY
 }
 
 @test "agent dispatch: unrecorded attribution is labeled without overwriting known identities" {
-  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-dispatch.yaml" <<'PY'
 import json,sys
 text=open(sys.argv[1]).read(); d=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))
 panel=next(p for p in d["panels"] if p["id"]==12)
@@ -785,7 +785,7 @@ PY
 }
 
 @test "agent cost: whole-system API panels meet the cost and denominator contract" {
-  run python3 - "$BASE/grafana-dashboard-agent-cost.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-cost.yaml" <<'PY'
 import json,sys
 text=open(sys.argv[1]).read(); d=json.loads("\n".join(x[4:] for x in text.split("  agent-cost.json: |\n",1)[1].splitlines()))
 by_title={p["title"]:p for p in d["panels"]}
@@ -824,7 +824,7 @@ PY
 }
 
 @test "agent cost: new attribution panels exist with exprs, unpriced note, no Ledger coverage, and no overlaps" {
-  run python3 - "$BASE/grafana-dashboard-agent-cost.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-cost.yaml" <<'PY'
 import json,sys
 from pathlib import Path
 path=Path(sys.argv[1]); text=path.read_text()
@@ -866,7 +866,7 @@ PY
 }
 
 @test "agent cost: Codex API cost queries never add the mode and category series together" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json,re,sys
 from pathlib import Path
 base=Path(sys.argv[1])
@@ -888,7 +888,7 @@ PY
 }
 
 @test "agent cost: Codex spend by category is readable and shows tokens as counts" {
-  run python3 - "$BASE/grafana-dashboard-agent-cost.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-cost.yaml" <<'PY'
 import json,sys
 text=open(sys.argv[1]).read(); d=json.loads("\n".join(x[4:] for x in text.split("  agent-cost.json: |\n",1)[1].splitlines()))
 spend={p["title"]:p for p in d["panels"]}["Codex spend by category"]
@@ -910,7 +910,7 @@ PY
 }
 
 @test "agent cost: API cost expression stub matches the 7d baseline and missing release term" {
-  run python3 - "$BASE/grafana-dashboard-agent-cost.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-cost.yaml" <<'PY'
 import json,sys
 text=open(sys.argv[1]).read(); d=json.loads("\n".join(x[4:] for x in text.split("  agent-cost.json: |\n",1)[1].splitlines()))
 p={x["title"]:x for x in d["panels"]}
@@ -928,7 +928,7 @@ PY
 }
 
 @test "agent activity: configured setting and observed compaction point are distinct" {
-  run python3 - "$BASE/grafana-dashboard-agent-activity.yaml" <<'PYTEST'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-activity.yaml" <<'PYTEST'
 import json,sys
 text=open(sys.argv[1]).read()
 d=json.loads("\n".join(x[4:] for x in text.split("  agent-activity.json: |\n",1)[1].splitlines()))
@@ -953,7 +953,7 @@ PYTEST
 }
 
 @test "agent activity: wasted reread share and empty mapping" {
-  run python3 - "$BASE/grafana-dashboard-agent-activity.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-activity.yaml" <<'PY'
 import json, sys
 from pathlib import Path
 text=Path(sys.argv[1]).read_text()
@@ -976,7 +976,7 @@ PY
 }
 
 @test "agent activity: repo gauges cap named series and preserve the remainder" {
-  run python3 - "$BASE/grafana-dashboard-agent-activity.yaml" <<'PYTEST'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-activity.yaml" <<'PYTEST'
 import json,sys
 from pathlib import Path
 text=Path(sys.argv[1]).read_text()
@@ -995,7 +995,7 @@ PYTEST
 }
 
 @test "agent activity: agy data source names local host and source without overlap" {
-  run python3 - "$BASE/grafana-dashboard-agent-activity.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-activity.yaml" <<'PY'
 import json,sys
 text=open(sys.argv[1]).read()
 panels=json.loads("\n".join(line[4:] for line in text.split("  agent-activity.json: |\n",1)[1].splitlines()))["panels"]
@@ -1021,7 +1021,7 @@ PY
 }
 
 @test "agent dispatch: outcome row accommodates nine labels and preserves subsequent layout" {
-  run python3 - "$BASE" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}" <<'PY'
 import json,sys
 from pathlib import Path
 text=(Path(sys.argv[1])/"grafana-dashboard-agent-dispatch.yaml").read_text()
@@ -1057,7 +1057,7 @@ PY
 }
 
 @test "agent dispatch dashboard: S1 gate panels exist and match query and description contract" {
-  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" "$EXPORTER" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-dispatch.yaml" "$EXPORTER" <<'PY'
 import json, re, sys
 from pathlib import Path
 d = json.loads("\n".join(x[4:] for x in open(sys.argv[1]).read().split("  agent-dispatch.json: |\n", 1)[1].splitlines()))
@@ -1107,7 +1107,7 @@ PY
 }
 
 @test "agent dispatch dashboard: Split work outer join on synthetic metrics" {
-  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" "$EXPORTER" "${BATS_TEST_DIRNAME}/../fixtures/dispatch-gates/synthetic.jsonl" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-dispatch.yaml" "$EXPORTER" "${BATS_TEST_DIRNAME}/../fixtures/dispatch-gates/synthetic.jsonl" <<'PY'
 import json, os, re, shutil, subprocess, sys, tempfile
 from pathlib import Path
 
@@ -1212,7 +1212,7 @@ PY
 }
 
 @test "agent activity: Claude quota panels exist, query quota metrics, and do not overlap" {
-  run python3 - "$BASE/grafana-dashboard-agent-activity.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-activity.yaml" <<'PY'
 import json, sys
 text = open(sys.argv[1]).read()
 d = json.loads("\n".join(x[4:] for x in text.split("  agent-activity.json: |\n", 1)[1].splitlines()))
@@ -1256,7 +1256,7 @@ PY
 }
 
 @test "agent cost: unpriced Claude messages stat sits beside Claude cost and is red above 0" {
-  run python3 - "$BASE/grafana-dashboard-agent-cost.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-cost.yaml" <<'PY'
 import json,sys
 text=open(sys.argv[1]).read(); panels=json.loads("\n".join(x[4:] for x in text.split("  agent-cost.json: |\n",1)[1].splitlines()))["panels"]
 by_id={p["id"]:p for p in panels}
@@ -1277,7 +1277,7 @@ PY
 }
 
 @test "agent cost: Fable row has daily tokens on own axis and weekly limit gauge" {
-  run python3 - "$BASE/grafana-dashboard-agent-cost.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-cost.yaml" <<'PY'
 import json,sys
 text=open(sys.argv[1]).read(); panels=json.loads("\n".join(x[4:] for x in text.split("  agent-cost.json: |\n",1)[1].splitlines()))["panels"]
 fable_row=next((p for p in panels if p.get("type")=="row" and p.get("title")=="Fable"),None)
@@ -1295,7 +1295,7 @@ PY
 }
 
 @test "agent dispatch dashboard: Landed specs table places Worker model column right after Agent" {
-  run python3 - "$BASE/grafana-dashboard-agent-dispatch.yaml" <<'PY'
+  run python3 - "${AGENT_DASHBOARD_DIR}/grafana-dashboard-agent-dispatch.yaml" <<'PY'
 import json,sys
 text=open(sys.argv[1]).read(); panels=json.loads("\n".join(x[4:] for x in text.split("  agent-dispatch.json: |\n",1)[1].splitlines()))["panels"]
 per_spec=next(p for p in panels if p.get("id")==12)
diff --git a/scripts/tests/tripwire.sh b/scripts/tests/tripwire.sh
index 4e49b148..86709047 100755
--- a/scripts/tests/tripwire.sh
+++ b/scripts/tests/tripwire.sh
@@ -54,10 +54,33 @@ _tripwire_dir="$(mktemp -d "${TMPDIR:-/tmp}/k3dm-tripwire.XXXXXX")"
 trap 'rm -rf "$_tripwire_dir"' EXIT
 _tripwire_bin="$_tripwire_dir/bin"
 _tripwire_log="$_tripwire_dir/blocked.log"
+_tripwire_watch_dir="${K3DM_TRIPWIRE_WATCH_DIR:-${HOME:+$HOME/Library/LaunchAgents}}"
 mkdir -p "$_tripwire_bin"
 : > "$_tripwire_log"
 
+_tripwire_snapshot() {
+  local output="$1" file
+  : > "$output"
+  [[ -n "$_tripwire_watch_dir" && -d "$_tripwire_watch_dir" ]] || return 0
+  while IFS= read -r file; do
+    printf '%s\t' "$file" >> "$output"
+    cksum < "$file" >> "$output"
+  done < <(find "$_tripwire_watch_dir" -maxdepth 1 -type f -name 'com.k3d-manager.*.plist' -print | sort)
+}
+
+_tripwire_newer() {
+  local output="$1"
+  : > "$output"
+  [[ -n "$_tripwire_watch_dir" && -d "$_tripwire_watch_dir" ]] || return 0
+  find "$_tripwire_watch_dir" -maxdepth 1 -type f -name 'com.k3d-manager.*.plist' -newer "$_tripwire_dir/watch.marker" -print | sort > "$output"
+}
+
+_tripwire_snapshot "$_tripwire_dir/watch.before"
+touch "$_tripwire_dir/watch.marker"
+_tripwire_newer "$_tripwire_dir/watch.newer.before"
+
 for _tool in "${TRIPWIRE_TOOLS[@]}"; do
+  type -P -- "$_tool" >/dev/null || continue
   cat > "$_tripwire_bin/$_tool" <<SHIM
 #!/usr/bin/env bash
 case "$_tool \${1:-} \${2:-}" in
@@ -89,4 +112,27 @@ if [[ -s "$_tripwire_log" ]]; then
     [[ $_rc -eq 0 ]] && _rc=1
   fi
 fi
+
+_tripwire_snapshot "$_tripwire_dir/watch.after"
+_tripwire_newer "$_tripwire_dir/watch.newer.after"
+_watch_changed=0
+while IFS=$'\t' read -r _path _checksum; do
+  [[ -n "$_path" ]] || continue
+  if ! grep -Fq "$_path" "$_tripwire_dir/watch.after"; then
+    printf '[tripwire] FAIL: %s removed during the run — isolate HOME and stub launchctl in the test.\n' "$_path" >&2
+    _watch_changed=1
+  fi
+done < "$_tripwire_dir/watch.before"
+while IFS=$'\t' read -r _path _checksum; do
+  [[ -n "$_path" ]] || continue
+  _before=$(grep -F "$_path" "$_tripwire_dir/watch.before" || true)
+  if [[ -z "$_before" ]]; then
+    printf '[tripwire] FAIL: %s created during the run — isolate HOME and stub launchctl in the test.\n' "$_path" >&2
+    _watch_changed=1
+  elif [[ "$_before" != "$_path"$'\t'"$_checksum" ]] || grep -Fxq "$_path" "$_tripwire_dir/watch.newer.after" && ! grep -Fxq "$_path" "$_tripwire_dir/watch.newer.before"; then
+    printf '[tripwire] FAIL: %s modified during the run — isolate HOME and stub launchctl in the test.\n' "$_path" >&2
+    _watch_changed=1
+  fi
+done < "$_tripwire_dir/watch.after"
+if (( _watch_changed )); then [[ $_rc -eq 0 ]] && _rc=1; fi
 exit "$_rc"
```
