#!/usr/bin/env bats

# Template captured from services-git.yaml in worktree commit 5f7ef7be, 2026-11-24.
# The fake ApplicationSet below preserves the rendered generator tree and generated app labels.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  WORK="$BATS_TEST_TMPDIR/fake-repo"
  STUB="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$WORK" "$STUB"
  [ "$WORK" = "$BATS_TEST_TMPDIR/fake-repo" ]
  cp "$REPO_ROOT/Makefile" "$WORK/Makefile"
  cat > "$WORK/appset.json" <<'JSON'
{"spec":{"generators":[{"matrix":{"generators":[{"clusters":{}},{"matrix":{"generators":[{"git":{"revision":"release","directories":[{"path":"services/*"}]}},{"git":{"revision":"pins","files":[{"path":"pins.json"}]}}]}}]}}],"template":{"spec":{"source":{"targetRevision":"release"}}}}}
JSON
  cp "$WORK/appset.json" "$WORK/appset.original.json"
  cat > "$WORK/apps" <<'APPS'
application/cluster-a-shopping-cart-basket
application/cluster-b-shopping-cart-frontend
APPS
  cat > "$STUB/kubectl" <<'SH'
#!/usr/bin/env bash
set -e
case "$1 $2" in
  "get applicationset")
    if [ "${GET_APPSET_FAIL:-0}" = 1 ]; then exit 1; fi
    cat "$FIXTURE_ROOT/appset.json"
    ;;
  "get applications") cat "$FIXTURE_ROOT/apps" ;;
  "patch applicationset")
    printf '%s\n' "$*" >> "$CALL_LOG"
    if [ "${PATCH_FAIL:-0}" = 1 ]; then exit 1; fi
    patch="${*: -1}"
    printf '%s' "$patch" > "$PATCH_FILE"
    python3 - "$FIXTURE_ROOT/appset.json" "$patch" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
for item in json.loads(sys.argv[2]):
    cur = doc
    keys = item["path"].strip("/").split("/")
    keys = [key.replace("~1", "/").replace("~0", "~") for key in keys]
    for key in keys[:-1]:
        cur = cur[int(key)] if isinstance(cur, list) else cur[key]
    key = keys[-1]
    if isinstance(cur, list):
        cur[int(key)] = item["value"]
    else:
        cur[key] = item["value"]
json.dump(doc, open(sys.argv[1], "w", encoding="utf-8"))
PY
    ;;
  "annotate application") printf '%s\n' "$*" >> "$CALL_LOG" ;;
  *) echo "unexpected kubectl: $*" >&2; exit 2 ;;
esac
SH
  chmod +x "$STUB/kubectl"
  export FIXTURE_ROOT="$WORK" CALL_LOG="$WORK/calls" PATCH_FILE="$WORK/patch.json"
  export GET_APPSET_FAIL=0 PATCH_FAIL=0
  export PATH="$STUB:$PATH"
}

@test "sync-branch patches services git revision and refreshes generated apps" {
  run python3 - "$WORK/appset.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
patch = {"op": "replace", "path": "/spec/generators/0/git/revision", "value": "feature/test"}
cur = doc
try:
    for key in patch["path"].strip("/").split("/")[:-1]:
        cur = cur[int(key)] if isinstance(cur, list) else cur[key]
    key = patch["path"].strip("/").split("/")[-1]
    if key not in cur:
        raise KeyError(key)
except (IndexError, KeyError, TypeError) as exc:
    print(f"pre-fix JSON patch failed as expected: {exc}")
    sys.exit(0)
sys.exit("pre-fix JSON patch unexpectedly resolved")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"pre-fix JSON patch failed as expected"* ]]
  run make -C "$WORK" sync-branch BRANCH=feature/test ARGOCD_NS=cicd INFRA_CONTEXT=fixture
  [ "$status" -eq 0 ]
  jq -e '.[0].path == "/spec/generators/0/matrix/generators/1/matrix/generators/0/git/revision" and .[0].value == "feature/test"' "$PATCH_FILE"
  jq -e '.[1].path == "/spec/template/spec/source/targetRevision" and .[1].value == "feature/test"' "$PATCH_FILE"
  grep -qF 'annotate application application/cluster-a-shopping-cart-basket' "$CALL_LOG"
  grep -qF 'annotate application application/cluster-b-shopping-cart-frontend' "$CALL_LOG"
  run grep -qF '/spec/generators/0/git/revision' "$CALL_LOG"
  [ "$status" -ne 0 ]
}

@test "sync-main finds the services generator when git generators are swapped" {
  jq '.spec.generators[0].matrix.generators[1].matrix.generators |= reverse' "$WORK/appset.json" > "$WORK/swapped.json"
  mv "$WORK/swapped.json" "$WORK/appset.json"
  run make -C "$WORK" sync-main ARGOCD_NS=cicd INFRA_CONTEXT=fixture
  [ "$status" -eq 0 ]
  jq -e '.[0].path == "/spec/generators/0/matrix/generators/1/matrix/generators/1/git/revision" and .[0].value == "main"' "$PATCH_FILE"
  grep -qF 'annotate application application/cluster-a-shopping-cart-basket' "$CALL_LOG"
}

@test "both targets stop when the ApplicationSet get fails before patching" {
  failures=0
  for target in sync-branch sync-main; do
    : > "$CALL_LOG"
    GET_APPSET_FAIL=1 run make -C "$WORK" "$target" BRANCH=feature/test ARGOCD_NS=cicd INFRA_CONTEXT=fixture
    [ "$status" -ne 0 ] || failures=$((failures + 1))
    run grep -qF 'patch applicationset' "$CALL_LOG"
    [ "$status" -ne 0 ] || failures=$((failures + 1))
  done
  [ "$failures" -eq 0 ]
}

@test "both targets stop after a failed patch without annotating apps" {
  failures=0
  for target in sync-branch sync-main; do
    : > "$CALL_LOG"
    PATCH_FAIL=1 run make -C "$WORK" "$target" BRANCH=feature/test ARGOCD_NS=cicd INFRA_CONTEXT=fixture
    [ "$status" -ne 0 ] || failures=$((failures + 1))
    run grep -qF 'annotate application' "$CALL_LOG"
    [ "$status" -ne 0 ] || failures=$((failures + 1))
  done
  [ "$failures" -eq 0 ]
}

@test "both targets reject zero matching services generators without patching" {
  jq 'del(.spec.generators[0].matrix.generators[1].matrix.generators[0].git.directories)' "$WORK/appset.original.json" > "$WORK/appset.json"
  failures=0
  for target in sync-branch sync-main; do
    : > "$CALL_LOG"
    run make -C "$WORK" "$target" BRANCH=feature/test ARGOCD_NS=cicd INFRA_CONTEXT=fixture
    [ "$status" -ne 0 ] || failures=$((failures + 1))
    run grep -qF 'patch applicationset' "$CALL_LOG"
    [ "$status" -ne 0 ] || failures=$((failures + 1))
  done
  [ "$failures" -eq 0 ]
}

@test "both targets reject two matching services generators without patching" {
  jq '.spec.generators[0].matrix.generators[1].matrix.generators[1].git.directories = [{"path":"services/*"}]' "$WORK/appset.original.json" > "$WORK/appset.json"
  failures=0
  for target in sync-branch sync-main; do
    : > "$CALL_LOG"
    run make -C "$WORK" "$target" BRANCH=feature/test ARGOCD_NS=cicd INFRA_CONTEXT=fixture
    [ "$status" -ne 0 ] || failures=$((failures + 1))
    run grep -qF 'patch applicationset' "$CALL_LOG"
    [ "$status" -ne 0 ] || failures=$((failures + 1))
  done
  [ "$failures" -eq 0 ]
}
