# Slack command help is inconsistent and grammar-heavy

## Status

Fixed on `k3d-manager-v1.42.0`.

## Finding

After reviewing the `/cluster-diagnose` help problem, the other long Slack errors
used compressed grammar strings or a terse usage line. This made cluster lifecycle,
cleanup, `/ask-docs`, `/k3dm`, and ArgoCD upgrade commands harder to discover.

## Fix

Use short, example-based help for the long command surfaces. Keep the syntax concise,
show the valid choices explicitly, and include one safe example. Existing command
semantics and validation remain unchanged.

## Verification

- Relay tests cover representative help for cluster-up, cluster-resume,
  cleanup, ask-docs, and ArgoCD upgrade.
- Existing Slack-command documentation tests remain green.

The initial verification caught and corrected a JavaScript template-literal quoting
error in the ArgoCD stage message before deployment. The corrected syntax check and
test results are recorded by the implementation handoff.

The standardized help was deployed with `make deploy-worker`; Wrangler reported Worker
version `1c21d3e7-1e39-4dfc-aeee-b16f5b326233`, and the repository smoke check completed
successfully.
