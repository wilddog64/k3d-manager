# Stripe checkout live acceptance — order runtime mismatch

## Finding

The live `order-service` image was built from the Java root `Dockerfile`, while the
payment-aware `POST /api/orders/checkout` implementation exists in `go/cmd/server`.
An authenticated checkout request therefore reached the Java service and returned
`405 Method Not Allowed` (`Request method 'POST' is not supported`). Keycloak token
issuance, the basket request, and Stripe configuration were working.

## Fix shipped

- The reusable image workflow now accepts optional Docker `context` and `dockerfile`
  inputs while preserving the existing defaults.
- Order CI selects `go/Dockerfile` with `go` as the build context.
- The order-service kustomization supplies the Go runtime's basket, payment, and
  Stripe gateway settings.

## Verification

- Go `gofmt`, `go vet ./...`, and `go test ./...` pass with an isolated cache.
- The source branches are pushed, but live rollout remains pending the two PRs being
  merged and the resulting image-promotion workflow completing.

## Follow-up

After promotion, verify both the Stripe happy path and declined-card path against
`/api/orders/checkout`, then confirm the order Deployment is running the promoted
Go image digest.
