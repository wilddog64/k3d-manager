# Review brief: repo-sync launchd PATH (Flash) — cross-vendor diff review

**Role:** review child of `2026-11-11-repo-sync-launchd-path-has-no-kubectl`.
**Intent approved:** operator, 2026-11-11
**Spec under review:** `docs/bugs/2026-11-11-repo-sync-launchd-path-has-no-kubectl.md` (read it in full first).

## Files

Read-only: review these, change none of them.
- `scripts/etc/launchd/com.k3d-manager.repo-sync.plist.tmpl`
- `scripts/tests/bin/repo_sync_launchd_env.bats`

## Task

Review the worker's diff below against the spec: its Fix direction, Contract readers and Acceptance block. Report findings only. Do not edit, commit or keep any file. You may `git apply` the diff in your own worktree to run the touched suites and try mutations, but leave the worktree clean at exit (`git checkout -- . && git clean -fd`).

For each finding give: severity (blocker / should-fix / nit); file:line in the diff; a concrete input or state that breaks it; the spec line (Fix item or M/N id) it violates.

Check in particular:
1. Each `must_not` (N1) test fails when the plist's EnvironmentVariables block is removed (try it), and the positive control shows the installer path really runs without it.
2. The macOS-only skips: does any assertion that matters on the hub get skipped on a Mac that should run it? Does E1 still run and pass on Linux?
3. The render: `make install-repo-sync` uses `sed` on the template; is the new block valid plist after rendering (plutil -lint if on macOS)?
4. The test never touches the real `~/Library/LaunchAgents` or loads an agent (scratch HOME, `K3DM_AGENT_LOAD=0`, launchctl stub).

End with a one-line verdict: `land`, `land after fixes`, or `rework`. Under 400 words.

## Worker diff (uncommitted, against `k3d-manager-v1.43.15` at the worker's base `a3786d5f`)

```diff
diff --git a/scripts/etc/launchd/com.k3d-manager.repo-sync.plist.tmpl b/scripts/etc/launchd/com.k3d-manager.repo-sync.plist.tmpl
index 03542196..4ae69ff2 100644
--- a/scripts/etc/launchd/com.k3d-manager.repo-sync.plist.tmpl
+++ b/scripts/etc/launchd/com.k3d-manager.repo-sync.plist.tmpl
@@ -3,6 +3,11 @@
 <plist version="1.0"><dict>
   <key>Label</key><string>com.k3d-manager.repo-sync</string>
   <key>ProgramArguments</key><array><string>{{REPO_ROOT}}/bin/k3dm-repo-sync</string></array>
+  <key>EnvironmentVariables</key>
+  <dict>
+    <key>PATH</key>
+    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
+  </dict>
   <key>RunAtLoad</key><true/><key>StartInterval</key><integer>300</integer>
   <key>StandardOutPath</key><string>{{HOME}}/.local/share/k3d-manager/logs/repo-sync.log</string>
   <key>StandardErrorPath</key><string>{{HOME}}/.local/share/k3d-manager/logs/repo-sync.log</string>
diff --git a/scripts/tests/bin/repo_sync_launchd_env.bats b/scripts/tests/bin/repo_sync_launchd_env.bats
new file mode 100644
index 00000000..68c1804e
--- /dev/null
+++ b/scripts/tests/bin/repo_sync_launchd_env.bats
@@ -0,0 +1,135 @@
+#!/usr/bin/env bats
+
+setup() {
+  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
+  WORK="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/repo-sync-env.XXXXXX")"
+  SCRATCH_HOME="$WORK/home"
+  AGENTS_DIR="$SCRATCH_HOME/Library/LaunchAgents"
+  STUBS_DIR="$WORK/stubs"
+  CALLS_LOG="$WORK/calls.log"
+  INSTALLER_LOG="$WORK/installer.log"
+
+  mkdir -p "$AGENTS_DIR" "$SCRATCH_HOME/.local/share/k3d-manager/logs" "$STUBS_DIR"
+  touch "$CALLS_LOG" "$INSTALLER_LOG"
+
+  # launchctl stub: records calls only, no output imitated
+  cat > "$STUBS_DIR/launchctl" <<'EOF'
+#!/usr/bin/env bash
+printf '%s %s
' "launchctl" "$*" >> "${CALLS_LOG:-/dev/null}"
+exit 0
+EOF
+  chmod +x "$STUBS_DIR/launchctl"
+
+  # Fixture assertions
+  [ -d "$SCRATCH_HOME" ]
+  [ -d "$AGENTS_DIR" ]
+  [ "$SCRATCH_HOME" != "$HOME" ]
+  [ -x "$STUBS_DIR/launchctl" ]
+}
+
+teardown() {
+  rm -rf "$WORK"
+}
+
+_extract_plist_path() {
+  local plist_path="$1"
+  python3 -c '
+import plistlib, sys
+try:
+    with open(sys.argv[1], "rb") as f:
+        pl = plistlib.load(f)
+    env = pl.get("EnvironmentVariables", {})
+    val = env.get("PATH", "")
+    sys.stdout.write(val)
+except Exception:
+    pass
+' "$plist_path"
+}
+
+_probe_installer_invocation() {
+  local test_path="$1"
+  local log_file="$2"
+  (
+    local spy_bin="$WORK/spy_bin"
+    mkdir -p "$spy_bin"
+    for tool in brew apt-get dnf yum; do
+      cat > "$spy_bin/$tool" <<EOF
+#!/usr/bin/env bash
+printf '%s %s
' "$tool" "\$*" >> "$log_file"
+exit 0
+EOF
+      chmod +x "$spy_bin/$tool"
+    done
+    export PATH="$spy_bin:$test_path"
+    # shellcheck disable=SC1090,SC1091
+    source "$PROJECT_ROOT/scripts/lib/foundation/scripts/lib/system.sh"
+    _kubectl version --client 2>/dev/null || true
+  ) || true
+}
+
+@test "E1: the rendered repo-sync plist sets PATH with /opt/homebrew/bin ahead of /usr/bin (M1)" {
+  local plist="$AGENTS_DIR/com.k3d-manager.repo-sync.plist"
+
+  run env -i HOME="$SCRATCH_HOME" PATH="$STUBS_DIR:/opt/homebrew/bin:/usr/bin:/bin" K3DM_AGENT_LOAD=0 \
+    make -C "$PROJECT_ROOT" --no-print-directory install-repo-sync
+  [ "$status" -eq 0 ]
+  [ -f "$plist" ]
+
+  local path_val
+  path_val="$(_extract_plist_path "$plist")"
+  [ -n "$path_val" ]
+
+  [[ "$path_val" == *"/opt/homebrew/bin"* ]]
+  [[ "$path_val" == *"/usr/bin"* ]]
+
+  local hb_prefix="${path_val%%/opt/homebrew/bin*}"
+  local ub_prefix="${path_val%%/usr/bin*}"
+  [ "${#hb_prefix}" -lt "${#ub_prefix}" ]
+
+  # Expected standard tool chain with Homebrew first
+  [[ "$path_val" == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"* ]]
+}
+
+@test "E2: the job, run with only the rendered plist's environment, invokes no installer for kubectl or gh (N1)" {
+  [[ "$(uname -s)" == Darwin ]] || skip 'launchd PATH is macOS-only'
+  [ -x "/opt/homebrew/bin/kubectl" ] || skip '/opt/homebrew/bin/kubectl is absent on this host'
+  [ -x "/opt/homebrew/bin/gh" ] || skip '/opt/homebrew/bin/gh is absent on this host'
+
+  local plist="$AGENTS_DIR/com.k3d-manager.repo-sync.plist"
+
+  run env -i HOME="$SCRATCH_HOME" PATH="$STUBS_DIR:/opt/homebrew/bin:/usr/bin:/bin" K3DM_AGENT_LOAD=0 \
+    make -C "$PROJECT_ROOT" --no-print-directory install-repo-sync
+  [ "$status" -eq 0 ]
+  [ -f "$plist" ]
+
+  local rendered_path
+  rendered_path="$(_extract_plist_path "$plist")"
+
+  # Under launchd, when EnvironmentVariables does not define PATH, default is /usr/bin:/bin:/usr/sbin:/sbin
+  local job_path="${rendered_path:-/usr/bin:/bin:/usr/sbin:/sbin}"
+
+  # kubectl and gh must be resolvable under the job's PATH
+  run env -i PATH="$job_path" bash -c 'command -v kubectl && command -v gh'
+  [ "$status" -eq 0 ]
+
+  # The job environment must not trigger kubectl installer
+  : > "$INSTALLER_LOG"
+  _probe_installer_invocation "$job_path" "$INSTALLER_LOG"
+  [ ! -s "$INSTALLER_LOG" ]
+}
+
+@test "N1 positive control: default launchd PATH without Homebrew invokes installer for kubectl" {
+  [[ "$(uname -s)" == Darwin ]] || skip 'launchd PATH is macOS-only'
+
+  local default_launchd_path="/usr/bin:/bin:/usr/sbin:/sbin"
+
+  # Under launchd's default PATH without Homebrew, kubectl is absent
+  run env -i PATH="$default_launchd_path" bash -c 'command -v kubectl'
+  [ "$status" -ne 0 ]
+
+  # Missing kubectl in PATH triggers _install_kubernetes_cli, which invokes brew install kubectl
+  : > "$INSTALLER_LOG"
+  _probe_installer_invocation "$default_launchd_path" "$INSTALLER_LOG"
+  [ -s "$INSTALLER_LOG" ]
+  grep -q "brew install kubectl" "$INSTALLER_LOG"
+}
```
