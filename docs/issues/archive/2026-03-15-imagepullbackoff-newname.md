# Issue: ImagePullBackOff due to missing `newName`

## Summary
Kustomization manifests in the service repos pointed to bare image names. GitHub Actions only updated `newTag`, so the cluster kept pulling from Docker Hub and failed. Added `newName: ghcr.io/wilddog64/<svc>` blocks to each repo:

| Repo | Commit | Notes |
|---|---|---|
| shopping-cart-basket | `c1f665caec01f7cceb1413bf7e8da788f05a34f7` | existing SHA preserved |
| shopping-cart-product-catalog | `696db952d3351b8c817f2d9f684cd81ad596bb65` | placeholder `latest` until CI refresh |
| shopping-cart-order | `7695a90fad230e3f7146e453dd09be305149d0a9` | placeholder `latest` |
| shopping-cart-payment | `51ec199cb03c34f99d20b3186171e45d558ffa69` | source image `ghcr.io/your-org/payment-service`; kustomize now rewrites to ghcr target |
| shopping-cart-frontend | `3a9140d28782011211caaf5c6f399fd4934353df` | existing `latest` tag retained |

## Verification
- `kubectl kustomize k8s/base | grep image:` in each repo → fully-qualified GHCR references
- `gh api /users/wilddog64/packages/container/shopping-cart-basket/versions --jq '.[0].metadata.container.tags'` shows `latest` and `sha-d351...` tags
- Other service packages currently return 404 (not pushed yet) — trigger CI build after merges

## Next Steps
- Merge PRs for each repo and let CI publish images
- Re-run ArgoCD sync; expect ImagePullBackOff resolved once GHCR images exist
