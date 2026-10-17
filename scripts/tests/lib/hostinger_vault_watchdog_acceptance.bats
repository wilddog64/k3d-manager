#!/usr/bin/env bats

REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"

setup() {
  export SCRIPT_DIR="$REPO/scripts"
  export PLUGINS_DIR="$SCRIPT_DIR/plugins"
  VAULT_SH="${VAULT_SH:-$SCRIPT_DIR/plugins/vault.sh}"
  ARGOCD_SH="${ARGOCD_SH:-$SCRIPT_DIR/plugins/argocd.sh}"
  HOSTINGER_SH="${HOSTINGER_SH:-$SCRIPT_DIR/lib/providers/k3s-hostinger.sh}"
  CALLS="$BATS_TEST_TMPDIR/calls.log"
  : > "$CALLS"
  GUARD="$BATS_TEST_TMPDIR/guard"
  mkdir -p "$GUARD"
  printf '#!/bin/sh\necho "REAL KUBECTL INVOKED" >&2\nexit 99\n' > "$GUARD/kubectl"
  chmod +x "$GUARD/kubectl"
  export PATH="$GUARD:$PATH"
  export UNSEAL_SENTINEL="SENTINEL-UNSEAL-KEY-c0ffee1234"
  export HUB_IMG="hashicorp/vault:HUBIMG"
  export TGT_IMG="hashicorp/vault:TARGETIMG"
  export APPLIED_DIR="$BATS_TEST_TMPDIR/applied"
  mkdir -p "$APPLIED_DIR"
  source "$SCRIPT_DIR/lib/system.sh"
  source "$SCRIPT_DIR/lib/provider.sh"
  source "$SCRIPT_DIR/lib/core.sh"
}

install_kube_stubs() {
  _stub_kube() {
    local kind="$1"; shift
    printf '%s %s\n' "$kind" "$*" >> "$CALLS"
    local a="$*" ctx=""
    case "$a" in *"--context ubuntu-hostinger"*) ctx=tgt;; esac
    if [[ "$a" == *"get statefulset"* ]]; then
      if [[ "$ctx" == tgt ]]; then printf '%s' "$TGT_IMG"; else printf '%s' "$HUB_IMG"; fi
      return 0
    fi
    if [[ "$a" == *"get secret"* ]]; then
      printf '{"data":{"shard":"%s"}}' "$UNSEAL_SENTINEL"; return 0
    fi
    if [[ "$a" == *"apply"* ]]; then
      local prev="" f=""
      for t in "$@"; do [[ "$prev" == "-f" ]] && f="$t"; prev="$t"; done
      if [[ -n "$f" && -f "$f" ]]; then cp "$f" "$APPLIED_DIR/applied-$kind-${ctx:-none}.yaml"; fi
      return 0
    fi
    return 0
  }
  kubectl() { _stub_kube kubectl "$@"; }
  _kubectl() { _stub_kube _kubectl "$@"; }
  export -f _stub_kube kubectl _kubectl
}

load_vault() {
  install_kube_stubs
  # shellcheck disable=SC1090
  source "$VAULT_SH"
  install_kube_stubs
}

load_hostinger() {
  load_vault
  # shellcheck disable=SC1090
  source "$HOSTINGER_SH"
  install_kube_stubs
  export HOSTINGER_HOST=203.0.113.9
  : > "$BATS_TEST_TMPDIR/kc"
  _HOSTINGER_KUBECONFIG="$BATS_TEST_TMPDIR/kc"
  _hostinger_require_host() { echo 203.0.113.9; }
  _hostinger_merge_kubeconfig() { :; }
  _hostinger_register_cluster() { :; }
  _hostinger_reapply_gitops_applicationsets() { :; }
  _hostinger_clear_stale_platform_tracking_ids() { :; }
  _hostinger_reconcile_vault_cluster_store() { :; }
  _hostinger_refresh_frontend_dns() { :; }
  _hostinger_refresh_access_layer() { :; }
  deploy_observability_acg() { :; }
  _acg_record_provider() { :; }
}

@test "M2: refresh path installs the watchdog on ubuntu-hostinger in the Vault namespace" {
  load_hostinger
  run _provider_k3s_hostinger_refresh_cluster
  echo "$output"
  [ "$status" -eq 0 ]
  ls "$APPLIED_DIR"
  applied="$(cat "$APPLIED_DIR"/applied-*-tgt.yaml)"
  [[ "$applied" == *"vault-unseal-watchdog"* ]] || false
  [[ "$applied" == *"namespace: secrets"* ]] || false
  grep -q -- "apply --context ubuntu-hostinger" "$CALLS" || grep -q "ubuntu-hostinger.*apply" "$CALLS"
}

@test "M3: watchdog image comes from the target context's Vault StatefulSet" {
  load_vault
  run vault_install_unseal_watchdog secrets ubuntu-hostinger
  echo "$output"
  [ "$status" -eq 0 ]
  applied="$(cat "$APPLIED_DIR"/*.yaml)"
  [[ "$applied" == *"TARGETIMG"* ]] || false
  [[ "$applied" != *"HUBIMG"* ]] || false
}

@test "N1: every kubectl/_kubectl call of the install carries the given --context" {
  load_vault
  run vault_install_unseal_watchdog secrets ubuntu-hostinger
  echo "$output"
  [ "$status" -eq 0 ]
  [ -s "$CALLS" ]
  cat "$CALLS"
  bad=0
  while IFS= read -r line; do
    [[ "$line" == *"--context ubuntu-hostinger"* ]] || bad=$((bad+1))
  done < "$CALLS"
  [ "$bad" -eq 0 ]
  [[ "$output" != *"REAL KUBECTL INVOKED"* ]] || false
}

@test "N1b: the refresh path never touches any other context" {
  load_hostinger
  run _provider_k3s_hostinger_refresh_cluster
  [ "$status" -eq 0 ]
  bad=0
  while IFS= read -r line; do
    [[ "$line" == *"--context ubuntu-hostinger"* ]] || bad=$((bad+1))
  done < "$CALLS"
  [ "$bad" -eq 0 ]
}

@test "N2: no unseal key material is printed" {
  load_hostinger
  export VAULT_UNSEAL_SHARD="$UNSEAL_SENTINEL"
  run _provider_k3s_hostinger_refresh_cluster
  echo "$output"
  [[ "$output" != *"$UNSEAL_SENTINEL"* ]] || false
  run vault_install_unseal_watchdog secrets ubuntu-hostinger
  [[ "$output" != *"$UNSEAL_SENTINEL"* ]] || false
  run vault_install_unseal_watchdog secrets
  [[ "$output" != *"$UNSEAL_SENTINEL"* ]] || false
}

@test "N2b: kubectl calls do not read the unseal secret data" {
  load_vault
  run vault_install_unseal_watchdog secrets ubuntu-hostinger
  [ "$status" -eq 0 ]
  ! grep -q "get secret" "$CALLS" || false
}

apps_json() {
  cat <<JSON
{"items":[
 {"metadata":{"name":"app-stale","ownerReferences":[{"kind":"ApplicationSet","name":"owner1"}]},
  "spec":{"source":{"repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"old-branch"}},
  "status":{"health":{"status":"Healthy"}}},
 {"metadata":{"name":"app-degraded","ownerReferences":[{"kind":"ApplicationSet","name":"owner1"}]},
  "spec":{"source":{"repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"want-branch"}},
  "status":{"health":{"status":"Degraded"}}},
 {"metadata":{"name":"app-fine","ownerReferences":[{"kind":"ApplicationSet","name":"owner1"}]},
  "spec":{"source":{"repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"want-branch"}},
  "status":{"health":{"status":"Healthy"}}}
]}
JSON
}

load_argocd() {
  # shellcheck disable=SC1090
  source "$ARGOCD_SH"
  APPS="$(apps_json)"
  _kubectl() { printf '%s\n' "$*" >> "$CALLS"; printf '%s' "$APPS"; }
  kubectl() { echo "REAL KUBECTL" >&2; return 99; }
}

section() {
  # print lines after the heading matching $1 until the next "[argocd]" line
  printf '%s\n' "$output" | awk -v h="$1" '/\[argocd\]/ {f=0} /\[argocd\]/ && index($0,h){f=1; next} f'
}

@test "M4: Degraded app on expected branch is reported under a health heading" {
  load_argocd
  run argocd_check_values_branch want-branch ctx-x owner1
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"app-stale"* ]] || false
  health="$(section "Degraded")"
  [[ "$health" == *"app-degraded"* ]] || false
  [[ "$health" != *"app-stale"* ]] || false
}

@test "N3: app on the expected branch is never listed under the stale values branch heading" {
  load_argocd
  run argocd_check_values_branch want-branch ctx-x owner1
  echo "$output"
  [[ "$output" == *"stale values branch"* ]] || false
  stale="$(section "stale values branch")"
  [[ "$stale" == *"app-stale"* ]] || false
  [[ "$stale" != *"app-degraded"* ]] || false
  [[ "$stale" != *"app-fine"* ]] || false
  [[ "$output" == *"Degraded"* ]] || false
}

@test "N3b: only a Degraded app on expected branch -> no stale heading at all" {
  load_argocd
  APPS="$(apps_json | sed 's/old-branch/want-branch/')"
  run argocd_check_values_branch want-branch ctx-x owner1
  echo "$output"
  [[ "$output" != *"on a stale values branch"* ]] || false
  [[ "$output" == *"app-degraded"* ]] || false
}
