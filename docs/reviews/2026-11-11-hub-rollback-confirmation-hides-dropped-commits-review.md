# Review brief: hub-rollback returns to the state before the last promote (Luna) — cross-vendor diff review

**Role:** review child of `2026-11-11-hub-rollback-confirmation-hides-dropped-commits`.
**Intent approved:** operator, 2026-11-11
**Spec under review:** `docs/bugs/2026-11-11-hub-rollback-confirmation-hides-dropped-commits.md` (read it in full first).

## Files

Read-only: review these, change none of them.
- `Makefile
bin/k3dm-hub-promote
docs/howto/hub-promote.md
scripts/tests/bin/hub_promote.bats`

## Task

Review the worker's diff below against the spec: its Fix direction, Contract readers and Acceptance block. Report findings only. Do not edit, commit or keep any file. You may `git apply` the diff in your own worktree to run the touched suites and try mutations, but leave the worktree clean at exit (`git checkout -- . && git clean -fd`).

For each finding give: severity (blocker / should-fix / nit); file:line in the diff; a concrete input or state that breaks it; the spec line (Fix item or M/N id) it violates.

Check in particular:
1. M1/N1: promote A, push X to deploy/hub, promote B (contains X), rollback lands on A+X. Is there a test for exactly that, and does it fail on the pre-fix code?
2. N2 (bootstrap-only refuses without moving or tagging) and N3 (confirmation never says "no commits between refs" when commits leave): each red on pre-fix code?
3. Stack replay: no-op promotes (old == new), duplicate consecutive promotes, rollback tags (new must equal the popped entry's old), rollback then promote then rollback. Any order of tags that now replays wrongly or dies?
4. The uncontained-commit guard and BREAK_GLASS still behave as before.
5. The confirmation's "will be removed" / "will be added" lists use the right ranges when the target is not an ancestor of deploy/hub.

End with a one-line verdict: `land`, `land after fixes`, or `rework`. Under 400 words.

## Worker diff (uncommitted, against `k3d-manager-v1.43.15` at the worker's base `ad170251`)

```diff
diff --git a/Makefile b/Makefile
index 3a6e5cc8..a584c7af 100644
--- a/Makefile
+++ b/Makefile
@@ -1780,7 +1780,7 @@ help:
 	@echo "    make appsets-check         Report Applications not reading deploy/hub values (read-only)"
 	@echo "    make hub-promote REF=...   Promote a checked origin commit to deploy/hub (BREAK_GLASS=1 optional)"
 	@echo "    make promote REF=...       hub-promote, then appsets-check and platform-ops (stops at first failure)"
-	@echo "    make hub-rollback          Roll back deploy/hub to the previous recorded promotion"
+	@echo "    make hub-rollback          Return deploy/hub to the state before the last promotion"
 	@echo "    make hub-promote-status    Show deploy/hub SHA, recent tags, and release ahead count"
 	@echo "    make ssm                   Ensure session-manager-plugin is installed"
 	@echo "    make provision             Provision ACG stack via SSM (depends on ssm)"
diff --git a/bin/k3dm-hub-promote b/bin/k3dm-hub-promote
index 6e756904..0c21de29 100755
--- a/bin/k3dm-hub-promote
+++ b/bin/k3dm-hub-promote
@@ -83,8 +83,16 @@ show_and_confirm() {
   if [[ "$old" =~ ^0+$ ]]; then
     printf '[hub-promote] bootstrap: deploy/hub does not exist yet
'
   else
-    subjects="$(git_cmd log --format='%h %s' -30 "$old..$new" 2>/dev/null || true)"
-    if [[ -n "$subjects" ]]; then printf '%s
' "$subjects"; else printf '[hub-promote] no commits between refs
'; fi
+    if [[ "$action" == rollback ]]; then
+      subjects="$(git_cmd log --format='%h %s' "$new..$old" 2>/dev/null || true)"
+      printf '[hub-promote] will be removed from deploy/hub:
'
+      if [[ -n "$subjects" ]]; then printf '%s
' "$subjects"; else printf '  (none)
'; fi
+      subjects="$(git_cmd log --format='%h %s' "$old..$new" 2>/dev/null || true)"
+      if [[ -n "$subjects" ]]; then printf '[hub-promote] will be added to deploy/hub:
%s
' "$subjects"; fi
+    else
+      subjects="$(git_cmd log --format='%h %s' -30 "$old..$new" 2>/dev/null || true)"
+      if [[ -n "$subjects" ]]; then printf '%s
' "$subjects"; else printf '[hub-promote] no commits between refs
'; fi
+    fi
   fi
   [[ -z "$ref" ]] || printf '[hub-promote] REF: %s
' "$ref"
   [[ -t 0 ]] || die 'confirmation requires a TTY'
@@ -151,34 +159,41 @@ status() {
 
 rollback() {
   local break_glass="${1:-0}"
-  local old target tag tag_data action sha top
+  local old target tag tag_data action sha tag_old top
   local -a tags=()
-  local -a stack=()
+  local -a stack_old=()
+  local -a stack_new=()
   git_cmd fetch "$REMOTE" --prune
   old="$(remote_sha)"
   mapfile -t tags < <(git_cmd ls-remote --tags "$REMOTE" "refs/tags/${TAG_PREFIX}*" | awk '$2 !~ /\^\{\}$/ {print $2}' | sort -k1,1)
   for tag in "${tags[@]}"; do
     tag_data="$(git_cmd fetch --no-tags "$REMOTE" "$tag" >/dev/null && git_cmd cat-file -p FETCH_HEAD)" || die "promotion tag $tag is not available"
     action="$(sed -n 's/^action: //p' <<< "$tag_data" | head -1)"
+    tag_old="$(sed -n 's/^old: //p' <<< "$tag_data" | head -1)"
     sha="$(sed -n 's/^new: //p' <<< "$tag_data" | head -1)"
-    [[ "$sha" =~ ^[0-9a-f]{40,64}$ ]] || die "promotion tag $tag has no valid new SHA"
+    [[ "$sha" =~ ^[0-9a-f]{40,64}$ && "$tag_old" =~ ^[0-9a-f]{40,64}$ ]] || die "promotion tag $tag has no valid old/new SHA"
     case "$action" in
       promote)
-        if (( ${#stack[@]} == 0 )) || [[ "${stack[${#stack[@]}-1]}" != "$sha" ]]; then
-          stack+=("$sha")
+        if [[ "$tag_old" != "$sha" ]]; then
+          stack_old+=("$tag_old")
+          stack_new+=("$sha")
         fi
         ;;
       rollback)
-        (( ${#stack[@]} >= 2 )) || die "rollback tag $tag has no earlier promotion to pop"
-        top="${stack[${#stack[@]}-2]}"
-        [[ "$sha" == "$top" ]] || die "rollback tag $tag does not match the promotion stack"
-        unset 'stack[${#stack[@]}-1]'
+        (( ${#stack_new[@]} >= 1 )) || die "rollback tag $tag has no earlier promotion to pop"
+        top="${stack_new[${#stack_new[@]}-1]}"
+        [[ "$tag_old" == "$top" && "$sha" == "${stack_old[${#stack_old[@]}-1]}" ]] || die "rollback tag $tag does not match the promotion stack"
+        unset 'stack_old[${#stack_old[@]}-1]'
+        unset 'stack_new[${#stack_new[@]}-1]'
         ;;
       *) die "promotion tag $tag has an unknown action" ;;
     esac
   done
-  (( ${#stack[@]} >= 2 )) || die 'there is no earlier promotion to return to'
-  top="${stack[${#stack[@]}-1]}"
+  (( ${#stack_new[@]} > 0 )) || die 'there is no earlier promotion to return to'
+  top="${stack_new[${#stack_new[@]}-1]}"
+  if [[ "${stack_old[${#stack_old[@]}-1]}" =~ ^0+$ ]]; then
+    die 'the promotion stack only contains the bootstrap; there is no earlier state to return to'
+  fi
   if [[ "$old" != "$top" ]]; then
     if ! git_cmd merge-base --is-ancestor "$top" "$old" 2>/dev/null; then
       die 'deploy/hub does not match the promotion stack top'
@@ -195,7 +210,7 @@ rollback() {
       die 'deploy/hub does not match the promotion stack top'
     fi
   fi
-  target="${stack[${#stack[@]}-2]}"
+  target="${stack_old[${#stack_old[@]}-1]}"
   show_and_confirm "$old" "$target" rollback
   record_move "$old" "$target" rollback "" "$break_glass"
 }
diff --git a/docs/howto/hub-promote.md b/docs/howto/hub-promote.md
index bb33fe13..7b516429 100644
--- a/docs/howto/hub-promote.md
+++ b/docs/howto/hub-promote.md
@@ -63,11 +63,16 @@ make hub-promote REF=<commit-ish> BREAK_GLASS=1
 
 ## Roll back and inspect
 
-`make hub-rollback` uses the promotion tags as a stack: after promoting A, B and
-C, successive rollbacks move to B and then A. When you want to move forward
-again, promote that commit explicitly with `make hub-promote REF=<commit-ish>`.
-If `deploy/hub` holds promoter commits added after the last promotion (not in
-the promotion stack top), `make hub-rollback` refuses and lists them unless
+`make hub-rollback` returns `deploy/hub` to the state recorded in the latest
+promotion tag's `old:` field. This keeps commits that were already live before
+that promotion, including CVE image pins committed directly to `deploy/hub`.
+The confirmation lists every commit that will be removed and, when applicable,
+commits that will be added. After promoting A, B and C without intervening
+commits, successive rollbacks move to B and then A. When you want to move
+forward again, promote that commit explicitly with
+`make hub-promote REF=<commit-ish>`.
+If `deploy/hub` holds commits added after the last promotion (not in the
+promotion stack top), `make hub-rollback` refuses and lists them unless
 overridden with `BREAK_GLASS=1`:
 
 ```sh
diff --git a/scripts/tests/bin/hub_promote.bats b/scripts/tests/bin/hub_promote.bats
index c6c901ef..a530d508 100644
--- a/scripts/tests/bin/hub_promote.bats
+++ b/scripts/tests/bin/hub_promote.bats
@@ -422,8 +422,10 @@ REF: $promoted"
   _rollback_to "$B_SHA"
 }
 
-@test "N5: exhausted promotion stack refuses a third rollback without changes" {
+@test "N5: exhausted promotion stack refuses after returning to bootstrap state" {
   _seed_exhausted_promotion_stack
+  initial="$(git -C "$WORK" rev-parse "$A_SHA^")"
+  _rollback_to "$initial"
   old="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
   tag_count="$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {n++} END {print n+0}')"
   _run_promoter_tty promote empty rollback
@@ -434,16 +436,56 @@ REF: $promoted"
 }
 
 @test "N5: bootstrap-only history refuses rollback without changes" {
-  _promote_sha "$(git -C "$WORK" rev-parse HEAD)"
+  _make_candidate
+  git --git-dir="$ORIGIN" update-ref -d refs/heads/deploy/hub
+  _run_promoter_tty promote success promote k3d-manager-v1.43.15 1
+  [ "$status" -eq 0 ]
   old="$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)"
   tag_count="$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {n++} END {print n+0}')"
   _run_promoter_tty promote empty rollback
   [ "$status" -ne 0 ]
-  [[ "$output" == *"no earlier promotion"* ]]
+  [[ "$output" == *"bootstrap"* ]]
   [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$old" ]
   [ "$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {n++} END {print n+0}')" = "$tag_count" ]
 }
 
+@test "M1 N1 E1: rollback preserves a promoter commit present before the last promotion" {
+  [ "$(cd "$(git -C "$WORK" remote get-url origin)" && pwd -P)" = "$ORIGIN" ]
+  [ "$ORIGIN" != *"github.com"* ]
+  _prepare_promotion_history
+  _promote_sha "$A_SHA"
+
+  git -C "$WORK" fetch -q origin deploy/hub
+  git -C "$WORK" checkout -q -B deploy/hub origin/deploy/hub
+  printf 'CVE pin X
' > "$WORK/cve-pin-x.txt"
+  git -C "$WORK" add cve-pin-x.txt
+  git -C "$WORK" commit -qm 'fix(cve): pin image X'
+  X_SHA="$(git -C "$WORK" rev-parse HEAD)"
+  git -C "$WORK" push -q origin HEAD:refs/heads/deploy/hub
+
+  git -C "$WORK" checkout -q -B feature/promotion-B "$X_SHA"
+  printf 'promotion B
' > "$WORK/promotion-B.txt"
+  git -C "$WORK" add promotion-B.txt
+  git -C "$WORK" commit -qm 'promotion B includes X'
+  B_WITH_X="$(git -C "$WORK" rev-parse HEAD)"
+  git -C "$WORK" push -q origin HEAD:refs/heads/feature/promotion-B
+  _promote_sha feature/promotion-B
+  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$B_WITH_X" ]
+
+  _run_promoter_tty promote empty rollback
+  [ "$status" -eq 0 ]
+  [[ "$output" == *"will be removed from deploy/hub"* ]]
+  [[ "$output" == *"promotion B includes X"* ]]
+  [[ "$output" != *"no commits between refs"* ]]
+  [ "$(git -C "$WORK" ls-remote origin refs/heads/deploy/hub | cut -f1)" = "$X_SHA" ]
+  tag_ref="$(git -C "$WORK" ls-remote --tags origin 'refs/tags/hub-promote/*' | awk '$2 !~ /\^\{\}$/ {print $2}' | sort -r | head -1)"
+  git -C "$WORK" fetch -q origin "$tag_ref"
+  tag_data="$(git -C "$WORK" cat-file -p FETCH_HEAD)"
+  grep -Fxq 'action: rollback' <<< "$tag_data"
+  grep -Fxq "old: $B_WITH_X" <<< "$tag_data"
+  grep -Fxq "new: $X_SHA" <<< "$tag_data"
+}
+
 @test "N5: rollback refuses when deploy/hub moved outside the promotion stack" {
   _prepare_promotion_history
   _promote_sha "$A_SHA"
```
