# Progress: shopping-cart-infra

## Infrastructure Stages

| Stage | Description | Status |
|---|---|---|
| 1 | RabbitMQ StatefulSet deployment | ✅ Complete |
| 2 | Vault integration for RabbitMQ dynamic credentials | ✅ Complete |
| 3 | Python client library | ✅ Complete (rabbitmq-client-python repo) |
| 3 | Go client library | ✅ Complete (rabbitmq-client-go repo) |
| 3 | Java client library | ✅ Complete (rabbitmq-client-java repo) |
| 4 | Monitoring & production readiness | ⏳ In Progress (observability-stack repo) |

## Built

### Data Layer
- [x] Namespace definitions (`shopping-cart-data`, `shopping-cart-apps`)
- [x] PostgreSQL StatefulSet: products (with init SQL schema)
- [x] PostgreSQL StatefulSet: orders (with init SQL schema)
- [ ] order-service schema: add cancellation_reason column to orders table 

- [x] Redis StatefulSet: cart session storage
- [x] Redis StatefulSet: orders-cache
- [x] RabbitMQ StatefulSet with management UI + Prometheus plugin
- [x] ExternalSecrets for all components (Vault → K8s Secrets)
- [x] RabbitMQ default credentials sourced from Vault (`d356490` — branch `fix/app-namespace-secrets`, spec `docs/plans/v0.2.1-bugfix-rabbitmq-vault-creds.md`)
- [x] ArgoCD sync waves + ESO health check + ddl-auto=create (`3b8b13b` — branch `fix/argocd-sync-waves-ddl-auto`, spec `docs/plans/v0.2.2-fix-argocd-sync-waves-ddl-auto.md`) — PR merged `e95b31a` 2026-04-05
- [x] `rabbitmq-management` Service LoadBalancer → ClusterIP (`dfc949d` — PR #27 merged 2026-04-05) — fixes ArgoCD wave 1 block on k3s
- [x] Vault database secrets engine configuration script

### Application Services (Helm Chart)
- [x] Helm chart structure (`chart/`)
- [x] product-catalog templates (Python/FastAPI)
- [x] cart/basket templates (Go/Gin)
- [x] order templates (Java/Spring Boot)
- [x] frontend templates (React/nginx)
- [x] Demo values (`values.yaml`, 8GB constraints)
- [x] Production values (`values-prod.yaml`)
- [x] Dev values (`values-dev.yaml`, updated by CI)

### Argo CD GitOps
- [x] AppProject (`shopping-cart`)
- [x] Application: shopping-cart-infrastructure (data layer)
- [x] Application: shopping-cart-dev (app layer, auto-sync)
- [x] Application: shopping-cart-prod (app layer, manual sync)

### Identity Stack
- [x] Keycloak deployment in `identity` namespace
- [x] OpenLDAP deployment
- [x] Realm `shopping-cart` with `frontend` client

### CI/CD
- [x] `bin/build-and-push.sh` — Build/push images to GHCR
- [x] `bin/setup-service-repo.sh` — Automate new service repo creation
- [x] `bin/deploy-infra.sh` — Deploy full infrastructure stack
- [x] `examples/dockerfiles/` — Dockerfile templates for all service types
- [x] `examples/github-actions/` — GitHub Actions workflow templates

### Documentation
- [x] `docs/cicd-architecture.md`
- [x] `docs/container-image-workflow.md`
- [x] `docs/github-actions-webhook-setup.md`
- [x] `docs/message-schemas.md`
- [x] `docs/rabbitmq-client-library-design.md`
- [x] `docs/rabbitmq-operations.md`
- [x] `docs/rabbitmq-load-testing.md`
- [x] `docs/vault-usage-guide.md`
- [x] `docs/vault-password-rotation.md`
- [x] `docs/redis-password-rotation.md`
- [x] `docs/plans/message-queue-implementation.md`
- [x] Issue docs: 001 (RabbitMQ NodePort), 002 (Prometheus plugin)

### CI Stabilization (fix/ci-stabilization branch)
- [x] `shopping-cart-frontend`: TypeScript cleanup + `tsconfig` types (`5b69bd0`)
- [x] `shopping-cart-product-catalog`: Dockerfile apt upgrades (`c745bd3`)
- [x] `shopping-cart-payment`: GitHub Actions `./mvnw … -Dmaven.multiModuleProjectDirectory=.` (`7642f06` — local Maven wrapper download timed out)
- [x] `rabbitmq-client-java`: GitHub Packages publish workflow + distributionManagement (`0f1c9b1`)
- [x] `shopping-cart-order`: GitHub Packages repository + Maven settings/workflow update (`75c07bb` — local Maven unavailable)

## Pending

### Multi-arch CI fix (Codex ready)

- [x] `shopping-cart-basket` — `@999f8d7` on main (Codex, 2026-03-18)
- [ ] Update `@8363caf` → `@999f8d7` in remaining 4 app repo CI workflows — spec: `docs/plans/codex-multiarch-workflow-pin.md`
- [ ] PRs open on all 4 remaining repos (`fix/multiarch-workflow-pin`) — CI green before merge
- [ ] Claude merges PRs after CI green
- [ ] CI re-runs on main — pushes `linux/amd64,linux/arm64` images to ghcr.io
- [ ] Gemini re-verifies ArgoCD all 5 apps Synced + pods Running on k3s

### shopping-cart-basket resilience (Codex ready)

- [ ] Redis circuit breaker — `sony/gobreaker` wrapping all 4 repo ops; 503 on open state; `/health/live` reflects circuit state
- Issue spec: `shopping-cart-basket/docs/issues/2026-03-18-redis-circuit-breaker.md`

### v0.9.5 — Service Mesh (next milestone after v0.9.4)

- [ ] `istio/peer-authentication.yaml` — STRICT mTLS mesh-wide
- [ ] `istio/authz-payment.yaml` — deny-all + allow order-service → payment (replaces NetworkPolicy at L7)
- [ ] `istio/gateway.yaml` — Gateway + VirtualService for frontend ingress + API routing
- [ ] `istio/destination-rules.yaml` — LEAST_CONN (order, payment), ROUND_ROBIN (basket, catalog, frontend)
- [ ] `istio/service-entries.yaml` — Stripe + PayPal registered as MESH_EXTERNAL
- [ ] `docs/service-mesh.md` — **operational doc** (what's deployed, how to verify mTLS, how to add a new service, troubleshooting)
- Full spec: `k3d-manager/docs/plans/v0.9.5-service-mesh.md`

### Other

- [ ] Stage 4: Observability integration (being done in `observability-stack` repo)
- [ ] Network policies for strict namespace isolation
- [ ] Production promotion runbook
- [ ] RabbitMQ cluster (multi-node) configuration for HA
- [ ] PostgreSQL HA (read replicas)
- [ ] Backup/restore procedures for PostgreSQL and Redis

## Known Issues

| ID | Description | Status |
|---|---|---|
| 001 | RabbitMQ NodePort accessibility in k3d | Documented |
| 002 | RabbitMQ Prometheus plugin configuration | Documented |
| 003 | order-service missing column cancellation_reason | Open | 

