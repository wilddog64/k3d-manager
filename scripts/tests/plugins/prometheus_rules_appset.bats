#!/usr/bin/env bats

APPSET="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/prometheus-rules-hub.yaml"
RULES_DIR="${BATS_TEST_DIRNAME}/../../etc/prometheus/rules"

_assert_appset_contract() {
  local appset="$1" rules_dir="$2"
  local revision path exclude file kind namespace release

  [ -f "$appset" ] || return 1
  yq -e '.kind == "ApplicationSet" and .metadata.name == "prometheus-rules-hub" and .metadata.labels["k3dm.k3d.io/rollout-stage"] == "hub"' "$appset" >/dev/null || return 1
  yq -e '.spec.template.spec.project == "platform" and .spec.template.spec.destination.server == "https://kubernetes.default.svc" and .spec.template.spec.destination.namespace == "monitoring" and .spec.template.spec.syncPolicy.automated.prune == true and .spec.template.spec.syncPolicy.automated.selfHeal == true and .spec.template.spec.syncPolicy.automated.allowEmpty == false and (.spec.template.spec.syncPolicy.syncOptions | contains(["ServerSideApply=true"])) and .spec.template.metadata.annotations["argocd.argoproj.io/compare-options"] == "ServerSideDiff=true" and (.spec.template.spec | has("ignoreDifferences") | not) and (.spec.template.spec.source.directory.include | test("^\\*\\.yaml$")) and .spec.template.spec.source.directory.recurse == false' "$appset" >/dev/null || return 1

  path="$(yq -r '.spec.template.spec.source.path // ""' "$appset")" || return 1
  revision="$(yq -r '.spec.template.spec.source.targetRevision // ""' "$appset")" || return 1
  exclude="$(yq -r '.spec.template.spec.source.directory.exclude // ""' "$appset")" || return 1
  [ "$path" = "scripts/etc/prometheus/rules" ] || return 1
  [ "$revision" = "\${K3D_MANAGER_BRANCH}" ] || return 1
  [[ "$exclude" == *"public-endpoint-probes.yaml"* ]] || return 1

  for file in "$rules_dir"/*.yaml; do
    [[ "$(basename "$file")" == public-endpoint-probes.yaml ]] && continue
    kind="$(yq -r 'select(.kind != null) | .kind' "$file")" || return 1
    namespace="$(yq -r 'select(.kind != null) | .metadata.namespace' "$file")" || return 1
    release="$(yq -r 'select(.kind != null) | .metadata.labels.release' "$file")" || return 1
    [ "$kind" = PrometheusRule ] && [ "$namespace" = monitoring ] && [ "$release" = kube-prometheus-stack ] || return 1
    if grep -Eq '\$\{[^}]+\}' "$file"; then return 1; fi
  done
}

@test "hub rules appset renders to deploy/hub and excludes probes" {
  local rendered="${BATS_TEST_TMPDIR}/prometheus-rules-hub.yaml"
  ARGOCD_NAMESPACE=argocd K3D_MANAGER_BRANCH=deploy/hub envsubst < "$APPSET" > "$rendered"
  _assert_appset_contract "$APPSET" "$RULES_DIR" deploy/hub
  [ "$(yq -r '.spec.template.spec.source.targetRevision' "$rendered")" = deploy/hub ]
}

@test "hub rules appset applies only rendered monitoring PrometheusRules" {
  _assert_appset_contract "$APPSET" "$RULES_DIR" deploy/hub
}

@test "placeholder and hardcoded branch guards fail on bad fixtures" {
  local scratch_rules="${BATS_TEST_TMPDIR}/rules" scratch_appset="${BATS_TEST_TMPDIR}/appset.yaml"
  mkdir -p "$scratch_rules"
  cp "$RULES_DIR"/*.yaml "$scratch_rules/"
  cat > "${scratch_rules}/placeholder.yaml" <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
  name: bad-placeholder
spec: {}
target: '${MISSING_VALUE}'
EOF
  run _assert_appset_contract "$APPSET" "$scratch_rules" deploy/hub
  printf 'positive control placeholder: status=%s\n' "$status"
  [ "$status" -ne 0 ]

  cp "$APPSET" "$scratch_appset"
  yq -i '.spec.template.spec.source.targetRevision = "main"' "$scratch_appset"
  run _assert_appset_contract "$scratch_appset" "$RULES_DIR" deploy/hub
  printf 'positive control branch: status=%s\n' "$status"
  [ "$status" -ne 0 ]
}
