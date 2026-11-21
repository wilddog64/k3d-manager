#!/usr/bin/env bats
setup() {
  source <(sed '/^_load_access$/,$d' "$BATS_TEST_DIRNAME/../../etc/argocd/platform-ops/cve-remediation-verify.sh")
  log="$BATS_TEST_TMPDIR/patches"
  [[ "$log" == "$BATS_TEST_TMPDIR/patches" ]]
  sync='Synced|Healthy'; ready=1; image=repo@old; minimum=10
  _hub() {
    case "$*" in
      *'patch configmap'*) echo "$*" >>"$log";;
      *'.data.state}'*) echo promotion_requested;;
      *'.data.service}'*) echo shopping-cart-frontend;;
      *'.data.to_digest}'*) echo sha256:fixture;;
      *'.data.created_at}'*) echo 2024-02-29T00:00:00Z;;
      *'.status.sync.status}'*) echo "$sync";;
      *) return 1;;
    esac
  }
  _app() {
    case "$*" in
      *'.spec.minReadySeconds}'*) echo "$minimum";;
      *'.status.readyReplicas}'*) echo "$ready";;
      *'containers[0].image}'*) echo "$image";;
      *) echo 1;;
    esac
  }
}
@test "convergence failures stay pending until the bounded interval expires" {
  for reason in deployment_digest_mismatch deployment_not_fully_ready argocd_not_synced_or_healthy; do
    case "$reason" in deployment_not_fully_ready) ready=0;; argocd_not_synced_or_healthy) sync=Progressing;; esac
    : >"$log"
    VERIFY_NOW=1709165100 run _verify_event example
    [ "$status" = 0 ]; [[ "$output" == "pending example $reason" ]]; [ ! -s "$log" ]
    VERIFY_NOW=1709166100 run _verify_event example
    [ "$status" = 0 ]; grep -F "\"state\":\"failed\"" "$log"; grep -F "$reason" "$log"
  done
}
@test "a converged pin is applied immediately and manual review is immediate" {
  image=repo@sha256:fixture
  VERIFY_NOW=1709165100 _verify_event example
  grep -F verified_synced_healthy_digest "$log"
  minimum=0
  VERIFY_NOW=1709165100 _verify_event example
  grep -F min_ready_seconds_not_configured "$log"
}
