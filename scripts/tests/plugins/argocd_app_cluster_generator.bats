#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
}

@test "argocd app cluster generator: no static ubuntu-k3s ApplicationSet destination remains" {
  run grep -rF -- "ubuntu-k3s" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets"
  [ "$status" -eq 1 ]
}

@test "argocd app cluster generator: services-git uses matrix clusters label selector" {
  run grep -F -- "- matrix:" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/services-git.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- "k3d-manager/role: app-cluster" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/services-git.yaml"
  [ "$status" -eq 0 ]
}

@test "argocd app cluster generator: data-git exists and targets shopping-cart-data" {
  run test -f "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/data-git.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- "k3d-manager/role: app-cluster" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/data-git.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- "namespace: shopping-cart-data" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/data-git.yaml"
  [ "$status" -eq 0 ]
}

@test "argocd app cluster generator: data-git ignores controller-injected volumeClaimTemplates fields" {
  run grep -F -- ".spec.persistentVolumeClaimRetentionPolicy" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/data-git.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- ".spec.volumeClaimTemplates[].status" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/data-git.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- ".spec.volumeClaimTemplates[].apiVersion" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/data-git.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- ".spec.volumeClaimTemplates[].kind" "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/data-git.yaml"
  [ "$status" -eq 0 ]
}

@test "argocd app cluster generator: data-git requires the shopping-cart opt-in label" {
  run grep -F -- 'k3d-manager/shopping-cart: "true"' "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/data-git.yaml"
  [ "$status" -eq 0 ]
}

@test "argocd app cluster generator: services-git requires the shopping-cart opt-in label" {
  run grep -F -- 'k3d-manager/shopping-cart: "true"' "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/services-git.yaml"
  [ "$status" -eq 0 ]
}

@test "argocd app cluster generator: eso and acg dashboards stay opt-in-free so the hub keeps them" {
  local _appsets="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets"
  run grep -F -- "k3d-manager/shopping-cart" "${_appsets}/eso.yaml"
  [ "$status" -eq 1 ]
  run grep -F -- "k3d-manager/shopping-cart" "${_appsets}/grafana-dashboards-acg.yaml"
  [ "$status" -eq 1 ]
  run grep -F -- "k3d-manager/role: app-cluster" "${_appsets}/eso.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- "k3d-manager/role: app-cluster" "${_appsets}/grafana-dashboards-acg.yaml"
  [ "$status" -eq 0 ]
}

@test "services-git selects the exact e2e Stripe overlays" {
  run python3 - "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/services-git.yaml" <<'PY'
import os, sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
root = os.path.abspath(os.path.join(os.path.dirname(sys.argv[1]), '..', '..', '..', '..'))
path = doc['spec']['template']['spec']['source']['path']
expected = '{{ if and (eq (index .metadata.labels "k3dm.k3d.io/e2e-profile") "stripe") (has .path.basename (list "shopping-cart-order" "shopping-cart-payment")) }}services-e2e-stripe/{{.path.basename}}{{ else }}{{.path.path}}{{ end }}'
assert path == expected, path
for directory, name, keys in [
    ('shopping-cart-order', 'order-service-config', {'BASKET_URL', 'PAYMENT_URL'}),
    ('shopping-cart-payment', 'payment-service-config', {'payment.gateway.default', 'mock.gateway.enabled', 'oauth2.jwk-set-uri'}),
]:
    overlay = yaml.safe_load(open(os.path.join(root, 'services-e2e-stripe', directory, 'kustomization.yaml')))
    assert overlay['resources'] == [f'../../services/{directory}']
    assert os.path.isfile(os.path.join(root, 'services', directory, 'kustomization.yaml'))
    assert not os.path.exists(os.path.join(root, 'services', directory, 'e2e-stripe'))
    patch = yaml.safe_load(overlay['patches'][0]['patch'])
    assert patch['metadata']['name'] == name
    assert set(patch['data']) == keys
print('overlay assertions ok')
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"overlay assertions ok"* ]]
}
