#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
setup() {
  export HOME="$BATS_TEST_TMPDIR/home" ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  export CVE_PIN_REPO_URL="file://$ORIGIN" GIT_WRITE_TOKEN=fixture-askpass-only
  export LOG="$BATS_TEST_TMPDIR/log" OBS="$BATS_TEST_TMPDIR/observations"
  export APP_SERVICES="shopping-cart-frontend shopping-cart-basket"
  export REAL_GIT
  REAL_GIT="$(command -v git)"
  export GIT_ALLOW_PROTOCOL=file GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@localhost
  export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@localhost
  mkdir "$HOME" "$OBS" "$BATS_TEST_TMPDIR/bin"
  [[ "$ORIGIN" == "$BATS_TEST_TMPDIR/origin.git" && "$CVE_PIN_REPO_URL" == "file://$ORIGIN" ]]
  : >"$LOG"
  # Route the dispatch-base writer's hard-coded GitHub URL to this same
  # origin when the verifier runs the new tests against the old scanner.
  git config --global "url.$CVE_PIN_REPO_URL.insteadOf" https://github.com/wilddog64/k3d-manager.git
  git init -q --bare "$ORIGIN"
  seed="$BATS_TEST_TMPDIR/seed"
  git init -qb deploy/hub "$seed"
  front=shopping-cart-frontend; basket=shopping-cart-basket
  digest="sha256:$(printf '%064d' 1)"; other="sha256:$(printf '%064d' 2)"
  for service in $APP_SERVICES; do
    mkdir -p "$seed/services/$service"
    cp "$BATS_TEST_DIRNAME/../../../services/$service/kustomization.yaml" "$seed/services/$service/"
    printf '%s\n' deploy/hub > "$OBS/$service.rev"
  done
  base="$(awk '/^    digest:/ {print $2}' "$seed/services/$front/kustomization.yaml")"
  git -C "$seed" add services
  git -C "$seed" commit -qm bases
  git -C "$seed" push -q "$CVE_PIN_REPO_URL" HEAD:refs/heads/deploy/hub
  ref=refs/heads/cve-pins/hub
  src="$BATS_TEST_DIRNAME/../../etc/argocd/platform-ops/app-cve-scan.sh"
  driver="$BATS_TEST_TMPDIR/driver"
  sed '/^# === MAIN ===/,$d' "$src" >"$driver"
  cat >>"$driver" <<'SH'
_hub_kubectl() {
  echo "kubectl $*" >>"$LOG"
  svc=${5#ubuntu-hostinger-}
  case "$*" in
    *'get application '*targetRevision*) cat "$OBS/$svc.rev";;
    # m4-air, 2026-11-20: real kubectl against a read-only loopback API
    # with an empty kubeconfig. Missing: rc 0, empty stdout. Forbidden:
    # rc 1, empty stdout. An existing Application with no override was JSON.
    *'get application '*'--ignore-not-found -o json')
      [ ! -f "$OBS/$svc.failed" ] || return 1
      if [ -f "$OBS/$svc.json" ]; then cat "$OBS/$svc.json"; fi;;
    *'annotate application '*|*'patch application '*) :;;
    *) return 1;;
  esac
}
_load_app_cluster_access() { :; }
_find_report_row() { printf 'shopping-cart-apps report %s sha-running 0 0' "$1"; }
_report_cves() { :; }
_emit_remediation_event() { echo event >>"$LOG"; }
_notify() { echo "notify $*" >>"$LOG"; }
if [ "$1" != main ]; then
  _rc=0
  "$@" || exit 1
  exit "$_rc"
fi
SH
  sed -n '/^# === MAIN ===/,$p' "$src" >>"$driver"
  cat >"$BATS_TEST_TMPDIR/bin/git" <<'SH'
#!/bin/sh
echo "git $*" >>"$LOG"
case "$1" in
  ls-remote)
    [ -z "${LOOKUP_ERROR:-}" ] || exit "$LOOKUP_ERROR"
    [ "$("$GIT_ASKPASS" Password)" = "$GIT_WRITE_TOKEN" ] && echo askpass-ok >>"$LOG";;
  push)
    [ "$*" = "push -q origin HEAD:refs/heads/cve-pins/hub" ] || exit 94
    if [ -s "$OBS/races" ]; then
      count="$(cat "$OBS/races")"
      if [ "$count" -gt 0 ]; then
        echo $((count-1)) > "$OBS/races"
        ref=refs/heads/cve-pins/hub
        if old="$("$REAL_GIT" --git-dir="$ORIGIN" rev-parse --verify "$ref" 2>/dev/null)"; then
          new="$(echo competitor | "$REAL_GIT" --git-dir="$ORIGIN" commit-tree "$old^{tree}" -p "$old")"
        else
          # A concurrent creator publishes its independently built orphan.
          new="$("$REAL_GIT" --git-dir="$ORIGIN" rev-parse refs/fixture/seed)"
        fi
        "$REAL_GIT" --git-dir="$ORIGIN" update-ref "$ref" "$new" || exit 1
      fi
    fi;;
esac
exec "$REAL_GIT" "$@"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/git"
}

scan() { env PATH="$BATS_TEST_TMPDIR/bin:$PATH" sh "$driver" "$@"; }
origin() { git --git-dir="$ORIGIN" "$@"; }
pins() { origin show "$ref:pins.json"; }
tip() { origin rev-parse "$ref"; }
seed_empty() {
  run scan main
  [ "$status" = 0 ]
  [[ "$output" == *'PINSYNC: complete pins=0 live_overrides=0 incomplete=0'* ]]
  grep -F "get application ubuntu-hostinger-$front" "$LOG"
  [ "$(origin ls-tree --name-only "$ref")" = pins.json ]
}

@test "writes only pins with authenticated argv hygiene and preserves timestamp on rerun" {
  # Start on the same origin for both implementations, independently of
  # startup seeding. This lets the verifier observe the old deploy/hub write.
  git -C "$seed" switch -q --orphan cve-pins/hub
  echo '{"v":1,"cvePins":{}}' >"$seed/pins.json"
  git -C "$seed" add pins.json
  git -C "$seed" commit -qm 'fixture: empty pin branch'
  git -C "$seed" push -q "$CVE_PIN_REPO_URL" "HEAD:$ref"
  scan _hub_kubectl -n cicd get application "ubuntu-hostinger-$front" --ignore-not-found -o json
  grep -F "kubectl -n cicd get application ubuntu-hostinger-$front" "$LOG"
  old="$(tip)"; deploy="$(origin rev-parse deploy/hub)"
  run scan _promote_image "$front" "ghcr.io/wilddog64/$front" sha-new "$digest" old CVE-1
  [ "$status" = 0 ]
  sha="$(tip)"
  [[ "$output" == *"on cve-pins/hub@$sha"* ]]
  pins | jq -e --arg s "$front" --arg d "$digest" --arg b "$base" '.v==1 and (.cvePins[$s] | .digest==$d and .base==$b and (.at|fromdateiso8601)>0)'
  grep -F "annotate application ubuntu-hostinger-$front" "$LOG"
  [ "$(grep -cx event "$LOG")" = 1 ]; grep -F "git=cve-pins/hub@$sha" "$LOG"
  grep -Fx askpass-ok "$LOG"
  [[ "$output" != *"$GIT_WRITE_TOKEN"* ]]
  run ! grep -F "$GIT_WRITE_TOKEN" "$LOG"
  origin merge-base --is-ancestor "$old" "$sha"
  [ "$(origin for-each-ref --format='%(refname) %(objectname)' refs/heads)" = "$(printf '%s %s\n%s %s' "$ref" "$sha" refs/heads/deploy/hub "$deploy")" ]
  cat >"$BATS_TEST_TMPDIR/bin/date" <<'SH'
#!/bin/sh
echo 2030-01-01T00:00:00Z
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/date"
  run --separate-stderr scan _git_persist_promotion "$front" "$digest" "$base"
  [ "$status" = 0 ]; [ "$output" = "$sha" ]; [ "$(tip)" = "$sha" ]
  run scan _git_persist_promotion "$front" "$other" "$base"
  [ "$status" = 0 ]; [ "$(tip)" != "$sha" ]
  pins | jq -e --arg s "$front" '.cvePins[$s].at=="2030-01-01T00:00:00Z"'
}

@test "clean startup seeds both legacy overrides in an orphan then makes no new commit" {
  for service in $APP_SERVICES; do
    image="ghcr.io/wilddog64/$service@$digest"
    if [ "$service" = "$front" ]; then image="ghcr.io/wilddog64/$front=ghcr.io/wilddog64/$front:sha-new@$other"; fi
    jq -n --arg im "$image" '{spec:{source:{kustomize:{images:[$im]}}}}' >"$OBS/$service.json"
  done
  run scan main
  [ "$status" = 0 ]; [[ "$output" == *'PINSYNC: complete pins=2 live_overrides=2 incomplete=0'* ]]
  sha="$(tip)"
  [ "$(origin rev-list --parents -1 "$ref")" = "$sha" ]
  pins | jq -e --arg f "$front" --arg b "$basket" --arg d "$other" --arg base "$base" '.cvePins[$f].digest==$d and .cvePins[$f].base==$base and .cvePins[$b].base=="none"'
  run scan main
  [ "$status" = 0 ]; [ "$(tip)" = "$sha" ]
}

@test "seed distinguishes observed live overrides from written pins" {
  jq -n --arg im "ghcr.io/wilddog64/$front@$digest" '{spec:{source:{kustomize:{images:[$im]}}}}' >"$OBS/$front.json"
  echo '{"apiVersion":"argoproj.io/v1alpha1","kind":"Application","metadata":{"name":"multi","namespace":"cicd"},"spec":{"sources":[{"repoURL":"https://example.invalid/repo"}]}}' >"$OBS/$basket.json"
  run scan main
  [ "$status" = 1 ]
  [[ "$output" == *"PINSEED: incomplete read of $basket; branch not created"* ]]
  [[ "$output" == *'PINSYNC: FAILED — incomplete reads=1'* ]]
  [ -z "$(origin show-ref "$ref")" ]
}

@test "pin validation blocks invalid promotion entries before push" {
  seed_empty
  original_tip="$(tip)"
  for service in shopping-cart-outside shopping-cart-frontend; do
    bad_digest="$digest"
    [ "$service" != shopping-cart-frontend ] || bad_digest=sha256:short
    : >"$LOG"
    run scan _git_persist_promotion "$service" "$bad_digest" none
    [ "$status" = 1 ]
    [ "$(tip)" = "$original_tip" ]
    run ! grep -F 'git push' "$LOG"
  done

  local mutant="$BATS_TEST_TMPDIR/driver-without-validation"
  sed 's/_pin_valid \&\& git add/git add/' "$driver" >"$mutant"
  [ "$(grep -c '_pin_valid && git add' "$driver")" = 1 ]
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" sh "$mutant" _git_persist_promotion shopping-cart-outside "$digest" none
  [ "$(tip)" != "$original_tip" ]
  run grep -F 'git push -q origin HEAD:refs/heads/cve-pins/hub' "$LOG"
  [ "$status" = 0 ]
  run origin show "$ref:pins.json"
  printf '%s\n' "$output" | jq -e '.cvePins | has("shopping-cart-outside")'
}

@test "incomplete application, malformed override and missing base each abort all seed writes" {
  refs="$(origin show-ref)"
  jq -n --arg im "ghcr.io/wilddog64/$basket@$digest" '{spec:{source:{kustomize:{images:[$im]}}}}' >"$OBS/$basket.json"
  touch "$OBS/$front.failed"
  for error in unreadable malformed missing-base; do
    case "$error" in
      malformed) rm "$OBS/$front.failed"; echo '{"spec":{"source":{"kustomize":{"images":["bad"]}}}}' >"$OBS/$front.json";;
      missing-base) sed "s/$basket/$front/g" "$OBS/$basket.json" >"$OBS/$front.json"; echo missing >"$OBS/$front.rev";;
    esac
    run scan main
    [ "$status" = 1 ]; [[ "$output" == *"PINSEED: incomplete read of $front; branch not created"* ]]
    [ "$(origin show-ref)" = "$refs" ]
  done
  echo '{"apiVersion":"argoproj.io/v1alpha1","kind":"Application","metadata":{"name":"empty","namespace":"cicd"},"spec":{"source":{}}}' >"$OBS/$front.json"
  run scan main
  [ "$status" = 0 ]; [[ "$output" == *'pins=1 live_overrides=1 incomplete=0'* ]]
}

@test "lookup failures and absent tokens leave every remote ref unchanged" {
  refs="$(origin show-ref)"
  export LOOKUP_ERROR=128
  run scan main
  [ "$status" = 1 ]; [[ "$output" == *'PINSYNC: pin branch lookup failed (rc 128)'* ]]
  [[ "$output" == *'PINSYNC: FAILED — pin branch lookup or synchronization failed'* ]]
  run scan _promote_image "$basket" repo sha "$digest" old CVE-1
  [ "$status" = 1 ]; [[ "$output" == *"GITWRITE $basket: pin branch lookup failed"* ]]
  run ! grep -qx event "$LOG"; [ "$(origin show-ref)" = "$refs" ]
  : >"$LOG"
  GIT_WRITE_TOKEN='' run scan main
  [ "$status" = 1 ]; [[ "$output" == *'PINSYNC: FAILED — no GIT_WRITE_TOKEN'* ]]
  run ! grep -q '^git ' "$LOG"; [ "$(origin show-ref)" = "$refs" ]
}

@test "startup prunes changed bases together and keeps pins on read failure" {
  seed_empty
  scan _git_persist_promotion "$front" "$digest" "$base"
  scan _git_persist_promotion "$basket" "$digest" none
  old="$(tip)"; scan main; [ "$(tip)" = "$old" ]
  scan _git_persist_promotion "$basket" "$digest" "$other"
  scan _git_persist_promotion "$front" "$digest" "$other"
  old="$(tip)"; echo missing >"$OBS/$front.rev"; echo missing >"$OBS/$basket.rev"
  scan main; [ "$(tip)" = "$old" ]
  echo deploy/hub >"$OBS/$front.rev"; echo deploy/hub >"$OBS/$basket.rev"
  scan main
  [ "$(origin rev-parse "$ref^")" = "$old" ]
  pins | jq -e '.cvePins=={}'
}

@test "invalid pin schemas never advance the branch or issue an event" {
  seed_empty
  git -C "$seed" fetch -q "$CVE_PIN_REPO_URL" "$ref"
  git -C "$seed" checkout -q --detach FETCH_HEAD
  valid="$(jq -cn --arg d "$digest" --arg s "$basket" '{v:1,cvePins:{($s):{digest:$d,base:"none",at:"2026-01-01T00:00:00Z"}}}')"
  for filter in 'del(.v)' '.v=2' '.extra=true' '.cvePins |= with_entries(.key="invalid")' \
      '.cvePins |= with_entries(.key="shopping-cart-foreign")' '.cvePins[].digest="short"' \
      '.cvePins[].base="unknown"' '.cvePins[].at="yesterday"' '.cvePins[].extra=true'; do
    doc="$(jq -c "$filter" <<<"$valid")"
    echo "$doc" >"$seed/pins.json"
    git -C "$seed" commit -qam invalid
    git -C "$seed" push -q "$CVE_PIN_REPO_URL" "HEAD:$ref"
    refs="$(origin show-ref)"
    run scan _promote_image "$basket" repo sha "$digest" old CVE-1
    [ "$status" = 1 ]; [[ "$output" == *"pins.json invalid on cve-pins/hub"* ]]
    run ! grep -qx event "$LOG"; [ "$(origin show-ref)" = "$refs" ]
  done
}

@test "one concurrent write retries and two reject the promotion" {
  seed_empty
  echo 1 >"$OBS/races"
  scan _git_persist_promotion "$basket" "$digest" none
  pins | jq -e --arg s "$basket" --arg d "$digest" '.cvePins[$s].digest==$d'
  echo 2 >"$OBS/races"
  run scan _promote_image "$basket" repo sha "$other" old CVE-1
  [ "$status" = 1 ]; [[ "$output" == *'NOT APPLIED'* ]]
  run ! grep -qx event "$LOG"; pins | jq -e --arg s "$basket" --arg d "$digest" '.cvePins[$s].digest==$d'
}

@test "concurrent seed adopts the winner and continues writing" {
  seed_empty
  winner="$(echo competing-seed | git --git-dir="$ORIGIN" commit-tree "$ref^{tree}")"
  origin update-ref refs/fixture/seed "$winner"
  origin update-ref -d "$ref"
  echo 1 >"$OBS/races"
  scan _git_persist_promotion "$basket" "$digest" none
  [ "$(origin rev-parse "$ref^")" = "$(origin rev-parse refs/fixture/seed)" ]
  pins | jq -e --arg s "$basket" --arg d "$digest" '.cvePins[$s].digest==$d'
}
