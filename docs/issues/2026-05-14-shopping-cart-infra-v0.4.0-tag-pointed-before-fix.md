# shopping-cart-infra v0.4.0 tag pointed before the Keycloak fix

## What I checked
- `git -C /Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-infra show -s --format='%h %D %s' v0.4.0`
- `git -C /Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-infra log --oneline --decorate=short --max-count=4 shopping-cart-infra-v0.4.0`

## Actual output
```text
128ab3f tag: v0.4.0 docs: add v0.4.0 bugfix note to README
```

```text
674b7b1 (HEAD -> shopping-cart-infra-v0.4.0, origin/shopping-cart-infra-v0.4.0) docs: consolidate v0.4.0 release notes
2e97ec6 docs: add v0.4.0 release note
d2d6dba fix(keycloak): guard realm precheck on fresh db
272f5d2 fix(keycloak): wrap realm import render sed
```

## Root cause
- The `v0.4.0` tag was still pointing at `128ab3f`, which predates the functional Keycloak realm-import fix.
- The fix itself was already present on the `shopping-cart-infra-v0.4.0` branch, but the release tag did not include the final release-branch tip.

## Follow-up
- Retag `v0.4.0` to the release-branch tip that includes the fix and the release-note consolidation.
