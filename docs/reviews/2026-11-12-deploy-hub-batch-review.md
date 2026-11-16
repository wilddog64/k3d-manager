# Review brief: deploy/hub batch: checkout follows deploy/hub, promote guard fails closed (Luna) — cross-vendor diff review

**Role:** review child of `deploy-hub-batch`.
**Intent approved:** operator, 2026-11-12
**Approval basis:** "dispatch as you suggest"; first-pass quality trial: cross-vendor diff review
**Spec under review:** `docs/bugs/2026-11-12-deploy-hub-batch-checkout-follows-deploy-hub-and-promote-guard-fails-closed.md` (read it in full first).

## Files

Read-only: review these, change none of them.
- `bin/k3dm-hermes`
- `bin/k3dm-hub-promote`
- `bin/k3dm-repo-sync`
- `docs/howto/checkout-auto-sync.md`
- `docs/howto/hub-promote.md`
- `docs/howto/hub-sync.md`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`
- `scripts/tests/bin/hub_promote.bats`
- `scripts/tests/bin/repo_sync.bats`
- `scripts/tests/bin/test_dashboard_queries.py`
- `scripts/tests/bin/test_hermes_checkout_lag.py`
- `scripts/tests/plugins/grafana_dashboard_bugs.bats`

## Task

Review the worker's diff below against the spec: its Fix, Contract readers and Acceptance block. Report findings only. Do not edit, commit or keep any file. You may `git apply` the diff in your own worktree to run the touched suites and try mutations, but leave the worktree clean at exit (`git checkout -- . && git clean -fd`). Never touch the real Keychain, LaunchAgents, `launchctl`, GitHub, or a live Pushgateway.

For each finding give: severity (blocker / should-fix / nit); file:line in the diff; a concrete input or state that breaks it; the spec line (Fix item or M/N id) it violates.

Check in particular:
1. Each must_not (N3-N7): is there a test for exactly that state, and would it fail on the pre-fix code at 64b5fe27?
2. The worker found a spec conflict: Fix A.4 says `--check` fetches, D.1/E5 say no fetch; it kept no-fetch. Which reading do the Acceptance items and Contract readers need? Does anything that reads `--check` output now get stale data?
3. Every reset of the hub checkout to deploy/hub: is a backup ref always written first, and is the reset refused for a diverged checkout and for local commits (M9-M11)? Try the order of guards.
4. The promote guard: every error path (git failure, missing ref, unreadable state) now refuses rather than proceeding; BREAK_GLASS still works as before.
5. Hermes checkout-lag and the Bugs dashboard: the compared ref is deploy/hub everywhere, and the dashboard query still matches the series the producer emits.

End with a one-line verdict: `land`, `land after fixes`, or `rework`. Under 500 words.

## Worker diff (uncommitted, against `k3d-manager-v1.44.0` at the worker's base `64b5fe27`)

```diff
diff --git a/bin/k3dm-hermes b/bin/k3dm-hermes
index b3537c17..d9becd92 100755
--- a/bin/k3dm-hermes
+++ b/bin/k3dm-hermes
@@ -627,22 +627,19 @@ def _newest_release_branch(current, env):
         return current
 
 
-def _push_checkout_lag(upstream_ref, upstream_branch, newest_branch):
+def _push_checkout_lag(lag_ref):
     """Publish code-only checkout lag. Failures are intentionally non-fatal."""
     try:
-        if not (_METRIC_LABEL.fullmatch(upstream_branch or "") and
-                _METRIC_LABEL.fullmatch(newest_branch or "")):
+        if not _METRIC_LABEL.fullmatch(lag_ref or ""):
             return
         result = subprocess.run(
-            ["git", "rev-list", "--count", f"HEAD..{upstream_ref}", "--", ".",
+            ["git", "rev-list", "--count", f"HEAD..{lag_ref}", "--", ".",
              ":!docs", ":!memory-bank", ":!CHANGELOG.md"], cwd=ROOT,
             capture_output=True, text=True, timeout=60, check=False)
         if result.returncode != 0 or not result.stdout.strip().isdigit():
             return
         count = int(result.stdout.strip())
-        newest = int(upstream_branch == newest_branch)
-        body = (f'k3dm_hub_checkout_code_commits_behind{{branch="{upstream_branch}"}} {count}\n'
-                f'k3dm_hub_checkout_on_newest_release{{newest_branch="{newest_branch}"}} {newest}\n'
+        body = (f'k3dm_hub_checkout_code_commits_behind{{branch="deploy/hub"}} {count}\n'
                 f'k3dm_hub_checkout_last_check_timestamp_seconds {time.time()}\n').encode()
         base = os.environ.get("K3DM_VECTORDB_PUSHGATEWAY_URL", "http://localhost:19094").rstrip("/")
         request = urllib.request.Request(f"{base}/metrics/job/k3dm-hub-checkout", data=body,
@@ -720,23 +717,18 @@ def _refresh_index(state, now=None):
                                  env=fetch_env)
         if fetched.returncode != 0:
             raise RuntimeError(f"git fetch failed: {(fetched.stderr or '').strip()}")
-        lag_ref_fetched = True
-        if (not os.environ.get("K3DM_INDEX_REF", "").strip() and
-                newest_branch != upstream_branch):
-            try:
-                upstream_fetch = subprocess.run(
-                    ["git", "fetch", "--quiet", "origin",
-                     f"+refs/heads/{upstream_branch}:refs/remotes/origin/{upstream_branch}"],
-                    cwd=ROOT, capture_output=True, text=True, timeout=60, check=False,
-                    env=fetch_env)
-                if upstream_fetch.returncode != 0:
-                    lag_ref_fetched = False
-            except Exception:
-                lag_ref_fetched = False
-            if not lag_ref_fetched:
-                print("hub checkout lag skipped: upstream ref fetch failed", file=sys.stderr)
-        if lag_ref_fetched:
-            _push_checkout_lag(upstream_ref, upstream_branch, newest_branch)
+        try:
+            lag_fetch = subprocess.run(
+                ["git", "fetch", "--quiet", "origin",
+                 "+refs/heads/deploy/hub:refs/remotes/origin/deploy/hub"],
+                cwd=ROOT, capture_output=True, text=True, timeout=60, check=False,
+                env=fetch_env)
+        except Exception:
+            lag_fetch = None
+        if lag_fetch is None or lag_fetch.returncode != 0:
+            print("hub checkout lag skipped: deploy/hub fetch failed", file=sys.stderr)
+        else:
+            _push_checkout_lag("origin/deploy/hub")
         paused_until = float(state.get("index_paused_until", 0) or 0)
         if paused_until and now < paused_until:
             metrics["result"] = "paused"
diff --git a/bin/k3dm-hub-promote b/bin/k3dm-hub-promote
index c76db18a..ede7f01a 100755
--- a/bin/k3dm-hub-promote
+++ b/bin/k3dm-hub-promote
@@ -23,7 +23,7 @@ uncontained_commits() {
   if [[ "$old" =~ ^0+$ || -z "$target" || -z "$old" ]]; then
     return 0
   fi
-  git_cmd cherry "$target" "$old" 2>/dev/null | awk '$1 == "+" {print $2}' || true
+  git_cmd cherry "$target" "$old" | awk '$1 == "+" {print $2}'
 }
 
 print_uncontained_list() {
@@ -135,25 +135,39 @@ record_move() {
 }
 
 status() {
-  local sha tags release ahead
+  local sha tags release ahead local_sha origin_sha counts local_ahead local_behind
   sha="$(remote_sha)"
   printf '[hub-promote] deploy/hub: %s\n' "$sha"
   tags="$(git_cmd ls-remote --tags "$REMOTE" "refs/tags/${TAG_PREFIX}*" | awk '$2 !~ /\^\{\}$/ {print}' | sort -k2 -r | head -3 || true)"
   printf '[hub-promote] last three hub-promote tags:\n%s\n' "${tags:-  (none)}"
   release="${RELEASE_BRANCH:-$(git_cmd branch --show-current)}"
   if [[ ! "$release" =~ ^k3d-manager-v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
-    release="$(git_cmd for-each-ref --sort=-committerdate --format='%(refname:short)' 'refs/remotes/origin/k3d-manager-v*' | head -1)"
+    release="$(git_cmd for-each-ref --sort=-committerdate --format='%(refname:lstrip=3)' 'refs/remotes/origin/k3d-manager-v*' | head -1)"
   fi
   if [[ -z "$release" ]]; then release=main; fi
-  ahead="$(git_cmd rev-list --count "$sha..$release" 2>/dev/null || printf '?')"
+  if ! git_cmd fetch --quiet --no-tags "$REMOTE" "+refs/heads/$release:refs/remotes/$REMOTE/$release" "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH"; then
+    printf '[hub-promote] WARNING: fetch failed; counts may be stale\n' >&2
+  fi
+  ahead="$(git_cmd rev-list --count "$sha..refs/remotes/$REMOTE/$release" 2>/dev/null || printf '?')"
   printf '[hub-promote] %s ahead of deploy/hub: %s\n' "$release" "$ahead"
+  local_sha="$(git_cmd rev-parse --verify "refs/heads/$release^{commit}" 2>/dev/null || true)"
+  origin_sha="$(git_cmd rev-parse --verify "refs/remotes/$REMOTE/$release^{commit}" 2>/dev/null || true)"
+  if [[ -n "$local_sha" && -n "$origin_sha" && "$local_sha" != "$origin_sha" ]]; then
+    counts="$(git_cmd rev-list --left-right --count "refs/heads/$release...refs/remotes/$REMOTE/$release")" || counts='? ?'
+    if [[ "$counts" == *$'\t'* ]]; then
+      read -r local_ahead local_behind <<< "$counts"
+      printf '[hub-promote] local %s is %s behind / %s ahead of origin\n' "$release" "$local_behind" "$local_ahead"
+    else
+      printf '[hub-promote] local %s is ? behind / ? ahead of origin\n' "$release"
+    fi
+  fi
   local rel_sha
-  rel_sha="$(git_cmd rev-parse --verify "refs/remotes/$REMOTE/$release^{commit}" 2>/dev/null || git_cmd rev-parse --verify "$release^{commit}" 2>/dev/null || true)"
+  rel_sha="$origin_sha"
   if [[ -n "$rel_sha" ]]; then
     local -a uncontained=()
-    while IFS= read -r c; do
-      [[ -n "$c" ]] && uncontained+=("$c")
-    done < <(uncontained_commits "$rel_sha" "$sha")
+    local uncontained_text
+    uncontained_text="$(uncontained_commits "$rel_sha" "$sha")" || printf '[hub-promote] WARNING: cannot check deploy/hub containment\n' >&2
+    [[ -z "${uncontained_text:-}" ]] || mapfile -t uncontained <<< "$uncontained_text"
     if (( ${#uncontained[@]} > 0 )); then
       printf '[hub-promote] uncontained commits on deploy/hub:\n'
       print_uncontained_list "${uncontained[@]}"
@@ -218,9 +232,9 @@ rollback() {
     fi
   fi
   local -a uncontained=()
-  while IFS= read -r c; do
-    [[ -n "$c" ]] && uncontained+=("$c")
-  done < <(uncontained_commits "$live_sha" "$old")
+  local uncontained_text
+  uncontained_text="$(uncontained_commits "$live_sha" "$old")" || die "cannot check deploy/hub containment ($old against $live_sha)"
+  [[ -z "$uncontained_text" ]] || mapfile -t uncontained <<< "$uncontained_text"
   if (( ${#uncontained[@]} > 0 )); then
     if [[ "$break_glass" != 1 ]]; then
       printf '[hub-promote] ERROR: deploy/hub has uncontained commits not in promotion stack top %s:\n' "$top" >&2
@@ -254,10 +268,14 @@ main() {
         printf '[hub-promote] deploy/hub is already at %s; nothing to promote\n' "$new"
         exit 0
       fi
+      if [[ ! "$old" =~ ^0+$ ]]; then
+        git_cmd fetch --no-tags "$REMOTE" "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH" || die "cannot fetch $REMOTE $BRANCH"
+        git_cmd cat-file -e "$old^{commit}" || die "deploy/hub commit $old is not available locally; refusing to promote"
+      fi
       local -a uncontained=()
-      while IFS= read -r c; do
-        [[ -n "$c" ]] && uncontained+=("$c")
-      done < <(uncontained_commits "$new" "$old")
+      local uncontained_text
+      uncontained_text="$(uncontained_commits "$new" "$old")" || die "cannot check deploy/hub containment ($old against $new)"
+      [[ -z "$uncontained_text" ]] || mapfile -t uncontained <<< "$uncontained_text"
       if (( ${#uncontained[@]} > 0 )); then
         if [[ "$break_glass" != 1 ]]; then
           printf '[hub-promote] ERROR: deploy/hub contains %d commit(s) not in %s:\n' "${#uncontained[@]}" "$ref" >&2
diff --git a/bin/k3dm-repo-sync b/bin/k3dm-repo-sync
index f83dcfe9..948a8d7e 100755
--- a/bin/k3dm-repo-sync
+++ b/bin/k3dm-repo-sync
@@ -83,9 +83,10 @@ def repo_label(path):
 def role():
     p = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", pathlib.Path.home() / ".config")) / "k3d-manager/machine-role"
     try:
-        return p.read_text().strip()
+        value = p.read_text().strip()
+        return value or "missing"
     except OSError:
-        return "worker"
+        return "missing"
 
 
 def repositories():
@@ -145,6 +146,7 @@ def result_for(path, is_hub):
         upstream = up.stdout.strip()
         remote, _, ref = upstream.partition("/")
     if is_hub_root:
+        rec["remote"] = remote
         fetch_args = [
             "fetch",
             "--no-tags",
@@ -161,11 +163,17 @@ def result_for(path, is_hub):
         vals = counts.stdout.split()
         ahead, behind = map(int, vals[:2])
         rec["behind_before"] = behind
-        if ahead and not (is_hub and path.resolve() == ROOT.resolve()):
-            rec["result"] = "skipped:ahead"
-            return rec
     if os.environ.get("K3DM_REPO_SYNC_CHECK") == "1":
-        rec["result"] = "would-update" if rec["behind_before"] else "current"
+        if is_hub_root and counts.returncode == 0 and ahead:
+            dirty = git(path, "status", "--porcelain", "--untracked-files=no").stdout.strip()
+            additions = git(path, "diff", "--name-only", "--diff-filter=A", "HEAD", target).stdout.splitlines()
+            collision = any(os.path.lexists(path / item) for item in additions)
+            rec["result"] = "skipped:dirty" if dirty or collision else "would-reset-to-deploy-hub"
+        elif counts.returncode == 0 and ahead:
+            rec["result"] = "skipped:diverged" if rec["behind_before"] else "skipped:ahead"
+        else:
+            rec["result"] = "would-update" if rec["behind_before"] else "current"
+        rec["behind_after"] = rec["behind_before"]
         if is_hub_root:
             rec["promote_backlog_unknown"] = True
         return rec
@@ -176,9 +184,11 @@ def result_for(path, is_hub):
         fetched = run(["git", "-C", str(path), *fetch_args], timeout=TIMEOUT, env=env)
     except subprocess.TimeoutExpired:
         rec["result"] = "fetch_failed"
+        rec["behind_after"] = rec["behind_before"]
         return rec
     if fetched.returncode:
         rec["result"] = "fetch_failed"
+        rec["behind_after"] = rec["behind_before"]
         return rec
     if is_hub_root and ref:
         try:
@@ -194,21 +204,49 @@ def result_for(path, is_hub):
     fresh_counts = git(path, "rev-list", "--left-right", "--count", f"HEAD...{target}")
     if fresh_counts.returncode == 0:
         fresh_ahead, rec["behind_before"] = map(int, fresh_counts.stdout.split()[:2])
-        if fresh_ahead and not (is_hub and path.resolve() == ROOT.resolve()):
-            rec["result"] = "skipped:ahead"
+        ahead = fresh_ahead
+        if fresh_ahead and not is_hub_root:
+            rec["result"] = "skipped:diverged" if rec["behind_before"] else "skipped:ahead"
+            rec["behind_after"] = rec["behind_before"]
             return rec
-    if is_hub and path.resolve() == ROOT.resolve():
-        ff = git(path, "merge-base", "--is-ancestor", "HEAD", "origin/deploy/hub")
+    if is_hub_root:
+        ff = git(path, "merge-base", "--is-ancestor", "HEAD", target)
         if ff.returncode:
-            rec["result"] = "skipped:not-ff-to-deploy-hub"
+            dirty = git(path, "status", "--porcelain", "--untracked-files=no").stdout.strip()
+            additions = git(path, "diff", "--name-only", "--diff-filter=A", "HEAD", target).stdout.splitlines()
+            collision = any(os.path.lexists(path / item) for item in additions)
+            if dirty or collision:
+                rec["result"] = "skipped:dirty"
+                rec["behind_after"] = rec["behind_before"]
+                return rec
+            stamp = datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
+            backup_ref = f"refs/k3dm/repo-sync-backup/{stamp}"
+            saved = git(path, "update-ref", backup_ref, rec["old_head"], "")
+            if saved.returncode:
+                rec["result"] = "blocked"
+                rec["behind_after"] = rec["behind_before"]
+                return rec
+            reset = git(path, "reset", "--hard", target)
+            if reset.returncode:
+                rec["result"] = "blocked"
+                rec["behind_after"] = rec["behind_before"]
+                return rec
+            rec["new_head"] = git(path, "rev-parse", "HEAD").stdout.strip()
+            rec["result"] = "reset-to-deploy-hub"
+            rec["backup_ref"] = backup_ref
+            after = git(path, "rev-list", "--left-right", "--count", f"HEAD...{comparison_ref}")
+            if after.returncode == 0:
+                rec["behind_after"] = int(after.stdout.split()[1])
             return rec
     try:
         merged = run(["git", "-C", str(path), "merge", "--ff-only", target], timeout=TIMEOUT, env=env)
     except subprocess.TimeoutExpired:
         rec["result"] = "fetch_failed"
+        rec["behind_after"] = rec["behind_before"]
         return rec
     if merged.returncode:
         rec["result"] = "blocked"
+        rec["behind_after"] = rec["behind_before"]
         return rec
     rec["new_head"] = git(path, "rev-parse", "HEAD").stdout.strip()
     rec["result"] = "updated" if rec["new_head"] != rec["old_head"] else "current"
@@ -245,6 +283,11 @@ def main():
     check = args == ["--check"]
     if args and not check:
         print("usage: k3dm-repo-sync [--check] [--remote HOST]", file=sys.stderr); return 2
+    machine_role = role()
+    if machine_role == "missing":
+        role_path = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", pathlib.Path.home() / ".config")) / "k3d-manager/machine-role"
+        print(f"[repo-sync] ERROR: machine-role file missing or empty: {role_path}", file=sys.stderr)
+        return 1
     STATE_DIR.mkdir(parents=True, exist_ok=True)
     try:
         LOCK.mkdir()
@@ -264,7 +307,7 @@ def main():
         raise
     try:
         os.environ["K3DM_REPO_SYNC_CHECK"] = "1" if check else "0"
-        is_hub = role() == "hub"
+        is_hub = machine_role == "hub"
         previous = {}
         previous_state = {}
         try:
@@ -275,7 +318,7 @@ def main():
             pass
         records = [result_for(p, is_hub) for p in repositories()]
         for rec in records:
-            rec["last_success_timestamp_seconds"] = (rec["run_time"] if rec["result"] in ("current", "updated")
+            rec["last_success_timestamp_seconds"] = (rec["run_time"] if rec["result"] in ("current", "updated", "reset-to-deploy-hub")
                                                        else previous.get(rec["path"], 0))
         run_time = int(time.time())
         state = {"run_time": run_time, "repositories": records,
@@ -291,7 +334,7 @@ def main():
                 state["webhook_restart_pending"] = True
                 state["webhook_restart_pending_recorded_at"] = pending_recorded_at
         for rec in records:
-            if pathlib.Path(rec["path"]).resolve() != ROOT.resolve() or rec["result"] != "updated":
+            if pathlib.Path(rec["path"]).resolve() != ROOT.resolve() or rec["result"] not in ("updated", "reset-to-deploy-hub"):
                 continue
             changed = git(ROOT, "diff", "--name-only", f"{rec['old_head']}..{rec['new_head']}").stdout.splitlines()
             mapping = [line.split("\t", 1) for line in (ROOT / "scripts/etc/machine/deploy-paths.tsv").read_text().splitlines()
@@ -315,7 +358,8 @@ def main():
                 rec = next((r for r in records if pathlib.Path(r["path"]).resolve() == ROOT.resolve()), None)
                 if rec and rec["old_head"]:
                     sha = marker.read_text().strip()
-                    diff = git(ROOT, "diff", "--name-only", f"{sha}..origin/deploy/hub", "--", "scripts/etc/argocd/platform-ops")
+                    remote = rec.get("remote") or "origin"
+                    diff = git(ROOT, "diff", "--name-only", f"{sha}..{remote}/deploy/hub", "--", "scripts/etc/argocd/platform-ops")
                     changed = diff.stdout.splitlines()
                     if diff.returncode:
                         state["deploy_unknown"].append("platform-ops")
@@ -351,14 +395,20 @@ def main():
                 if (root_rec and root_rec.get("result") != "fetch_failed"
                         and not root_rec.get("promote_backlog_unknown", False)):
                     upstream_ref = git(ROOT, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}").stdout.strip()
-                    backlog = git(ROOT, "rev-list", "--count", f"origin/deploy/hub..{upstream_ref}")
+                    remote = root_rec.get("remote") or "origin"
+                    backlog = git(ROOT, "rev-list", "--count", f"{remote}/deploy/hub..{upstream_ref}")
                     state["promote_backlog"] = int(backlog.stdout.strip()) if backlog.returncode == 0 else None
-                state["deploy_hub_sha"] = git(ROOT, "rev-parse", "origin/deploy/hub").stdout.strip()
+                root_rec = next((r for r in records if pathlib.Path(r["path"]).resolve() == ROOT.resolve()), None)
+                remote = root_rec.get("remote") or "origin" if root_rec else "origin"
+                state["deploy_hub_sha"] = git(ROOT, "rev-parse", f"{remote}/deploy/hub").stdout.strip()
             except Exception:
                 pass
         STATE.write_text(json.dumps(state, indent=2) + "\n")
         for rec in records:
-            print(f"{pathlib.Path(rec['path']).name}: {rec['branch'] or '-'} {rec['result']} ({rec['behind_before']} behind before, {rec['behind_after']} after)")
+            line = f"{pathlib.Path(rec['path']).name}: {rec['branch'] or '-'} {rec['result']} ({rec['behind_before']} behind before, {rec['behind_after']} after)"
+            if rec["result"] == "reset-to-deploy-hub":
+                line += f" old={rec['old_head']} new={rec['new_head']} backup={rec['backup_ref']}"
+            print(line)
         if is_hub:
             metrics = [f'k3dm_repo_sync_behind_commits{{repo="{repo_label(r["path"])}"}} {r["behind_after"]}' for r in records]
             metrics += [f'k3dm_repo_sync_last_success_timestamp_seconds{{repo="{repo_label(r["path"])}"}} {r["last_success_timestamp_seconds"]}' for r in records]
diff --git a/docs/howto/checkout-auto-sync.md b/docs/howto/checkout-auto-sync.md
index 7ec64911..e909f16f 100644
--- a/docs/howto/checkout-auto-sync.md
+++ b/docs/howto/checkout-auto-sync.md
@@ -1,8 +1,8 @@
 # Checkout auto-sync
 
-`bin/k3dm-repo-sync` runs every five minutes when installed. It fetches and fast-forwards configured checkouts for the machine role. The hub's k3d-manager checkout follows `origin/deploy/hub` so it does not run unpromoted release code.
+`bin/k3dm-repo-sync` runs every five minutes when installed. It fetches and fast-forwards configured checkouts for the machine role. The hub's k3d-manager root checkout follows its configured remote's `deploy/hub` branch so it does not run unpromoted release code. A clean non-fast-forward hub checkout is reset to that branch after a create-only backup ref is recorded. `--check` reports `would-reset-to-deploy-hub` without moving it. Worker checkouts and other repositories are never reset.
 
-The sync never switches branches, resets, rebases, stashes, cleans, deploys, or restarts the webhook. It leaves local commits alone and records a checkout as skipped. If local edits conflict with a fast-forward, it records `blocked`; unrelated edits are kept. Webhook changes set `webhook_restart_pending`; restart it manually with the normal operator procedure.
+The sync never switches branches, rebases, stashes, cleans, deploys, or restarts the webhook. Non-hub checkouts with local commits are left alone: ahead-only is `skipped:ahead`, and ahead plus behind is `skipped:diverged`. A dirty hub checkout or a path collision with a file being added is `skipped:dirty`; unrelated untracked files do not prevent a reset. If local edits conflict with a fast-forward, it records `blocked`; unrelated edits are kept. A missing or empty machine-role file prints an error and exits 1 before syncing or writing state. Webhook changes set `webhook_restart_pending`; restart it manually with the normal operator procedure.
 
 State is written to `~/.local/share/k3d-manager/repo-sync/state.json`. Each repository has its path, branch, result, before/after behind counts, old/new commit and run time. Hub state also reports pending deployment steps and steps it could not determine. `deployed-platform-ops` records the commit last applied by `make platform-ops`.
 
diff --git a/docs/howto/hub-promote.md b/docs/howto/hub-promote.md
index 0fd34c1c..3d45d4b0 100644
--- a/docs/howto/hub-promote.md
+++ b/docs/howto/hub-promote.md
@@ -50,7 +50,9 @@ git cherry-pick -x <commit-sha>
 ```
 
 Cherry-pick the commits onto the release branch, push to `origin`, wait for CI
-checks to pass, and re-run `make hub-promote`.
+checks to pass, and re-run `make hub-promote`. The hub checkout follows the
+promoted `deploy/hub` ref automatically, including when a carried commit has a
+new SHA after cherry-picking.
 
 If GitHub checks are unavailable during an outage or you must intentionally
 discard uncontained commits, `BREAK_GLASS=1` skips the check-run gate and the
@@ -71,6 +73,9 @@ commits that will be added. After promoting A, B and C without intervening
 commits, successive rollbacks move to B and then A. When you want to move
 forward again, promote that commit explicitly with
 `make hub-promote REF=<commit-ish>`.
+The hub checkout follows the rollback on its next repo-sync run. A clean
+non-fast-forward checkout is reset to `deploy/hub` after a create-only backup
+ref is recorded; dirty checkouts are left in place and reported for attention.
 If `deploy/hub` holds commits added after the last promotion (not in the
 promotion stack top), `make hub-rollback` refuses and lists them unless
 overridden with `BREAK_GLASS=1`:
diff --git a/docs/howto/hub-sync.md b/docs/howto/hub-sync.md
index 8905ab06..a1cb8b2b 100644
--- a/docs/howto/hub-sync.md
+++ b/docs/howto/hub-sync.md
@@ -8,12 +8,9 @@ The hub receives changes through three routes, with different delays:
 | Host tools in `bin/` and `scripts/` | M5 checkout auto-sync; `make hub-sync` nudges and reports it | About five minutes |
 | Dashboards and CronJobs | ArgoCD's ApplicationSet branch or `make platform-ops` | Until synced |
 
-The **Hub code behind** tile shows code commits on the hub's checked-out branch
-that have not been pulled. Documentation commits are excluded because Hermes
-can read them from the release ref without moving the checkout. The second
-value says whether the hub is reading the newest release branch. `unknown`
-means the metric check is stale or unavailable.
-The count stays accurate while a newer release exists, at the cost of a second fetch on those cycles.
+The **Hub code behind** tile shows code commits promoted to `deploy/hub` that
+the hub checkout has not pulled. Documentation commits are excluded because
+Hermes can read them from the release ref without moving the checkout.
 
 The hub checkout follows `deploy/hub`, the promoted ref. Use `make hub-sync`
 to nudge the hub's checkout sync and print its current commit and pending
diff --git a/scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml b/scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml
index 0366fa7b..dc3c3044 100644
--- a/scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml
+++ b/scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml
@@ -385,17 +385,16 @@ data:
           "id": 19,
           "type": "stat",
           "title": "Hub code behind",
-          "description": "Commits with code changes on the hub's branch that the hub's checkout has not pulled. Doc text does not need a pull: it appears within about 5 minutes. If a fix is not showing, run make hub-sync in a shell on the hub. The count is for the branch the hub is on.",
+          "description": "Code commits promoted to deploy/hub that the hub's checkout has not pulled yet. repo-sync pulls them within about 5 minutes. Commits not yet promoted are not counted: see make hub-promote-status. Doc text does not need a pull.",
           "gridPos": {"x": 20, "y": 1, "w": 4, "h": 4},
           "datasource": {"type": "prometheus", "uid": "prometheus"},
           "targets": [
-            {"refId": "A", "expr": "k3dm_hub_checkout_code_commits_behind and on() (time() - k3dm_hub_checkout_last_check_timestamp_seconds < 900)", "instant": true, "legendFormat": "{{branch}}"},
-            {"refId": "B", "expr": "k3dm_hub_checkout_on_newest_release and on() (time() - k3dm_hub_checkout_last_check_timestamp_seconds < 900)", "instant": true, "legendFormat": "{{newest_branch}}"}
+            {"refId": "A", "expr": "k3dm_hub_checkout_code_commits_behind and on() (time() - k3dm_hub_checkout_last_check_timestamp_seconds < 900)", "instant": true, "legendFormat": "{{branch}}"}
           ],
           "options": {"graphMode": "none", "colorMode": "value", "reduceOptions": {"calcs": ["lastNotNull"]}},
           "fieldConfig": {
             "defaults": {"noValue": "unknown", "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "orange", "value": 1}]}},
-            "overrides": [{"matcher": {"id": "byFrameRefID", "options": "B"}, "properties": [{"id": "mappings", "value": [{"type": "value", "options": {"1": {"text": "current release", "color": "green"}, "0": {"text": "older release", "color": "orange"}}}]}]}]
+            "overrides": []
           }
         },
         {
diff --git a/scripts/tests/bin/hub_promote.bats b/scripts/tests/bin/hub_promote.bats
index 168d56b5..236fb441 100644
--- a/scripts/tests/bin/hub_promote.bats
+++ b/scripts/tests/bin/hub_promote.bats
@@ -56,9 +56,22 @@ EOF
 # Git operations are constrained to the named scratch clone or its bare origin.
 allowed=0
 for arg in "$@"; do
-  [[ "$arg" == "$SCRATCH_REPO" || "$arg" == "$TEST_ORIGIN" || "$arg" == "--git-dir=$TEST_ORIGIN" ]] && allowed=1
+  [[ "$arg" == "$SCRATCH_REPO" || "$arg" == "$MOVE_SOURCE_REPO" || "$arg" == "$TEST_ORIGIN" || "$arg" == "--git-dir=$TEST_ORIGIN" ]] && allowed=1
 done
 [[ "$allowed" == 1 ]] || { echo "git stub refused a non-fixture target: $*" >&2; exit 97; }
+if [[ "${CHERRY_FAIL:-0}" == 1 && " $* " == *" cherry "* ]]; then
+  echo "stubbed git cherry failure" >&2
+  exit 1
+fi
+if [[ -n "${CAT_FILE_FAIL_SHA:-}" && "$*" == *"cat-file -e $CAT_FILE_FAIL_SHA^"* ]]; then
+  echo "stubbed unavailable commit $CAT_FILE_FAIL_SHA" >&2
+  exit 1
+fi
+if [[ "${MOVE_ON_LS_REMOTE:-0}" == 1 && ! -e "$MOVE_ONCE_FILE" && "$*" == *"ls-remote origin refs/heads/deploy/hub"* ]]; then
+  : > "$MOVE_ONCE_FILE"
+  "$REAL_GIT_PATH" -C "$MOVE_SOURCE_REPO" push "$TEST_ORIGIN" "$MOVE_HUB_SHA:refs/heads/race-promoter" >/dev/null 2>&1
+  "$REAL_GIT_PATH" --git-dir="$TEST_ORIGIN" update-ref refs/heads/deploy/hub "$MOVE_HUB_SHA"
+fi
 exec "$REAL_GIT_PATH" "$@"
 EOF
   cat > "$BATS_TEST_TMPDIR/stubs/gh" <<'EOF'
@@ -245,6 +258,59 @@ rollback: yes"
   printf '5\n' > "$DATE_COUNTER"
 }
 
+@test "M3 N3: promoter commit arriving between fetch and ls-remote is preserved" {
+  _prepare_promotion_history
+  git -C "$WORK" fetch -q origin
+  git -C "$WORK" branch -f k3d-manager-v1.43.15 "$D_SHA"
+  git -C "$WORK" checkout -q feature/test
+  MOVE_SOURCE_REPO="$BATS_TEST_TMPDIR/race-source"
+  export MOVE_SOURCE_REPO
+  git clone -q --branch k3d-manager-v1.43.15 "$ORIGIN" "$MOVE_SOURCE_REPO"
+  git -C "$MOVE_SOURCE_REPO" config user.name 'Race promoter'
+  git -C "$MOVE_SOURCE_REPO" config user.email 'race-promoter@example.invalid'
+  echo promoter > "$MOVE_SOURCE_REPO/promoter-arrival.txt"
+  git -C "$MOVE_SOURCE_REPO" add promoter-arrival.txt
+  git -C "$MOVE_SOURCE_REPO" commit -qm "promoter arrival"
+  MOVE_HUB_SHA="$(git -C "$MOVE_SOURCE_REPO" rev-parse HEAD)"
+  export MOVE_HUB_SHA MOVE_SOURCE_REPO MOVE_ONCE_FILE="$BATS_TEST_TMPDIR/move-once" MOVE_ON_LS_REMOTE=1
+  _run_promoter_tty promote success promote k3d-manager-v1.43.15 0
+  [ "$status" -ne 0 ]
+  [[ "$output" == *"deploy/hub contains 1 commit"* ]]
+  [[ "$output" == *"promoter arrival"* ]]
+  [[ "$output" != *"no commits between refs"* ]]
+  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$MOVE_HUB_SHA" ]
+  [ -z "$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*')" ]
+}
+
+@test "M3: promote fails closed on git cherry error and succeeds when restored" {
+  _make_candidate
+  old="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
+  export CHERRY_FAIL=1
+  _run_promoter_tty promote success promote k3d-manager-v1.43.15 0
+  [ "$status" -ne 0 ]
+  [[ "$output" == *"cannot check deploy/hub containment"* ]]
+  [[ "$output" == *"stubbed git cherry failure"* ]]
+  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$old" ]
+  export CHERRY_FAIL=0
+  _run_promoter_tty promote success promote k3d-manager-v1.43.15 0
+  [ "$status" -eq 0 ]
+  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" != "$old" ]
+}
+
+@test "M3: promote names an unavailable deploy/hub SHA and succeeds when available" {
+  _make_candidate
+  old="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
+  export CAT_FILE_FAIL_SHA="$old"
+  _run_promoter_tty promote success promote k3d-manager-v1.43.15 0
+  [ "$status" -ne 0 ]
+  [[ "$output" == *"deploy/hub commit $old is not available locally; refusing to promote"* ]]
+  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$old" ]
+  export CAT_FILE_FAIL_SHA=
+  _run_promoter_tty promote success promote k3d-manager-v1.43.15 0
+  [ "$status" -eq 0 ]
+  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" != "$old" ]
+}
+
 @test "N3: appsets-reapply pins deploy/hub despite BRANCH and checked-out branch" {
   run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" CALLS="$CALLS" make -C "$WORK" --no-print-directory appsets-reapply BRANCH=feature/test APPSETS_STAGE=hub
   [ "$status" -eq 0 ]
@@ -633,13 +699,51 @@ rollback: yes"
 }
 
 @test "M5: status reports deploy/hub, tags and ahead count without changing refs" {
-  before="$(git -C "$WORK" show-ref | sort)"
+  before_branches="$(git -C "$WORK" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags | sort)"
+  before_head="$(git -C "$WORK" rev-parse HEAD)"
+  before_index="$(git -C "$WORK" write-tree)"
+  before_worktree="$(git -C "$WORK" status --porcelain)"
   sha="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
   run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" RELEASE_BRANCH=k3d-manager-v1.43.15 PATH="$PATH" "$WORK/bin/k3dm-hub-promote" status < /dev/null
   [ "$status" -eq 0 ]
   [[ "$output" == *"deploy/hub: $sha"* ]]
   [[ "$output" == *"k3d-manager-v1.43.15 ahead of deploy/hub: 0"* ]]
-  [ "$(git -C "$WORK" show-ref | sort)" = "$before" ]
+  [ "$(git -C "$WORK" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags | sort)" = "$before_branches" ]
+  [ "$(git -C "$WORK" rev-parse HEAD)" = "$before_head" ]
+  [ "$(git -C "$WORK" write-tree)" = "$before_index" ]
+  [ "$(git -C "$WORK" status --porcelain)" = "$before_worktree" ]
+}
+
+@test "G regression: non-TTY promoter test completes when suite stdin is a terminal" {
+  clean_path="${PATH#"$BATS_TEST_TMPDIR/stubs:"}"
+  run env -u SCRATCH_REPO -u TEST_ORIGIN -u REAL_GIT_PATH -u CALLS PATH="$clean_path" \
+    perl -e 'alarm 60; exec @ARGV' script -q /dev/null bats -f 'N2: non-TTY' "$BATS_TEST_FILENAME"
+  [ "$status" -eq 0 ]
+}
+
+@test "M5: status counts origin and reports stale local release position" {
+  git -C "$WORK" checkout -q k3d-manager-v1.43.15
+  for index in 1 2 3 4 5; do
+    printf 'release %s\n' "$index" >> "$WORK/release.txt"
+    git -C "$WORK" add release.txt
+    git -C "$WORK" commit -q -m "release $index"
+    if [ "$index" -eq 2 ]; then second="$(git -C "$WORK" rev-parse HEAD)"; fi
+  done
+  git -C "$WORK" push -q origin HEAD:refs/heads/k3d-manager-v1.43.15
+  git -C "$WORK" fetch -q origin
+  git -C "$WORK" reset --hard -q "$second"
+  before_branches="$(git -C "$WORK" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags | sort)"
+  before_head="$(git -C "$WORK" rev-parse HEAD)"
+  before_index="$(git -C "$WORK" write-tree)"
+  before_worktree="$(git -C "$WORK" status --porcelain)"
+  run env HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" RELEASE_BRANCH=k3d-manager-v1.43.15 PATH="$PATH" "$WORK/bin/k3dm-hub-promote" status < /dev/null
+  [ "$status" -eq 0 ]
+  [[ "$output" == *"k3d-manager-v1.43.15 ahead of deploy/hub: 5"* ]]
+  [[ "$output" == *"local k3d-manager-v1.43.15 is 3 behind / 0 ahead of origin"* ]]
+  [ "$(git -C "$WORK" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags | sort)" = "$before_branches" ]
+  [ "$(git -C "$WORK" rev-parse HEAD)" = "$before_head" ]
+  [ "$(git -C "$WORK" write-tree)" = "$before_index" ]
+  [ "$(git -C "$WORK" status --porcelain)" = "$before_worktree" ]
 }
 
 @test "Makefile hub-promote passes REF and break-glass to the command" {
diff --git a/scripts/tests/bin/repo_sync.bats b/scripts/tests/bin/repo_sync.bats
index 2ec17d35..c377c88f 100644
--- a/scripts/tests/bin/repo_sync.bats
+++ b/scripts/tests/bin/repo_sync.bats
@@ -10,7 +10,9 @@ setup() {
   export HOME="$SCRATCH/home" XDG_CONFIG_HOME="$SCRATCH/home/.config"
   export K3DM_REPO_SYNC_STATE_DIR="$SCRATCH/state" K3DM_REPO_SYNC_TIMEOUT=3
   export K3DM_REPO_SYNC_REPOS="$SCRATCH/clone"
-  export REAL_GIT="$(command -v git)" REAL_MAKE="$(command -v make)"
+  REAL_GIT="$(command -v git)"
+  REAL_MAKE="$(command -v make)"
+  export REAL_GIT REAL_MAKE
   git init --bare "$SCRATCH/upstream.git" >/dev/null
   git clone "$SCRATCH/upstream.git" "$SCRATCH/seed" >/dev/null 2>&1
   git -C "$SCRATCH/seed" config user.email test@example.invalid
@@ -183,6 +185,16 @@ run_sync() {
   [ "$(git -C "$SCRATCH/clone" rev-parse HEAD)" = "$before_head" ]
   [ "$(git -C "$SCRATCH/clone" write-tree)" = "$before_index" ]
   [ "$(git -C "$SCRATCH/clone" status --porcelain)" = "$before_status" ]
+  grep -q 'skipped:diverged' "$SCRATCH/state/state.json"
+  grep -q '"behind_before": 1' "$SCRATCH/state/state.json"
+  grep -q '"behind_after": 1' "$SCRATCH/state/state.json"
+}
+
+@test "ahead-only checkout reports skipped ahead" {
+  echo ahead > "$SCRATCH/clone/ahead"
+  git -C "$SCRATCH/clone" add ahead && git -C "$SCRATCH/clone" commit -m ahead >/dev/null
+  run_sync
+  [ "$status" -eq 0 ]
   grep -q 'skipped:ahead' "$SCRATCH/state/state.json"
 }
 
@@ -359,11 +371,125 @@ run_sync() {
   [ "$status" -eq 0 ]
   [ "$(git -C "$HUB_ROOT" rev-parse HEAD)" = "$first" ]
   [ "$(git -C "$HUB_ROOT" rev-parse HEAD)" != "$second" ]
+  [ -z "$(git -C "$HUB_ROOT" for-each-ref --format='%(refname)' refs/k3dm/repo-sync-backup/)" ]
   printf 'worker\n' > "$XDG_CONFIG_HOME/k3d-manager/machine-role"
   export K3DM_REPO_SYNC_REPOS="$SCRATCH/clone"
   run_sync "$SCRATCH/clone"
   [ "$status" -eq 0 ]
   [ "$(git -C "$SCRATCH/clone" rev-parse HEAD)" = "$second" ]
+  echo worker-local > "$SCRATCH/clone/worker-local"
+  git -C "$SCRATCH/clone" add worker-local && git -C "$SCRATCH/clone" commit -m worker-local >/dev/null
+  worker_head="$(git -C "$SCRATCH/clone" rev-parse HEAD)"
+  echo upstream-next >> "$SCRATCH/seed/file"
+  git -C "$SCRATCH/seed" commit -am upstream-next >/dev/null
+  git -C "$SCRATCH/seed" push origin HEAD:main >/dev/null 2>&1
+  run_sync "$SCRATCH/clone"
+  [ "$status" -eq 0 ]
+  grep -q 'skipped:diverged' "$SCRATCH/state/state.json"
+  [ "$(git -C "$SCRATCH/clone" rev-parse HEAD)" = "$worker_head" ]
+}
+
+@test "dirty non-fast-forward hub checkout is skipped without a backup ref" {
+  install_stubs
+  prepare_hub_checkout
+  echo local-edit >> "$HUB_ROOT/file"
+  before_head="$(git -C "$HUB_ROOT" rev-parse HEAD)"
+  before_file="$(shasum "$HUB_ROOT/file" | awk '{print $1}')"
+  echo promoted >> "$SCRATCH/seed/file"
+  git -C "$SCRATCH/seed" commit -am promoted >/dev/null
+  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
+  git -C "$HUB_ROOT" branch side "$before_head"
+  echo local-commit > "$HUB_ROOT/local-commit"
+  git -C "$HUB_ROOT" add local-commit && git -C "$HUB_ROOT" commit -m local >/dev/null
+  before_head="$(git -C "$HUB_ROOT" rev-parse HEAD)"
+  run_sync "$HUB_ROOT"
+  [ "$status" -eq 0 ]
+  grep -q 'skipped:dirty' "$SCRATCH/state/state.json"
+  [ "$(git -C "$HUB_ROOT" rev-parse HEAD)" = "$before_head" ]
+  [ "$(shasum "$HUB_ROOT/file" | awk '{print $1}')" = "$before_file" ]
+  [ -z "$(git -C "$HUB_ROOT" for-each-ref --format='%(refname)' refs/k3dm/repo-sync-backup/)" ]
+}
+
+@test "hub role never resets a non-root repository with diverged commits" {
+  install_stubs
+  prepare_hub_checkout
+  printf 'hub\n' > "$XDG_CONFIG_HOME/k3d-manager/machine-role"
+  export K3DM_REPO_SYNC_REPOS="$HUB_ROOT:$SCRATCH/clone" PUSHGATEWAY_URL=http://127.0.0.1:9
+  echo local > "$SCRATCH/clone/local-only"
+  git -C "$SCRATCH/clone" add local-only && git -C "$SCRATCH/clone" commit -m local-only >/dev/null
+  before_head="$(git -C "$SCRATCH/clone" rev-parse HEAD)"
+  echo upstream > "$SCRATCH/seed/upstream-only"
+  git -C "$SCRATCH/seed" add upstream-only && git -C "$SCRATCH/seed" commit -m upstream-only >/dev/null
+  git -C "$SCRATCH/seed" push origin HEAD:main >/dev/null 2>&1
+  run_sync "$HUB_ROOT"
+  [ "$status" -eq 0 ]
+  [ "$(git -C "$SCRATCH/clone" rev-parse HEAD)" = "$before_head" ]
+  grep -q 'skipped:diverged' "$SCRATCH/state/state.json"
+  [ -z "$(git -C "$SCRATCH/clone" for-each-ref --format='%(refname)' refs/k3dm/repo-sync-backup/)" ]
+}
+
+@test "untracked file at a path deploy/hub adds is protected from reset" {
+  install_stubs
+  prepare_hub_checkout
+  git -C "$HUB_ROOT" branch local-branch
+  git -C "$SCRATCH/seed" checkout -b add-path >/dev/null 2>&1
+  echo promoted > "$SCRATCH/seed/will-be-added"
+  git -C "$SCRATCH/seed" add will-be-added && git -C "$SCRATCH/seed" commit -m add-path >/dev/null
+  promoted="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
+  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
+  git -C "$HUB_ROOT" checkout -qb local-divergence
+  echo local > "$HUB_ROOT/local-change"
+  git -C "$HUB_ROOT" add local-change && git -C "$HUB_ROOT" commit -m local-change >/dev/null
+  printf 'keep me\n' > "$HUB_ROOT/will-be-added"
+  before_head="$(git -C "$HUB_ROOT" rev-parse HEAD)"
+  before_file="$(shasum "$HUB_ROOT/will-be-added" | awk '{print $1}')"
+  run_sync "$HUB_ROOT"
+  [ "$status" -eq 0 ]
+  grep -q 'skipped:dirty' "$SCRATCH/state/state.json"
+  [ "$(git -C "$HUB_ROOT" rev-parse HEAD)" = "$before_head" ]
+  [ "$(shasum "$HUB_ROOT/will-be-added" | awk '{print $1}')" = "$before_file" ]
+  [ -z "$(git -C "$HUB_ROOT" for-each-ref --format='%(refname)' refs/k3dm/repo-sync-backup/)" ]
+  [ "$promoted" != "$before_head" ]
+}
+
+@test "reset to a rollback ref counts as success and marks webhook restart pending" {
+  install_stubs
+  prepare_hub_checkout
+  export PUSHGATEWAY_URL=http://127.0.0.1:9 APPCHECK_MODE=clean
+  mkdir -p "$SCRATCH/seed/scripts/lib/webhook"
+  echo first > "$SCRATCH/seed/scripts/lib/webhook/change.py"
+  git -C "$SCRATCH/seed" add scripts/lib/webhook/change.py
+  git -C "$SCRATCH/seed" commit -m webhook-first >/dev/null
+  rollback_sha="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
+  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
+  run_sync "$HUB_ROOT"
+  [ "$status" -eq 0 ]
+  python3 - "$SCRATCH/state/state.json" <<'PY'
+import json, sys
+p=sys.argv[1]; d=json.load(open(p)); d["webhook_restart_pending"]=False; d["deploy_pending"]=[]
+json.dump(d, open(p,"w"))
+PY
+  echo second >> "$SCRATCH/seed/scripts/lib/webhook/change.py"
+  git -C "$SCRATCH/seed" commit -am webhook-second >/dev/null
+  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
+  run_sync "$HUB_ROOT"
+  [ "$status" -eq 0 ]
+  python3 - "$SCRATCH/state/state.json" <<'PY'
+import json, sys
+p=sys.argv[1]; d=json.load(open(p)); d["webhook_restart_pending"]=False; d["deploy_pending"]=[]
+json.dump(d, open(p,"w"))
+PY
+  git --git-dir="$SCRATCH/upstream.git" update-ref refs/heads/deploy/hub "$rollback_sha"
+  run_sync "$HUB_ROOT"
+  [ "$status" -eq 0 ]
+  python3 - "$SCRATCH/state/state.json" <<'PY'
+import json, sys
+d=json.load(open(sys.argv[1])); r=next(x for x in d["repositories"] if x["path"].endswith("hub-checkout"))
+assert r["result"] == "reset-to-deploy-hub"
+assert r["last_success_timestamp_seconds"] == r["run_time"]
+assert d["webhook_restart_pending"] is True
+assert any(x["step"] == "webhook-restart" for x in d["deploy_pending"])
+PY
 }
 
 @test "hub-sync prints the remote line and warns but succeeds on ssh failure" {
@@ -413,27 +539,47 @@ run_sync() {
   fi
 }
 
-@test "hub non-fast-forward deploy ref leaves checkout unchanged and never promotes or pushes" {
+@test "hub clean non-fast-forward checkout backs up and follows deploy ref" {
   install_stubs
   prepare_hub_checkout
   echo local > "$HUB_ROOT/local-only"
   git -C "$HUB_ROOT" add local-only && git -C "$HUB_ROOT" commit -m local >/dev/null
   before_head="$(git -C "$HUB_ROOT" rev-parse HEAD)"
+  git -C "$HUB_ROOT" remote rename origin upstream >/dev/null
   before_index="$(git -C "$HUB_ROOT" write-tree)"
   before_status="$(git -C "$HUB_ROOT" status --porcelain)"
   : > "$GIT_LOG"
   export PUSHGATEWAY_URL=http://127.0.0.1:9
-  run_sync "$HUB_ROOT"
+  run "$HUB_ROOT/bin/k3dm-repo-sync" --check
   [ "$status" -eq 0 ]
+  [[ "$output" == *"would-reset-to-deploy-hub"* ]]
   [ "$(git -C "$HUB_ROOT" rev-parse HEAD)" = "$before_head" ]
-  [ "$(git -C "$HUB_ROOT" write-tree)" = "$before_index" ]
-  [ "$(git -C "$HUB_ROOT" status --porcelain)" = "$before_status" ]
-  grep -q 'skipped:not-ff-to-deploy-hub' "$SCRATCH/state/state.json"
+  run_sync "$HUB_ROOT"
+  [ "$status" -eq 0 ]
+  target="$(git -C "$HUB_ROOT" rev-parse upstream/deploy/hub)"
+  [ "$(git -C "$HUB_ROOT" rev-parse HEAD)" = "$target" ]
+  grep -q '"remote": "upstream"' "$SCRATCH/state/state.json"
+  grep -q '"result": "reset-to-deploy-hub"' "$SCRATCH/state/state.json"
+  grep -q '"backup_ref": "refs/k3dm/repo-sync-backup/' "$SCRATCH/state/state.json"
+  [ "$(git -C "$HUB_ROOT" rev-parse "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["repositories"][0]["backup_ref"])' "$SCRATCH/state/state.json")")" = "$before_head" ]
   if grep -Eq '(^|[[:space:]])(push|hub-promote|hub-rollback)([[:space:]]|$)' "$GIT_LOG" "$MAKE_LOG"; then
     return 1
   fi
 }
 
+@test "missing or empty machine role fails before state or repository access" {
+  rm "$XDG_CONFIG_HOME/k3d-manager/machine-role"
+  run "$TEST_SYNC_BIN"
+  [ "$status" -eq 1 ]
+  [[ "$output" == *"machine-role file missing or empty"* ]]
+  [ ! -e "$SCRATCH/state/state.json" ]
+  printf '\n' > "$XDG_CONFIG_HOME/k3d-manager/machine-role"
+  run "$TEST_SYNC_BIN" --check
+  [ "$status" -eq 1 ]
+  [[ "$output" == *"machine-role file missing or empty"* ]]
+  [ ! -e "$SCRATCH/state/state.json" ]
+}
+
 @test "dead repo-sync lock is recovered and a live lock is preserved" {
   mkdir -p "$SCRATCH/state/lock"
   printf '2147483647\n' > "$SCRATCH/state/lock/pid"
diff --git a/scripts/tests/bin/test_dashboard_queries.py b/scripts/tests/bin/test_dashboard_queries.py
index a5875021..ac7b0096 100644
--- a/scripts/tests/bin/test_dashboard_queries.py
+++ b/scripts/tests/bin/test_dashboard_queries.py
@@ -160,7 +160,7 @@ def fixture_metrics(tmp_path):
     # producer output is appended; the patched HTTP client never sends it.
     assert hermes.ROOT == repo
     with patch.object(hermes.urllib.request, "urlopen", side_effect=capture_push):
-        hermes._push_checkout_lag("HEAD", "k3d-manager-v1.43.14", "k3d-manager-v1.43.14")
+        hermes._push_checkout_lag("HEAD")
     metric_text += "".join(captured)
     return metric_text, set(texts)
 
diff --git a/scripts/tests/bin/test_hermes_checkout_lag.py b/scripts/tests/bin/test_hermes_checkout_lag.py
index 38221295..e1215967 100644
--- a/scripts/tests/bin/test_hermes_checkout_lag.py
+++ b/scripts/tests/bin/test_hermes_checkout_lag.py
@@ -35,6 +35,7 @@ def origin_and_clone(tmp_path, monkeypatch):
     git(seed, "branch", "-M", "k3d-manager-v1.43.14")
     git(seed, "remote", "add", "origin", str(origin))
     git(seed, "push", "-u", "origin", "HEAD")
+    git(seed, "push", "origin", "HEAD:refs/heads/deploy/hub")
     subprocess.run(["git", f"--git-dir={origin}", "symbolic-ref", "HEAD",
                     "refs/heads/k3d-manager-v1.43.14"], check=True)
     git(seed, "clone", str(origin), str(clone))
@@ -73,7 +74,7 @@ def refresh_with_capture(monkeypatch, clone, fail_older_fetch=False):
         if command[0] == "git" and len(command) > 1 and command[1] == "fetch":
             fetches.append((command, kwargs))
             if (fail_older_fetch and
-                    command[-1] == "+refs/heads/k3d-manager-v1.43.14:refs/remotes/origin/k3d-manager-v1.43.14"):
+                    command[-1] == "+refs/heads/deploy/hub:refs/remotes/origin/deploy/hub"):
                 return type("R", (), {"returncode": 1, "stdout": "", "stderr": "fetch failed"})()
             return real_run(command, **kwargs)
         if command[0] == "git":
@@ -101,16 +102,20 @@ def refresh_with_capture(monkeypatch, clone, fail_older_fetch=False):
 
 def test_refresh_lag_count_uses_fetched_older_upstream_when_newer_release_exists(
         older_branch_behind, monkeypatch):
-    _origin, _seed, clone = older_branch_behind
-    _state, _result, fetches, lag_payloads, index_metrics = refresh_with_capture(monkeypatch, clone)
+    _origin, seed, clone = older_branch_behind
+    state, _result, fetches, lag_payloads, index_metrics = refresh_with_capture(monkeypatch, clone)
     assert len(lag_payloads) == 1
-    assert 'code_commits_behind{branch="k3d-manager-v1.43.14"} 2' in lag_payloads[0]
+    assert 'code_commits_behind{branch="deploy/hub"} 0' in lag_payloads[0]
     assert len(fetches) == 2
     assert fetches[0][0][-1] == "+refs/heads/k3d-manager-v1.43.100:refs/remotes/origin/k3d-manager-v1.43.100"
-    assert fetches[1][0][-1] == "+refs/heads/k3d-manager-v1.43.14:refs/remotes/origin/k3d-manager-v1.43.14"
+    assert fetches[1][0][-1] == "+refs/heads/deploy/hub:refs/remotes/origin/deploy/hub"
     assert fetches[0][1]["timeout"] == fetches[1][1]["timeout"] == 60
     assert fetches[0][1]["env"] is fetches[1][1]["env"]
     assert index_metrics[0]["result"] == "success"
+    git(seed, "push", "origin", "HEAD:refs/heads/deploy/hub")
+    next_state, _result, _fetches, next_payloads, _metrics = refresh_with_capture(monkeypatch, clone)
+    assert 'code_commits_behind{branch="deploy/hub"} 2' in next_payloads[0]
+    assert next_state["index_ref"] == state["index_ref"] == "origin/k3d-manager-v1.43.100"
 
 
 def test_failed_older_upstream_fetch_skips_lag_without_changing_index_result(
@@ -129,9 +134,10 @@ def test_refresh_on_newest_branch_fetches_once(older_branch_behind, monkeypatch)
         "+refs/heads/k3d-manager-v1.43.100:refs/remotes/origin/k3d-manager-v1.43.100")
     git(clone, "switch", "--track", "-c", "k3d-manager-v1.43.100", "origin/k3d-manager-v1.43.100")
     _state, _result, fetches, lag_payloads, index_metrics = refresh_with_capture(monkeypatch, clone)
-    assert len(fetches) == 1
+    assert len(fetches) == 2
     assert fetches[0][0][-1] == "+refs/heads/k3d-manager-v1.43.100:refs/remotes/origin/k3d-manager-v1.43.100"
-    assert 'code_commits_behind{branch="k3d-manager-v1.43.100"} 0' in lag_payloads[0]
+    assert fetches[1][0][-1] == "+refs/heads/deploy/hub:refs/remotes/origin/deploy/hub"
+    assert 'code_commits_behind{branch="deploy/hub"} 0' in lag_payloads[0]
     assert index_metrics[0]["result"] == "success"
 
 
@@ -141,8 +147,8 @@ def test_lag_publishes_code_count_excluding_docs(origin_and_clone, monkeypatch):
     git(seed, "add", "docs/new.md"); git(seed, "commit", "-m", "doc")
     (seed / "code.txt").write_text("code\n")
     git(seed, "add", "code.txt"); git(seed, "commit", "-m", "code")
-    git(seed, "push", "origin", "HEAD")
-    git(clone, "fetch", "origin", "+refs/heads/k3d-manager-v1.43.14:refs/remotes/origin/k3d-manager-v1.43.14")
+    git(seed, "push", "origin", "HEAD:refs/heads/deploy/hub")
+    git(clone, "fetch", "origin", "+refs/heads/deploy/hub:refs/remotes/origin/deploy/hub")
     captured = []
 
     class Response:
@@ -155,10 +161,10 @@ def test_lag_publishes_code_count_excluding_docs(origin_and_clone, monkeypatch):
         return Response()
 
     monkeypatch.setattr(hermes.urllib.request, "urlopen", capture)
-    hermes._push_checkout_lag("origin/k3d-manager-v1.43.14", "k3d-manager-v1.43.14", "k3d-manager-v1.43.14")
-    assert 'code_commits_behind{branch="k3d-manager-v1.43.14"} 1' in captured[0]
+    hermes._push_checkout_lag("origin/deploy/hub")
+    assert 'code_commits_behind{branch="deploy/hub"} 1' in captured[0]
     assert "k3dm_hub_checkout_last_check_timestamp_seconds" in captured[0]
-    assert "k3dm_hub_checkout_on_newest_release{newest_branch=\"k3d-manager-v1.43.14\"} 1" in captured[0]
+    assert "k3dm_hub_checkout_on_newest_release" not in captured[0]
 
 
 def test_newest_release_uses_numeric_version_and_never_downgrades(origin_and_clone, monkeypatch):
@@ -182,8 +188,8 @@ def test_unsafe_branch_and_git_or_gateway_failures_publish_nothing(origin_and_cl
     published = []
     monkeypatch.setattr(hermes.subprocess, "run", lambda *_a, **_k: type("R", (), {"returncode": 1, "stdout": ""})())
     monkeypatch.setattr(hermes.urllib.request, "urlopen", lambda *_a, **_k: published.append(1))
-    hermes._push_checkout_lag("origin/x", 'x"bad', "x")
-    hermes._push_checkout_lag("origin/x", "x", "x")
+    hermes._push_checkout_lag('x"bad')
+    hermes._push_checkout_lag("origin/x")
     assert published == []
 
 
@@ -192,8 +198,7 @@ def test_unreachable_gateway_does_not_escape(origin_and_clone, monkeypatch):
     monkeypatch.setattr(hermes.subprocess, "run", lambda *_a, **_k:
                         type("R", (), {"returncode": 0, "stdout": "0\n"})())
     monkeypatch.setattr(hermes.urllib.request, "urlopen", lambda *_a, **_k: (_ for _ in ()).throw(OSError("offline")))
-    assert hermes._push_checkout_lag("origin/k3d-manager-v1.43.14", "k3d-manager-v1.43.14",
-                                     "k3d-manager-v1.43.14") is None
+    assert hermes._push_checkout_lag("origin/deploy/hub") is None
 
 
 def test_paused_refresh_still_publishes_checkout_lag(origin_and_clone, monkeypatch):
@@ -209,7 +214,7 @@ def test_paused_refresh_still_publishes_checkout_lag(origin_and_clone, monkeypat
     state = {"index_paused_until": 200}
     assert hermes._refresh_index(state, now=100) is None
     assert state["index_ref"] == "origin/k3d-manager-v1.43.14"
-    assert lag == [("origin/k3d-manager-v1.43.14", "k3d-manager-v1.43.14", "k3d-manager-v1.43.14")]
+    assert lag == [("origin/deploy/hub",)]
 
 
 def test_refresh_fetches_newest_release_docs_without_moving_head(origin_and_clone, monkeypatch):
@@ -263,5 +268,9 @@ def test_explicit_index_ref_wins_without_remote_release_lookup(origin_and_clone,
     hermes._refresh_index(state, now=1000)
     assert state["index_ref"] == "origin/k3d-manager-v1.43.14"
     fetch_calls = [command for command in calls if command[:2] == ["git", "fetch"]]
-    assert fetch_calls == [["git", "fetch", "--quiet", "origin", "k3d-manager-v1.43.14"]]
+    assert fetch_calls == [
+        ["git", "fetch", "--quiet", "origin", "k3d-manager-v1.43.14"],
+        ["git", "fetch", "--quiet", "origin",
+         "+refs/heads/deploy/hub:refs/remotes/origin/deploy/hub"],
+    ]
     assert not any(command[:3] == ["git", "ls-remote", "--heads"] for command in calls)
diff --git a/scripts/tests/plugins/grafana_dashboard_bugs.bats b/scripts/tests/plugins/grafana_dashboard_bugs.bats
index a90abe8c..253a6950 100644
--- a/scripts/tests/plugins/grafana_dashboard_bugs.bats
+++ b/scripts/tests/plugins/grafana_dashboard_bugs.bats
@@ -31,13 +31,13 @@ assert hub["fieldConfig"]["defaults"]["thresholds"]["steps"] == [
 targets={t["refId"]:t for t in hub["targets"]}
 assert targets["A"]["expr"] == "k3dm_hub_checkout_code_commits_behind and on() (time() - k3dm_hub_checkout_last_check_timestamp_seconds < 900)"
 assert targets["A"]["legendFormat"] == "{{branch}}"
-assert targets["B"]["expr"] == "k3dm_hub_checkout_on_newest_release and on() (time() - k3dm_hub_checkout_last_check_timestamp_seconds < 900)"
-assert targets["B"]["legendFormat"] == "{{newest_branch}}"
-override=hub["fieldConfig"]["overrides"][0]
-assert override["matcher"] == {"id":"byFrameRefID","options":"B"}
-mapping=override["properties"][0]["value"][0]["options"]
-assert mapping["1"] == {"text":"current release","color":"green"}
-assert mapping["0"] == {"text":"older release","color":"orange"}
+assert set(targets) == {"A"}
+assert hub["fieldConfig"]["overrides"] == []
+assert "older release" not in hub["description"].lower()
+assert "BRANCH=" not in hub["description"]
+assert "deploy/hub" in hub["description"]
+assert "older release" not in json.dumps(hub).lower()
+assert "BRANCH=" not in json.dumps(hub)
 occupied=set()
 for p in d["panels"]:
     pos=p["gridPos"]
```
