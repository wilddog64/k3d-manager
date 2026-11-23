#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../python_yaml.bash"
  manifest="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/services-git.yaml"
  python="$(k3dm_python_yaml)"
}

@test "the services matrix joins the pin file and preserves the application source and destination" {
  "$python" - "$manifest" <<'PY'
import sys, yaml
s = yaml.safe_load(open(sys.argv[1]))['spec']
assert any(x.get('name') == 'payment-db-credentials' for x in s['template']['spec']['ignoreDifferences'])
assert 'ignoreApplicationDifferences' not in s
repo = 'https://github.com/wilddog64/k3d-manager'
clusters, dirs = s['generators'][0]['matrix']['generators']
assert clusters == {'clusters': {'selector': {'matchLabels': {'k3d-manager/role': 'app-cluster', 'k3d-manager/shopping-cart': 'true'}}}}
assert s['syncPolicy'] == {'applicationsSync': 'create-update', 'preserveResourcesOnDeletion': True}
directories, pins = dirs['matrix']['generators']
assert directories['git'] == dict(repoURL=repo, revision='${K3D_MANAGER_BRANCH}', directories=[{'path':'services/*'}, {'path':'services/shopping-cart-identity','exclude':True}])
assert pins['git'] == dict(repoURL=repo, revision='cve-pins/hub', pathParamPrefix='cvePinsFile', files=[{'path':'pins.json'}])
assert pins['selector'] == {'matchExpressions': [
    {'key':'name','operator':'DoesNotExist'},
    {'key':'nameNormalized','operator':'DoesNotExist'},
    {'key':'server','operator':'DoesNotExist'},
    {'key':'project','operator':'DoesNotExist'},
    {'key':'path.path','operator':'DoesNotExist'},
    {'key':'path.basename','operator':'DoesNotExist'},
    {'key':'metadata.labels.k3dm.k3d.io/e2e-profile','operator':'DoesNotExist'},
]}
app = s['template']['spec']
assert app['source']['repoURL'] == repo and 'sources' not in app
assert app['source']['targetRevision'] == '${K3D_MANAGER_BRANCH}'
assert app['destination'] == {'name':'{{.name}}', 'namespace':'shopping-cart-apps'}
assert s['template']['metadata']['name'] == '{{.name}}-{{.path.basename}}'
patch = s['templatePatch']
assert '{{- $pins := index . "cvePins" }}' in patch
assert 'kindIs "map" $pins' in patch and 'kindIs "map" $pin' in patch
assert 'regexMatch "^sha256:[0-9a-f]{64}$" (toString (index $pin "digest"))' in patch
assert patch.count('images:') == 1
PY
}

@test "malformed pin parameter shapes render no patch successfully" {
  export GOCACHE="${BATS_SUITE_TMPDIR}/go-cache"
  "$python" - "$manifest" "${BATS_TEST_TMPDIR}/patch" "${BATS_TEST_DIRNAME}/../fixtures/cve-pin-render/main.go" <<'PY'
import json, subprocess, sys, yaml
manifest, path, fixture = sys.argv[1:]
open(path, 'w').write(yaml.safe_load(open(manifest))['spec']['templatePatch'])
service = 'shopping-cart-frontend'
shapes = [{}, {'v': 1}, {'cvePins': None}, {'cvePins': 'oops'}, {'cvePins': []}, {'cvePins': 7}, {'cvePins': {service: 'not-a-map'}}]
for params in shapes:
    params['path'] = {'basename': service}
    result = subprocess.run(['go', 'run', fixture, path], input=json.dumps(params), text=True, capture_output=True)
    assert result.returncode == 0, (params, result.stderr)
    assert result.stdout == '', (params, result.stdout)
PY
}

@test "the actual patch renders only valid digests under the directory's image name" {
  export GOCACHE="${BATS_SUITE_TMPDIR}/go-cache"
  "$python" - "$manifest" "${BATS_TEST_TMPDIR}/patch" "${BATS_TEST_DIRNAME}/../fixtures/cve-pin-render/main.go" <<'PY'
import json, subprocess, sys, yaml
manifest, path, fixture = sys.argv[1:]
open(path, 'w').write(yaml.safe_load(open(manifest))['spec']['templatePatch'])
app = 'shopping-cart-frontend'
digest = 'sha256:' + 'a'*64
def render(service, pins):
    data = json.dumps({'path': {'basename':service}, 'cvePins':pins})
    return yaml.safe_load(subprocess.check_output(['go','run',fixture,path],input=data,text=True))
expected = {'spec':{'source':{'kustomize':{'images':['ghcr.io/wilddog64/'+app+'@'+digest]}}}}
assert render(app,{app:{'digest':digest}}) == expected
assert render(app,{app:{'digest':digest,'image':'ghcr.io/attacker/x'}}) == expected
assert render('shopping-cart-basket',{app:{'digest':digest}}) is None
assert render(app,{}) is None
for bad in ['sha256:feedbeef', 'sha256:'+'A'*64, digest+'\n- evil']:
    assert render(app,{app:{'digest':bad}}) is None
PY
}

@test "deploy loop applies other sets even when the pin lookup fails" {
  source <(sed -n '/^function _argocd_services_pin_guard()/,/^}/p' "$BATS_TEST_DIRNAME/../../plugins/argocd.sh")
  source <(sed -n '/^function _argocd_deploy_applicationsets()/,/^}/p' "$BATS_TEST_DIRNAME/../../plugins/argocd.sh")
  ARGOCD_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
  mkdir -p "$ARGOCD_CONFIG_DIR/applicationsets"
  local log="$BATS_TEST_TMPDIR/applied" rc
  for name in services-git data-git; do echo "$name" >"$ARGOCD_CONFIG_DIR/applicationsets/$name.yaml"; done
  _argocd_appset_in_stage() { :; }
  _argocd_retire_legacy_observability_acg_apps() { :; }
  _argocd_appset_live_overrides() { :; }
  _info() { :; }
  _warn() { echo "$*"; }
  _err() { echo "$*"; }
  _kubectl() { [[ "$*" = 'apply -f -' ]] && cat >> "$log"; }
  _run_command() {
    [[ "$*" = '--soft -- git ls-remote --exit-code https://github.com/wilddog64/k3d-manager refs/heads/cve-pins/hub' ]] || return 99
    [ "${GIT_TERMINAL_PROMPT:-}" = 0 ] || return 98
    return "$rc"
  }
  for rc in 0 2 128; do
    : >"$log"
    run _argocd_deploy_applicationsets all prepared
    grep -qx data-git "$log"
    if (( rc == 0 )); then
      [ "$status" = 0 ]; grep -qx services-git "$log"
    else
      [ "$status" = 1 ]
      if (( rc == 2 )); then
        [[ "$output" == *"pin branch cve-pins/hub not found (exit 2)"* ]]
      else
        [[ "$output" == *"pin branch lookup failed (rc $rc)"* ]]
      fi
      [ "$(cat "$log")" = data-git ]
    fi
  done
}

@test "cutover instructions cover the manual entry point completeness and residuals" {
  local docs="$BATS_TEST_DIRNAME/../../../docs"
  local guide="$docs/architecture/cve-remediation-pipeline.md"
  grep -Fx '## Pin branch' "$guide"
  grep -F 'Cut over manually' "$guide"
  grep -F 'PINSYNC: complete pins=<n> live_overrides=<m> incomplete=0' "$guide"
  for n in 1 2 3 4 5; do grep -F "R2e-$n" "$guide"; done
  grep -F 'services-git' "$docs/howto/image-signing.md"
  run grep -Ei 'patch argo cd application|pins that digest into the ArgoCD Application' "$guide" "$docs/howto/image-signing.md"
  [ "$status" = 1 ]
}
