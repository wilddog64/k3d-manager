# Order service (Go) cannot start against a fresh database

## Finding

The Go order service (`shopping-cart-order`, image
`sha-56033880a16e77ad5df0752eac8ad1c00c4a258a`) ships **no runtime schema migration**.
Its schema (`V1__init_schema.sql`) exists only under
`go/internal/order/testdata/`, applied solely by `store_integration_test.go`. `main.go`
runs no migrate step. Deployed against an empty database the `orders`/`order_items`
tables never exist, and every order operation returns
`HTTP 500 {"code":"INTERNAL_ERROR"}` with
`relation "orders" does not exist (SQLSTATE 42P01)`.

Discovered while root-causing the Tier-1 E2E gate — see
`k3d-manager/docs/bugs/2026-08-29-e2e-order-schema-missing.md`. The Tier-1 substrate was
stopgapped by provisioning the schema in postgres initdb; this issue tracks the durable
service-side fix.

## Proposed fix (service repo — spec-not-direct, branch/PR)

1. Move/embed the migration out of `testdata/` into a first-class `migrations/` dir and
   `//go:embed` it.
2. Apply migrations on startup in `main.go` (idempotent; `CREATE TABLE IF NOT EXISTS` is
   already in the DDL), before serving.
3. Rebuild + publish the order image; bump `scripts/etc/e2e/kustomization.yaml`
   `newTag` to the new digest and drop the substrate stopgap once verified.

## Notes

- The Java Spring Boot tree still exists in the repo, but the **deployed** image is the Go
  rewrite. Confirm which build is canonical before wiring migrations, so the fix lands in
  the served path.
