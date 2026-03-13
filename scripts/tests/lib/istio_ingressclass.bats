#!/usr/bin/env bats

@test "istio-ingressclass manifest exists" {
  [ -f "${BATS_TEST_DIRNAME}/../../etc/istio-ingressclass.yaml" ]
}

@test "istio-ingressclass has the correct kind" {
  grep -q '^kind: IngressClass$' "${BATS_TEST_DIRNAME}/../../etc/istio-ingressclass.yaml"
}

@test "istio-ingressclass has the correct name" {
  grep -q '^  name: istio$' "${BATS_TEST_DIRNAME}/../../etc/istio-ingressclass.yaml"
}

@test "istio-ingressclass has the correct controller" {
  grep -q '^  controller: istio.io/ingress-controller$' "${BATS_TEST_DIRNAME}/../../etc/istio-ingressclass.yaml"
}
