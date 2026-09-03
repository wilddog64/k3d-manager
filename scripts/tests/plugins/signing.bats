#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/signing.sh"
  : > "$KUBECTL_LOG"
  : > "$HELM_LOG"

  PUB_FILE="$BATS_TEST_TMPDIR/cosign.pub"
  printf -- '-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEfakefakefake\n-----END PUBLIC KEY-----\n' \
    > "$PUB_FILE"
  POLICY_TMPL="${SCRIPT_DIR}/etc/signing/cluster-policy-verify-images.yaml.tmpl"
}

# --- deploy_image_signing surface --------------------------------------------

@test "deploy_image_signing --help prints usage" {
  run deploy_image_signing --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: deploy_image_signing"* ]]
}

@test "deploy_image_signing --enforce is gated behind SIGNING_ALLOW_ENFORCE" {
  unset SIGNING_ALLOW_ENFORCE
  run deploy_image_signing --enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"gated"* ]]
}

@test "deploy_image_signing rejects unknown option" {
  run deploy_image_signing --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option"* ]]
}

@test "deploy_image_signing --help documents --app-cluster" {
  run deploy_image_signing --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--app-cluster"* ]]
  [[ "$output" == *"no hub Vault"* ]]
}

# --- Kyverno install: pinned chart (A08) -------------------------------------

@test "_signing_install_kyverno pins the chart version (no floating latest)" {
  run _signing_install_kyverno
  [ "$status" -eq 0 ]
  read_lines "$HELM_LOG" helm_calls
  local joined="${helm_calls[*]}"
  [[ "$joined" == *"upgrade --install"* ]]
  [[ "$joined" == *"--version ${SIGNING_KYVERNO_HELM_CHART_VERSION}"* ]]
  [[ "$joined" == *"-n ${SIGNING_ADMISSION_NAMESPACE}"* ]]
}

@test "_signing_install_kyverno appends --set for each SIGNING_KYVERNO_HELM_SET entry" {
  SIGNING_KYVERNO_HELM_SET="admissionController.replicas=1 reportsController.replicas=1"
  run _signing_install_kyverno
  [ "$status" -eq 0 ]
  read_lines "$HELM_LOG" helm_calls
  local joined="${helm_calls[*]}"
  [[ "$joined" == *"--set admissionController.replicas=1"* ]]
  [[ "$joined" == *"--set reportsController.replicas=1"* ]]
}

@test "_signing_install_kyverno emits no --set when SIGNING_KYVERNO_HELM_SET is empty" {
  SIGNING_KYVERNO_HELM_SET=""
  run _signing_install_kyverno
  [ "$status" -eq 0 ]
  read_lines "$HELM_LOG" helm_calls
  [[ "${helm_calls[*]}" != *"--set"* ]]
}

@test "_signing_install_kyverno skips repo ops for a local chart path" {
  SIGNING_KYVERNO_HELM_CHART_REF="$BATS_TEST_TMPDIR/kyverno-chart.tgz"
  SIGNING_KYVERNO_HELM_REPO_URL=""
  touch "$SIGNING_KYVERNO_HELM_CHART_REF"
  run _signing_install_kyverno
  [ "$status" -eq 0 ]
  read_lines "$HELM_LOG" helm_calls
  [ "${#helm_calls[@]}" -eq 1 ]
  [[ "${helm_calls[0]}" == upgrade\ --install* ]]
}

# --- ClusterPolicy rendering: structural guarantees --------------------------

@test "_signing_render_policy injects the public key under publicKeys" {
  run _signing_render_policy "$PUB_FILE" "$POLICY_TMPL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"publicKeys: |-"* ]]
  [[ "$output" == *"BEGIN PUBLIC KEY"* ]]
}

@test "_signing_render_policy never leaks a private key" {
  run _signing_render_policy "$PUB_FILE" "$POLICY_TMPL"
  [ "$status" -eq 0 ]
  [[ "$output" != *"PRIVATE KEY"* ]]
}

@test "rendered policy is namespace-scoped to app namespaces only" {
  local out="$BATS_TEST_TMPDIR/policy.yaml"
  _signing_render_policy "$PUB_FILE" "$POLICY_TMPL" > "$out"
  grep -q "shopping-cart-apps" "$out"
  grep -q "shopping-cart-payment" "$out"
  # never all-namespaces
  ! grep -qE 'namespaces:\s*\[?\s*"?\*"?' "$out"
}

@test "rendered policy gates workload controllers, not bare Pod (401 root-cause fix)" {
  local out="$BATS_TEST_TMPDIR/policy.yaml"
  _signing_render_policy "$PUB_FILE" "$POLICY_TMPL" > "$out"
  grep -q "Deployment" "$out"
  grep -q "StatefulSet" "$out"
  # A bare Pod match reintroduces the generateName empty-namespace 401 on
  # private ghcr (docs/bugs/2026-08-30-kyverno-verify-401-private-ghcr.md).
  ! grep -qE '^\s*-\s*Pod\s*$' "$out"
}

@test "rendered policy scopes verifyImages to first-party registry, not wildcard" {
  local out="$BATS_TEST_TMPDIR/policy.yaml"
  _signing_render_policy "$PUB_FILE" "$POLICY_TMPL" > "$out"
  grep -q "ghcr.io/wilddog64/\*" "$out"
  # a bare '*' imageReference would match upstream images and block the platform
  ! grep -qE 'imageReferences:' -A2 "$out" 2>/dev/null | grep -qE '^\s*-\s*"?\*"?\s*$'
}

@test "rendered policy uses Kyverno 1.19 tlog/SCT field names (not bare 'ignore')" {
  local out="$BATS_TEST_TMPDIR/policy.yaml"
  _signing_render_policy "$PUB_FILE" "$POLICY_TMPL" > "$out"
  grep -q "ignoreTlog: true" "$out"
  grep -q "ignoreSCT: true" "$out"
  # the pre-1.19 'ignore: true' under ctlog/rekor is a strict-decoding error
  ! grep -qE '^\s*ignore: true\s*$' "$out"
}

@test "rendered policy defaults to Audit (never Enforce by default)" {
  local out="$BATS_TEST_TMPDIR/policy.yaml"
  SIGNING_VALIDATION_FAILURE_ACTION="Audit" \
    _signing_render_policy "$PUB_FILE" "$POLICY_TMPL" > "$out"
  grep -q "failureAction: Audit" "$out"
  ! grep -q "failureAction: Enforce" "$out"
}

@test "rendered policy honors Enforce when explicitly requested" {
  local out="$BATS_TEST_TMPDIR/policy.yaml"
  SIGNING_VALIDATION_FAILURE_ACTION="Enforce" \
    _signing_render_policy "$PUB_FILE" "$POLICY_TMPL" > "$out"
  grep -q "failureAction: Enforce" "$out"
}

# --- ADMIT latch: vuln attestation block (CVE-loop closure) ------------------

@test "rendered policy requires a cosign vuln attestation (ADMIT latch)" {
  local out="$BATS_TEST_TMPDIR/policy.yaml"
  _signing_render_policy "$PUB_FILE" "$POLICY_TMPL" > "$out"
  run yq -r '.spec.rules[0].verifyImages[0].attestations[0].type' "$out"
  [ "$status" -eq 0 ]
  [ "$output" = "https://cosign.sigstore.dev/attestation/vuln/v1" ]
}

@test "rendered policy is valid YAML with the key injected at BOTH depths" {
  local out="$BATS_TEST_TMPDIR/policy.yaml"
  _signing_render_policy "$PUB_FILE" "$POLICY_TMPL" > "$out"
  # The deeper attestations block re-indents the key by hand (a fixed-indent
  # awk injector renders invalid YAML at the second depth if unguarded); parse
  # with yq to prove both blocks landed at a structurally valid indent.
  run yq -e '.spec.rules[0].verifyImages[0].attestors[0].entries[0].keys.publicKeys' "$out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BEGIN PUBLIC KEY"* ]]
  run yq -e '.spec.rules[0].verifyImages[0].attestations[0].attestors[0].entries[0].keys.publicKeys' "$out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BEGIN PUBLIC KEY"* ]]
}

@test "attestation block inherits the staged failureAction (no separate gate)" {
  local out="$BATS_TEST_TMPDIR/policy.yaml"
  SIGNING_VALIDATION_FAILURE_ACTION="Audit" \
    _signing_render_policy "$PUB_FILE" "$POLICY_TMPL" > "$out"
  # Exactly one failureAction on the verifyImages entry -- the attestation check
  # rides the same Audit->Enforce staging as the signature check (D2).
  run yq -r '.spec.rules[0].verifyImages[0].failureAction' "$out"
  [ "$output" = "Audit" ]
}

# --- Secret hygiene (A02): no key material on argv ---------------------------

@test "signing.sh never passes cosign key/password as a bare CLI argument" {
  local src="${SCRIPT_DIR}/plugins/signing.sh"
  # cosign must read key material via env:// only, never --key <literal> / --password <literal>
  ! grep -qE -- '--key[= ]+[^e]' "$src"
  ! grep -qE -- '--password[= ]' "$src"
}
