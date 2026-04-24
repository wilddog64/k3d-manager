# Verification Issue: ArgoCD plugin pre-existing shellcheck and BATS failures

**Date:** 2026-04-24
**Task:** `docs/bugs/2026-04-24-argocd-ldap-namespace-hardcoded.md`
**Commit pushed:** `032bfadb`
**Status:** OPEN — reproduced again during `docs/bugs/2026-04-24-argocd-ldap-vars-not-sourced.md` verification (`1c3ead28`)

## What was tested / attempted

During the LDAP namespace hardcoded bug fix, the required pre-edit and post-edit checks were run against `scripts/plugins/argocd.sh`, plus the targeted ArgoCD plugin BATS suites and the curated full test bundle.

The code change itself was limited to:

```bash
if ! _kubectl get ns "${LDAP_NAMESPACE:-ldap}" >/dev/null 2>&1; then
```

## Actual output

Pre-edit and post-edit `shellcheck -x scripts/plugins/argocd.sh` both reported the same existing findings during the namespace hardcoded fix. The LDAP vars fix added seven lines near the top of `argocd.sh`, so the same findings now appear at shifted line numbers:

```text
In scripts/plugins/argocd.sh line 113:
   deploy_argocd_bootstrap
   ^---------------------^ SC2119 (info): Use deploy_argocd_bootstrap "$@" if function's $1 should mean script's $1.


In scripts/plugins/argocd.sh line 634:
function deploy_argocd_bootstrap() {
^-- SC2120 (warning): deploy_argocd_bootstrap references arguments, but none are ever passed.

For more information:
  https://www.shellcheck.net/wiki/SC2120 -- deploy_argocd_bootstrap reference...
  https://www.shellcheck.net/wiki/SC2119 -- Use deploy_argocd_bootstrap "$@" ...
```

Targeted BATS:

```text
1..14
not ok 1 deploy_argocd --help shows usage
# (in test file scripts/tests/plugins/argocd.bats, line 12)
#   `[[ "$output" == *"Usage: deploy_argocd"* ]]' failed
ok 2 deploy_argocd skips when CLUSTER_ROLE=app
ok 3 deploy_argocd_bootstrap --help shows usage
ok 4 deploy_argocd_bootstrap no-ops when skipping all resources
ok 5 _argocd_deploy_appproject fails when template missing
ok 6 ARGOCD_NAMESPACE defaults to cicd
ok 7 _argocd_deploy_key_policy_hcl includes deploy key paths
ok 8 _argocd_deploy_key_policy_hcl uses read capability
ok 9 _argocd_deploy_key_policy_hcl avoids write/delete
ok 10 configure_vault_argocd_repos errors when namespace missing
ok 11 configure_vault_argocd_repos errors when ESO CRDs missing
ok 12 configure_vault_argocd_repos --dry-run makes no kubectl calls
ok 13 configure_vault_argocd_repos --seed-vault writes placeholders
ok 14 configure_vault_argocd_repos --dry-run --seed-vault prints actions only
```

Full curated BATS:

```text
1..283
not ok 172 deploy_argocd --help shows usage
# (in test file scripts/tests/plugins/argocd.bats, line 12)
#   `[[ "$output" == *"Usage: deploy_argocd"* ]]' failed
Test log saved to scratch/test-logs/all/20260424-105749.log
Collected artifacts in scratch/test-logs/all/20260424-105749
```

Current full curated BATS during LDAP vars fix verification:

```text
1..283
not ok 172 deploy_argocd --help shows usage
# (in test file scripts/tests/plugins/argocd.bats, line 12)
#   `[[ "$output" == *"Usage: deploy_argocd"* ]]' failed
Test log saved to scratch/test-logs/all/20260424-131334.log
Collected artifacts in scratch/test-logs/all/20260424-131334
```

Current full curated BATS during ESO webhook readiness verification:

```text
1..283
not ok 172 deploy_argocd --help shows usage
# (in test file scripts/tests/plugins/argocd.bats, line 12)
#   `[[ "$output" == *"Usage: deploy_argocd"* ]]' failed
Test log saved to scratch/test-logs/all/20260424-141536.log
Collected artifacts in scratch/test-logs/all/20260424-141536
```

`_agent_lint` and `_agent_audit` both exited 0:

```text
running under bash version 5.3.9(1)-release
```

## Root cause if known

The shellcheck findings are unrelated to the LDAP namespace line. They come from `deploy_argocd` calling `deploy_argocd_bootstrap` without forwarding arguments while `deploy_argocd_bootstrap` references `$1`.

The BATS failure appears to be unrelated to the LDAP namespace fix. `deploy_argocd --help` currently returns successfully but only contains placeholder help text:

```bash
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
   # ... help text ...
   return 0
fi
```

The test expects output containing `Usage: deploy_argocd`.

## Recommended follow-up

Create a focused follow-up bug for `deploy_argocd --help` and the bootstrap argument-forwarding shellcheck findings. Keep it separate from the LDAP namespace fix because the bug spec explicitly allowed only the namespace dependency check change.
