# Live SSO and remote E2E recovery

Date: 2026-09-16. Branch: `k3d-manager-v1.34.0`.

The live investigation found three independent gaps:

1. The Keycloak PostSync hook from shopping-cart-infra was failing because the
   `quay.io/keycloak/keycloak:24.0` image has no `awk`. Its first pass nevertheless
   removed the stray top-level `otp-conditional-subflow`. The live flow now has the
   expected four level-0 executions, and an in-cluster PKCE authorization request
   returned a login form.
2. ArgoCD's `argocd-cm` advertised `https://argocd.shopping-cart.local` while the
   public browser origin is `https://argocd.3ai-talk.org`. The live ConfigMap was
   corrected to the public URL. The server now returns HTTP 303 with a Keycloak
   authorization URL whose callback is `https://argocd.3ai-talk.org/auth/callback`.
3. M2 publish-back was absent from both LaunchAgents. The operator configuration
   was installed at `~/.config/k3d-manager/e2e-remote.env`, and the three retained
   `publication_pending` runs were replayed successfully.

## Evidence

```text
INFO: [e2e-publish] applied result for run 1787838531-2562 (runner=m2, result=fail)
INFO: [e2e-publish] applied result for run 1789481773-13798 (runner=m2, result=fail)
INFO: [e2e-publish] applied result for run 1789549631-2079 (runner=m2, result=fail)
INFO: [e2e-remote] replay complete: published=3 still_pending=0
```

Exporter metrics now include:

```text
e2e_run_info{run_id="1787838531-2562",tier="vcluster",runner="m2",service="product-catalog",project="api+flows",...} 1
e2e_run_info{run_id="1789481773-13798",tier="vcluster",runner="m2",service="product-catalog",project="api+flows",...} 1
e2e_run_info{run_id="1789549631-2079",tier="vcluster",runner="m2",service="product-catalog",project="api+flows",...} 1
e2e_last_run_pass{tier="vcluster",service="product-catalog",project="api+flows",runner="m2"} 0
```

The in-cluster frontend authorization check returned:

```text
HTTP 200 login_form True invalid False sorry False
```

The in-cluster ArgoCD callback check returned:

```text
HTTP 303 LOCATION ...client_id=argocd&redirect_uri=https%3A%2F%2Fargocd.3ai-talk.org%2Fauth%2Fcallback...
```

## Durable changes

The k3d-manager side is in the working tree: `ARGOCD_PUBLIC_URL` is separated from
the internal routing host, Helm receives the public URL, and a regression test covers
the distinction. The shopping-cart-infra durable hook fix is on the pushed branch
`fix/keycloak-hook-runtime-tools` through commit `cb6e414` (the latest follow-up is
`cb6e414`; earlier commits `1976093`, `659ab48`, and `10a821e` are ancestors).

The hook's no-`awk` helper test passes its nine assertions in the Keycloak image when
Docker access is available. The live hook still reports a Keycloak `Resource not found`
response during its flow-execution read and reaches BackoffLimitExceeded, even though
the resulting live flow is correct and both browser authorization checks pass. The
branch must be merged and the hook rerun under normal ArgoCD control before declaring
the PostSync repair durable; this limitation is intentionally recorded rather than
claiming a successful hook.

## Validation

```text
bats scripts/tests/plugins/argocd.bats
1..27
27 passed

shellcheck scripts/plugins/argocd.sh
clean (exit 0)
```

