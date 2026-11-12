# Review brief: Hermes values_branch fix (Luna) — cross-vendor diff review

**Role:** review child of `2026-11-08-hermes-values-branch-flags-deploy-hub-and-r9-retargets-release-branch` (first-pass trial step 2).
**Intent approved:** operator, 2026-11-08
**Approval:** operator, 2026-11-08 ("go ahead")
**Spec under review:** `docs/bugs/2026-11-08-hermes-values-branch-flags-deploy-hub-and-r9-retargets-release-branch.md` (read it in full first).

## Files

Read-only: review these, change none of them.
- `scripts/lib/hermes/sensors.py`
- `scripts/lib/hermes/repairs.py`
- `scripts/plugins/argocd.sh`
- `docs/guides/hermes.md`
- `scripts/tests/hermes/test_hermes.py`
- `scripts/tests/hermes/test_repairs.py`
- `scripts/tests/plugins/argocd_values_branch_drift.bats`

## Task

Review the worker's diff below against the spec: its Fix steps, its Do-not list and its Acceptance block. Report
findings only. Do not edit, commit or keep any file. You may `git apply` the diff in your own worktree to run the tests
(`python3 -m pytest scripts/tests/hermes/test_hermes.py scripts/tests/hermes/test_repairs.py -q` and
`bats scripts/tests/plugins/argocd_values_branch_drift.bats scripts/tests/bin/cluster_status_values_branch.bats`)
and to try mutations, but leave the worktree clean at exit (`git checkout -- . && git clean -fd`).

For each finding give:
- severity: blocker / should-fix / nit;
- file:line in the diff;
- a concrete input or state that breaks it;
- the spec line (Fix step, Do-not item, or M/N id) it violates.

Check in particular:
1. Each `must_not` (N1, N2) has a test that fails when its guard is removed (try it).
2. No path lets r9 carry a ref other than `deploy/hub`, including through the sensor's `expected` argument.
3. No `git` call or `K3DM_RELEASE_BRANCH` read remains on the expected-ref path in `sensors.py` or `argocd_check_values_branch`.
4. The exact r9 name and blast radius, `reversible` still `False`, and the guide's R9 row matches.
5. `values_branch` keeps its signature; `data["expected"]` is still set; `RELEASE_BRANCH` is gone with no importer left.
6. Tests were deleted or converted only where Fix step 4 says; no remaining assertion was weakened.
7. `deploy_argocd_applicationsets`, `make hub-promote` and the ApplicationSet manifests are untouched.

End with a one-line verdict: `land`, `land after fixes`, or `rework`. Under 500 words.

## Worker diff (uncommitted, against `k3d-manager-v1.43.15` at the worker's base `73c0c70a`)

```diff
diff --git a/docs/guides/hermes.md b/docs/guides/hermes.md
index 2cd09ef3..3eb28506 100644
--- a/docs/guides/hermes.md
+++ b/docs/guides/hermes.md
@@ -66,7 +66,7 @@ holds, and `approve` takes a fresh sensor cycle before executing it.
 | R3 | Refresh Hostinger edge access | all public hosts fail for two cycles | `scripts/k3d-manager refresh_access_layer` (the public wrapper for `_hostinger_refresh_access_layer`; never `make refresh`) |
 | R4 | Re-run transient CI | CI is `timed_out`, `cancelled`, or `stuck`, with a run ID | `gh api ... rerun-failed-jobs` using the `k3dm-hermes-gh-token` PAT in `GH_TOKEN` |
 | R5 | Quarantine stale ACG reconciliation | sustained Kine pressure, `state.db` >= 8 GiB, and the known stale `host.k3d.internal` registration | pause hub ArgoCD application-controller (opt-in automatic circuit breaker only) |
-| R9 | Reapply ApplicationSets on the release branch | `values_branch` degraded with stale references | `./scripts/k3d-manager deploy_argocd_applicationsets --confirm` with `K3D_MANAGER_BRANCH` pinned |
+| R9 | Reapply ApplicationSets pinned to deploy/hub | `values_branch` degraded with stale references | `./scripts/k3d-manager deploy_argocd_applicationsets --confirm` with `K3D_MANAGER_BRANCH=deploy/hub` |
 | R10 | Delete failed Jobs superseded by a newer CronJob spec | A failed, inactive CronJob-owned Job in `identity`, `monitoring`, or `cicd` has a different runnable template (image/command/args); never automatic | `kubectl ... delete job --wait=false -- <pinned Job names>`; the allowlisted namespace and exact target set are rechecked and pinned at approval time |
 
 ## Slack approvals (opt-in)
diff --git a/scripts/lib/hermes/repairs.py b/scripts/lib/hermes/repairs.py
index 0b9864dc..16d772e6 100644
--- a/scripts/lib/hermes/repairs.py
+++ b/scripts/lib/hermes/repairs.py
@@ -172,14 +172,12 @@ def _r9_precondition(records, _history, _state):
     item = _rec(records, "values_branch") or {}
     expected = item.get("data", {}).get("expected", "")
     return (_status(records, "values_branch") == "degraded" and
-            bool(item.get("data", {}).get("stale")) and
-            re.fullmatch(r"k3d-manager-v\d+\.\d+\.\d+", expected) is not None)
+            bool(item.get("data", {}).get("stale")) and expected == "deploy/hub")
 
 
 def _r9_command(records):
-    expected = (_rec(records, "values_branch") or {}).get("data", {}).get("expected", "")
     return (["./scripts/k3d-manager", "deploy_argocd_applicationsets", "--confirm"],
-            {"K3D_MANAGER_BRANCH": expected})
+            {"K3D_MANAGER_BRANCH": "deploy/hub"})
 
 
 def _r10_targets(records):
@@ -244,9 +242,9 @@ REPAIRS = {
            "precondition": _r8_precondition, "build_command": _r8_command, "cwd": ROOT,
            "blast_radius": "DaemonSet pods on stale node IPs are recreated", "reversible": True,
            "needs_scope": "local hub kubeconfig"},
-    "r9": {"key": "r9", "name": "Reapply ApplicationSets on the release branch",
+    "r9": {"key": "r9", "name": "Reapply ApplicationSets pinned to deploy/hub",
            "precondition": _r9_precondition, "build_command": _r9_command, "cwd": ROOT,
-           "blast_radius": "every k3d-manager-sourced Application on the hub and app cluster re-targets the release branch and syncs",
+           "blast_radius": "every k3d-manager-sourced Application on the hub and app cluster re-targets deploy/hub and syncs",
            "reversible": False, "needs_scope": "local hub kubeconfig"},
     "r10": {"key": "r10", "name": "Delete failed Jobs superseded by a newer CronJob spec",
             "precondition": _r10_precondition, "build_command": _r10_command, "cwd": None,
diff --git a/scripts/lib/hermes/sensors.py b/scripts/lib/hermes/sensors.py
index de8ffb42..ec84598c 100644
--- a/scripts/lib/hermes/sensors.py
+++ b/scripts/lib/hermes/sensors.py
@@ -17,7 +17,6 @@ WEBHOOK_SERVICE = "k3dm-webhook-token"
 ARGOCD_SERVICE = "k3dm-hermes-argocd-token"
 GITHUB_SERVICE = "k3dm-hermes-gh-token"
 TERMINAL_OPERATION_FAILURES = ("Error", "Failed")
-RELEASE_BRANCH = re.compile(r"\Ak3d-manager-v\d+\.\d+\.\d+\Z")
 
 
 def _keychain_secret(service):
@@ -112,30 +111,15 @@ def argocd(run, state, token=None, threshold=3, server="argocd.3ai-talk.org"):
 
 
 def _values_branch_expected(run, expected=None):
-    if expected:
-        return expected, None
-    configured = os.environ.get("K3DM_RELEASE_BRANCH", "").strip()
-    if configured:
-        return configured, None
-    try:
-        code, output = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], {})
-        if code != 0 or not output.strip():
-            return None, "checkout branch could not be determined"
-        return output.strip(), None
-    except Exception:
-        return None, "checkout branch could not be determined"
+    return expected or "deploy/hub", None
 
 
 def values_branch(run, argocd_run, state, token=None, expected=None, threshold=3,
                   server="argocd.3ai-talk.org"):
-    """Check k3d-manager Application sources against the checked-out release branch."""
+    """Check k3d-manager Application sources against the hub deploy branch."""
     branch, error = _values_branch_expected(run, expected)
     if error:
         return record("values_branch", "unknown", error)
-    if not RELEASE_BRANCH.fullmatch(branch):
-        return record("values_branch", "healthy",
-                      f"skipped: checkout on {branch}, not a release branch",
-                      data={"expected": branch, "skipped": True})
     token = token if token is not None else _keychain_secret(ARGOCD_SERVICE)
     if not token:
         return _unavailable("values_branch", ARGOCD_SERVICE)
diff --git a/scripts/plugins/argocd.sh b/scripts/plugins/argocd.sh
index c3aee106..4c8af5a8 100644
--- a/scripts/plugins/argocd.sh
+++ b/scripts/plugins/argocd.sh
@@ -2052,17 +2052,13 @@ EOF
 }
 
 function argocd_check_values_branch() {
-   local _expected="${1:-${K3D_MANAGER_BRANCH:-}}"
+   local _expected="${1:-${K3D_MANAGER_BRANCH:-deploy/hub}}"
    local _context="${2:-k3d-k3d-cluster}"
    local _owners="${3:-}"
    local _namespace="${ARGOCD_NAMESPACE:-cicd}"
    local _apps
    local _drift
 
-   if [[ -z "${_expected}" ]]; then
-      _expected="$(git -C "${SCRIPT_DIR}/.." rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
-   fi
-
    _apps="$(_kubectl get application -n "${_namespace}" --context "${_context}" -o json 2>/dev/null)"
    if [[ -z "${_apps}" ]]; then
       _warn "[argocd] Could not read Applications from ${_context}/${_namespace}"
diff --git a/scripts/tests/hermes/test_hermes.py b/scripts/tests/hermes/test_hermes.py
index d14240fd..4b886bcc 100644
--- a/scripts/tests/hermes/test_hermes.py
+++ b/scripts/tests/hermes/test_hermes.py
@@ -126,11 +126,11 @@ def test_status_checks_handles_invalid_empty_and_timeout_output_as_unknown():
     assert status_checks(lambda *_: (_ for _ in ()).throw(TimeoutError()), {})["status"] == "unknown"
 
 
-def _values_apps(revision="k3d-manager-v1.40.0", stale=0):
+def _values_apps(revision="deploy/hub", stale=0):
     apps = []
     for number in range(45):
         source = {"repoURL": "https://github.com/wilddog64/k3d-manager",
-                  "targetRevision": "k3d-manager-v1.39.0" if number < stale else revision}
+                  "targetRevision": "k3d-manager-v1.43.15" if number < stale else revision}
         if number in (2, 4):
             source["targetRevision"] = "HEAD"
         if number == 2:
@@ -150,7 +150,7 @@ def test_values_branch_realistic_fixture_ignores_head_and_other_repos():
     output = json.dumps(apps)
     assert len(output) > 200_000
     calls = []
-    result = values_branch(lambda *_: (0, "k3d-manager-v1.40.0"),
+    result = values_branch(lambda *_: (0, "k3d-manager-v1.43.15"),
                            lambda argv, _env: calls.append(argv) or (0, output), {}, token="x")
     assert result["status"] == "healthy"
     assert result["data"]["checked"] == 42
@@ -158,42 +158,64 @@ def test_values_branch_realistic_fixture_ignores_head_and_other_repos():
     assert calls == [["argocd", "app", "list", "-o", "json", "--grpc-web"]]
 
 
+def test_values_branch_defaults_to_deploy_hub_and_ignores_checkout_branch():
+    git_calls = []
+    checkout = lambda *args: git_calls.append(args) or (0, "k3d-manager-v1.43.15")
+    healthy = values_branch(checkout, lambda *_: (0, json.dumps(_values_apps())), {}, token="x")
+    assert healthy["status"] == "healthy"
+    assert healthy["data"]["expected"] == "deploy/hub"
+    assert repairs.propose([healthy], state={}) == []
+
+    stale_state = {}
+    stale_run = lambda *_: (0, json.dumps(_values_apps(stale=1)))
+    values_branch(checkout, stale_run, stale_state, token="x")
+    values_branch(checkout, stale_run, stale_state, token="x")
+    stale = values_branch(checkout, stale_run, stale_state, token="x")
+    assert stale["status"] == "degraded"
+    assert "app-0@k3d-manager-v1.43.15" in stale["evidence"]
+    assert git_calls == []
+    proposals = repairs.propose([stale], state={})
+    assert len(proposals) == 1 and proposals[0]["key"] == "r9"
+    assert proposals[0]["name"] == "Reapply ApplicationSets pinned to deploy/hub"
+    assert repairs.REPAIRS["r9"]["build_command"]([stale])[1] == {"K3D_MANAGER_BRANCH": "deploy/hub"}
+
+
 def test_values_branch_debounces_lag_then_stale_and_clears():
     output = json.dumps(_values_apps(stale=2))
     current = {}
     run = lambda *_: (0, output)
-    assert [values_branch(lambda *_: (0, "k3d-manager-v1.40.0"), run, current, token="x")["status"]
+    assert [values_branch(lambda *_: (0, "k3d-manager-v1.43.15"), run, current, token="x")["status"]
             for _ in range(2)] == ["healthy", "healthy"]
-    third = values_branch(lambda *_: (0, "k3d-manager-v1.40.0"), run, current, token="x")
-    assert third["status"] == "degraded" and "app-0@k3d-manager-v1.39.0" in third["evidence"]
-    clean = values_branch(lambda *_: (0, "k3d-manager-v1.40.0"),
+    third = values_branch(lambda *_: (0, "k3d-manager-v1.43.15"), run, current, token="x")
+    assert third["status"] == "degraded" and "app-0@k3d-manager-v1.43.15" in third["evidence"]
+    clean = values_branch(lambda *_: (0, "k3d-manager-v1.43.15"),
                           lambda *_: (0, json.dumps(_values_apps())), current, token="x")
     assert clean["status"] == "healthy"
 
 
 def test_values_branch_counts_two_stale_sources_as_one_app():
     apps = [{"metadata": {"name": "one-app"}, "spec": {"sources": [
-        {"repoURL": "https://github.com/wilddog64/k3d-manager", "targetRevision": "k3d-manager-v1.39.0"},
-        {"repoURL": "https://github.com/wilddog64/k3d-manager", "targetRevision": "k3d-manager-v1.39.0"},
+        {"repoURL": "https://github.com/wilddog64/k3d-manager", "targetRevision": "k3d-manager-v1.43.15"},
+        {"repoURL": "https://github.com/wilddog64/k3d-manager", "targetRevision": "k3d-manager-v1.43.15"},
     ]}}]
-    result = values_branch(lambda *_: (0, "k3d-manager-v1.40.0"),
+    result = values_branch(lambda *_: (0, "k3d-manager-v1.43.15"),
                            lambda *_: (0, json.dumps(apps)), {}, token="x")
 
     assert result["evidence"].startswith("1 apps (2 source refs) not on")
-    assert result["evidence"].count("one-app@k3d-manager-v1.39.0") == 1
+    assert result["evidence"].count("one-app@k3d-manager-v1.43.15") == 1
     assert len(result["data"]["stale"]) == 2
 
 
 def test_values_branch_counts_multiple_apps_and_mixed_sources():
     apps = [
         {"metadata": {"name": "one-app"}, "spec": {"sources": [
-            {"repoURL": "https://github.com/wilddog64/k3d-manager", "targetRevision": "k3d-manager-v1.39.0"},
-            {"repoURL": "https://github.com/wilddog64/k3d-manager", "targetRevision": "k3d-manager-v1.40.0"},
+            {"repoURL": "https://github.com/wilddog64/k3d-manager", "targetRevision": "k3d-manager-v1.43.15"},
+            {"repoURL": "https://github.com/wilddog64/k3d-manager", "targetRevision": "deploy/hub"},
         ]}},
         {"metadata": {"name": "two-app"}, "spec": {"source":
-            {"repoURL": "https://github.com/wilddog64/k3d-manager", "targetRevision": "k3d-manager-v1.39.0"}}},
+            {"repoURL": "https://github.com/wilddog64/k3d-manager", "targetRevision": "k3d-manager-v1.43.15"}}},
     ]
-    result = values_branch(lambda *_: (0, "k3d-manager-v1.40.0"),
+    result = values_branch(lambda *_: (0, "k3d-manager-v1.43.15"),
                            lambda *_: (0, json.dumps(apps)), {}, token="x")
 
     assert result["evidence"].startswith("2 apps (2 source refs) not on")
@@ -202,66 +224,43 @@ def test_values_branch_counts_multiple_apps_and_mixed_sources():
 def test_values_branch_excludes_head_from_stale_counts():
     apps = [{"metadata": {"name": "one-app"}, "spec": {"sources": [
         {"repoURL": "https://github.com/wilddog64/k3d-manager", "targetRevision": "HEAD"},
-        {"repoURL": "https://github.com/wilddog64/k3d-manager", "targetRevision": "k3d-manager-v1.39.0"},
+        {"repoURL": "https://github.com/wilddog64/k3d-manager", "targetRevision": "k3d-manager-v1.43.15"},
     ]}}]
-    result = values_branch(lambda *_: (0, "k3d-manager-v1.40.0"),
+    result = values_branch(lambda *_: (0, "k3d-manager-v1.43.15"),
                            lambda *_: (0, json.dumps(apps)), {}, token="x")
 
     assert result["evidence"].startswith("1 apps (1 source refs) not on")
     assert result["data"]["tracking_head"] == 1
 
 
-def test_values_branch_nonrelease_is_skipped_and_never_pages(monkeypatch):
-    from hermes import pager
-    calls = []
-    state = {}
-    def argo(*args):
-        calls.append(args)
-        return 0, "[]"
-    pager_state = {}
-    for _ in range(pager.SENSOR_UNKNOWN_CYCLES + 1):
-        item = values_branch(lambda *_: (0, "main"), argo, state, token="x")
-        assert item["status"] == "healthy" and item["data"]["skipped"] is True
-        assert pager.health_events([item], pager_state) == []
-    assert calls == []
-    unknown_state, pages = {}, []
-    for _ in range(pager.SENSOR_UNKNOWN_CYCLES):
-        pages += pager.health_events([dict(item, status="unknown")], unknown_state)
-    assert any("values_branch check unknown" in text for text in pages), "control: unknown must page"
-
-
-def test_values_branch_nonrelease_skips_even_without_a_token(monkeypatch):
-    from hermes import sensors as sensor_module
-    monkeypatch.setattr(sensor_module, "_keychain_secret", lambda *_: "")
-    item = values_branch(lambda *_: (0, "claude/foo"), lambda *_: (0, "[]"), {})
-    assert item["status"] == "healthy" and item["data"]["skipped"] is True
-
-
 def test_values_branch_zero_refs_and_real_failures_are_unknown():
     no_refs = json.dumps([{"metadata": {"name": "head"}, "spec": {"source": {
         "repoURL": "https://github.com/wilddog64/k3d-manager", "targetRevision": "HEAD"}}}])
-    item = values_branch(lambda *_: (0, "k3d-manager-v1.40.0"),
+    item = values_branch(lambda *_: (0, "k3d-manager-v1.43.15"),
                          lambda *_: (0, no_refs), {}, token="x")
     assert item["status"] == "unknown" and "no k3d-manager" in item["evidence"]
     failed = values_branch(lambda *_: (1, "git failure"), lambda *_: (0, "[]"), {}, token="x")
     assert failed["status"] == "unknown"
 
 
-def test_values_branch_resolution_order_and_argocd_failures(monkeypatch):
+def test_values_branch_fixed_expected_ref_and_argocd_failures(monkeypatch):
     monkeypatch.setenv("K3DM_RELEASE_BRANCH", "k3d-manager-v1.39.0")
     assert k3dm_hermes is not None
     from hermes.sensors import _values_branch_expected
-    assert _values_branch_expected(lambda *_: (0, "main"), "k3d-manager-v1.40.0")[0] == "k3d-manager-v1.40.0"
-    assert _values_branch_expected(lambda *_: (0, "main"))[0] == "k3d-manager-v1.39.0"
-    bad_json = values_branch(lambda *_: (0, "k3d-manager-v1.40.0"),
+    git_calls = []
+    run = lambda *args: git_calls.append(args) or (0, "k3d-manager-v1.43.15")
+    assert _values_branch_expected(run, "deploy/hub")[0] == "deploy/hub"
+    assert _values_branch_expected(run)[0] == "deploy/hub"
+    assert git_calls == []
+    bad_json = values_branch(run,
                              lambda *_: (0, "not json"), {}, token="x")
     assert bad_json["status"] == "unknown"
-    rejected = values_branch(lambda *_: (0, "k3d-manager-v1.40.0"),
+    rejected = values_branch(run,
                              lambda *_: (1, "Unauthenticated"), {}, token="x")
     assert "re-mint" in rejected["evidence"]
     from hermes import sensors as sensor_module
     monkeypatch.setattr(sensor_module, "_keychain_secret", lambda *_: "")
-    missing = values_branch(lambda *_: (0, "k3d-manager-v1.40.0"), lambda *_: (0, "[]"), {})
+    missing = values_branch(run, lambda *_: (0, "[]"), {})
     assert missing["status"] == "unknown" and "credential unavailable" in missing["evidence"]
 
 
diff --git a/scripts/tests/hermes/test_repairs.py b/scripts/tests/hermes/test_repairs.py
index b19b2255..14ced023 100644
--- a/scripts/tests/hermes/test_repairs.py
+++ b/scripts/tests/hermes/test_repairs.py
@@ -137,28 +137,31 @@ def test_r8_ignores_drift_without_daemonset_owner():
 
 
 def r9_records(status="degraded", stale=True):
-    data = {"expected": "k3d-manager-v1.40.0",
-            "stale": [{"app": "loki", "revision": "k3d-manager-v1.39.0"}] if stale else []}
-    return [record("values_branch", status, "2 apps not on k3d-manager-v1.40.0", data)]
+    data = {"expected": "deploy/hub",
+            "stale": [{"app": "loki", "revision": "k3d-manager-v1.43.15"}] if stale else []}
+    return [record("values_branch", status, "2 apps not on deploy/hub", data)]
 
 
-def test_r9_requires_stale_values_branch_and_pins_release_env():
+def test_r9_requires_stale_values_branch_and_pins_deploy_hub():
     current = state()
     proposal = repairs.propose(r9_records(), current)[0]
     assert proposal["key"] == "r9"
+    assert proposal["name"] == "Reapply ApplicationSets pinned to deploy/hub"
     assert proposal["command"] == "./scripts/k3d-manager deploy_argocd_applicationsets --confirm"
     assert repairs.REPAIRS["r9"]["reversible"] is False
     calls = []
     outcome = repairs.approve(proposal["action_id"], current, r9_records(),
                               lambda *args: calls.append(args) or (0, "done"))
     assert outcome["outcome"] == "executed"
-    assert calls[0][1] == {"K3D_MANAGER_BRANCH": "k3d-manager-v1.40.0"}
+    assert calls[0][1] == {"K3D_MANAGER_BRANCH": "deploy/hub"}
 
 
 def test_r9_ignores_unknown_healthy_or_empty_stale():
     assert repairs.propose(r9_records("unknown"), state()) == []
     assert repairs.propose(r9_records("healthy"), state()) == []
     assert repairs.propose(r9_records("degraded", False), state()) == []
+    assert repairs.propose([record("values_branch", "degraded", data={
+        "expected": "k3d-manager-v1.43.15", "stale": [{"app": "loki"}]})], state()) == []
 
 
 def r10_records(names=("job-b", "job-a"), context="ctx"):
diff --git a/scripts/tests/plugins/argocd_values_branch_drift.bats b/scripts/tests/plugins/argocd_values_branch_drift.bats
index 7eca50de..760f3efa 100644
--- a/scripts/tests/plugins/argocd_values_branch_drift.bats
+++ b/scripts/tests/plugins/argocd_values_branch_drift.bats
@@ -29,6 +29,53 @@ _clean_fixture() {
 EOF
 }
 
+_hub_fixture() {
+  cat <<'EOF'
+{"items":[{"metadata":{"name":"hub-app"},"spec":{"sources":[{"repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"deploy/hub"}]}}]}
+EOF
+}
+
+_release_fixture() {
+  cat <<'EOF'
+{"items":[{"metadata":{"name":"release-app"},"spec":{"sources":[{"repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"k3d-manager-v1.43.15"}]}}]}
+EOF
+}
+
+_stub_git() {
+  mkdir -p "${BATS_TEST_TMPDIR}/stub-bin"
+  cat >"${BATS_TEST_TMPDIR}/stub-bin/git" <<'EOF'
+#!/usr/bin/env bash
+printf '%s\n' "$*" >>"${GIT_CALLS}"
+printf '%s\n' 'k3d-manager-v1.43.15'
+EOF
+  chmod +x "${BATS_TEST_TMPDIR}/stub-bin/git"
+  export GIT_CALLS="${BATS_TEST_TMPDIR}/git-calls"
+  : >"${GIT_CALLS}"
+  export PATH="${BATS_TEST_TMPDIR}/stub-bin:${PATH}"
+}
+
+@test "argocd values branch: no-argument default is deploy/hub and does not call git" {
+  unset K3D_MANAGER_BRANCH
+  _stub_git
+  _kubectl() { _hub_fixture; }
+  [ -d "${BATS_TEST_TMPDIR}/stub-bin" ]
+  run argocd_check_values_branch
+  [ "$status" -eq 0 ]
+  [[ "$output" == *"Expected values branch: deploy/hub"* ]]
+  [ ! -s "$GIT_CALLS" ]
+}
+
+@test "argocd values branch: no-argument check flags release ref without calling git" {
+  unset K3D_MANAGER_BRANCH
+  _stub_git
+  _kubectl() { _release_fixture; }
+  [ -d "${BATS_TEST_TMPDIR}/stub-bin" ]
+  run argocd_check_values_branch
+  [ "$status" -eq 1 ]
+  [[ "$output" == *"release-app k3d-manager-v1.43.15"* ]]
+  [ ! -s "$GIT_CALLS" ]
+}
+
 @test "argocd values branch: reports drift and returns 1 when an Application is stale" {
   _kubectl() { _mixed_fixture; }
 
```
