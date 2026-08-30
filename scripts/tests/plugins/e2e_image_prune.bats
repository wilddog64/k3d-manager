#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/e2e.sh"

  RUN_LOG="$BATS_TEST_TMPDIR/run.log"
  : > "$RUN_LOG"

  # A fake `docker` on PATH so the `command -v docker` guard passes; the plugin
  # never calls it directly — all docker calls route through _run_command below.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/docker" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/docker"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  # Controllable docker via _run_command. IMAGE_LIST drives the `docker images`
  # listing; PROTECT_ID maps a repo:tag to the id `docker image inspect` returns.
  IMAGE_LIST=""
  declare -gA PROTECT_ID=()
  _run_command() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--soft|--quiet|--prefer-sudo|--require-sudo|--interactive-sudo) shift ;;
        --probe) shift 2 ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    echo "$*" >> "$RUN_LOG"
    case "$*" in
      "docker images "*) printf '%s\n' "$IMAGE_LIST" ;;
      "docker image inspect -f {{.Id}} "*)
        local ref="${@: -1}"
        [[ -n "${PROTECT_ID[$ref]:-}" ]] && printf '%s\n' "${PROTECT_ID[$ref]}"
        ;;
      "docker ps -aq") : ;;
      *) : ;;
    esac
    return 0
  }
}

@test "e2e_prune_images is a public function (no leading underscore)" {
  run declare -f e2e_prune_images
  [ "$status" -eq 0 ]
  [[ "$BATS_TEST_DESCRIPTION" != _* ]]
}

@test "e2e_prune_images --help prints usage and exits 0" {
  run e2e_prune_images --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: e2e_prune_images"* ]]
  [[ "$output" == *"Dry-run by default"* ]]
}

@test "e2e_prune_images rejects a non-integer --days" {
  run e2e_prune_images --days abc
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be a non-negative integer"* ]]
}

@test "_e2e_kustomization_images pairs newName with newTag from the real substrate" {
  run _e2e_kustomization_images "${SCRIPT_DIR}/etc/e2e/kustomization.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghcr.io/wilddog64/shopping-cart-product-catalog:sha-"* ]]
  [[ "$output" == *"ghcr.io/wilddog64/shopping-cart-basket:sha-"* ]]
  [[ "$output" == *"ghcr.io/wilddog64/shopping-cart-order:sha-"* ]]
  [ "$(printf '%s\n' "$output" | grep -c ':')" -eq 3 ]
}

@test "_e2e_kustomization_images skips an entry that has newTag but no newName" {
  local f="$BATS_TEST_TMPDIR/kustomization.yaml"
  cat > "$f" <<'YAML'
images:
- name: only-tag-changed
  newTag: sha-deadbeef
- name: full-override
  newName: ghcr.io/example/app
  newTag: sha-cafef00d
YAML
  run _e2e_kustomization_images "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "ghcr.io/example/app:sha-cafef00d" ]
}

@test "_e2e_substrate_images unions kustomize overrides with literal manifest images" {
  run _e2e_substrate_images "${SCRIPT_DIR}/etc/e2e"
  [ "$status" -eq 0 ]
  # kustomize newName:newTag app images
  [[ "$output" == *"ghcr.io/wilddog64/shopping-cart-basket:sha-"* ]]
  # literal tagged infra images pinned directly in the manifests
  [[ "$output" == *"postgres:16.4-alpine"* ]]
  [[ "$output" == *"redis:7.4-alpine"* ]]
  # bare kustomize placeholders (no ':') must NOT leak through — every emitted
  # line is a real, tagged image reference
  local line
  for line in "${lines[@]}"; do
    [[ "$line" == *:* ]]
  done
}

@test "_e2e_image_epoch parses a docker CreatedAt timestamp" {
  run _e2e_image_epoch "2026-08-17 10:23:45 -0700 PDT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "_e2e_image_epoch returns non-zero on an unparseable timestamp" {
  run _e2e_image_epoch "not-a-date"
  [ "$status" -ne 0 ]
}

@test "dry run flags an old unprotected image and removes nothing" {
  local old new
  old="$(_e2e_epoch_to_created $(( $(date +%s) - 90 * 86400 )))"
  new="$(_e2e_epoch_to_created $(( $(date +%s) - 1 * 86400 )))"
  IMAGE_LIST="sha256:aaa|ghcr.io/wilddog64/stale-thing:old|${old}
sha256:bbb|ghcr.io/wilddog64/fresh-thing:new|${new}"

  run e2e_prune_images --days 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"WOULD REMOVE"*"ghcr.io/wilddog64/stale-thing:old"* ]]
  [[ "$output" != *"fresh-thing"* ]]
  [[ "$output" == *"1 would be removed"* ]]
  run grep -c "docker image rm" "$RUN_LOG"
  [ "$output" -eq 0 ]
}

@test "dry run does not flag a pinned substrate image even when old" {
  local old
  old="$(_e2e_epoch_to_created $(( $(date +%s) - 90 * 86400 )))"
  PROTECT_ID["ghcr.io/wilddog64/shopping-cart-basket:sha-pinned"]="sha256:pinned"
  IMAGE_LIST="sha256:pinned|ghcr.io/wilddog64/shopping-cart-basket:sha-pinned|${old}"

  # Point the substrate at this exact pinned ref via a temp kustomization.
  SCRIPT_DIR_ORIG="$SCRIPT_DIR"
  mkdir -p "$BATS_TEST_TMPDIR/etc/e2e"
  cat > "$BATS_TEST_TMPDIR/etc/e2e/kustomization.yaml" <<'YAML'
images:
- name: shopping-cart-basket
  newName: ghcr.io/wilddog64/shopping-cart-basket
  newTag: sha-pinned
YAML
  SCRIPT_DIR="$BATS_TEST_TMPDIR"

  run e2e_prune_images --days 30
  SCRIPT_DIR="$SCRIPT_DIR_ORIG"
  [ "$status" -eq 0 ]
  [[ "$output" != *"WOULD REMOVE"* ]]
  [[ "$output" == *"0 would be removed"* ]]
}

# Helper: render a docker-style CreatedAt string for a given epoch (BSD/GNU).
_e2e_epoch_to_created() {
  local epoch="$1"
  date -j -r "$epoch" "+%Y-%m-%d %H:%M:%S %z %Z" 2>/dev/null && return 0
  date -d "@$epoch" "+%Y-%m-%d %H:%M:%S %z %Z" 2>/dev/null && return 0
  return 1
}
