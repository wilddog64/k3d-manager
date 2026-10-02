# Bug: e2e assertion — api-payments

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-16 by k3dm-hermes
**Status:** OPEN, CONFIRMED (triage by Claude, 2026-10-01) — real: payment `/actuator/health` returns 503 in the e2e substrate. Operator chose (b), a real Keycloak token (2026-10-02); option (b) IMPLEMENTED on feature branches (payment `d2f2d55`, e2e-tests `df6b9c1`, k3d-manager substrate), pending PRs, image pins and a live Tier 1 run. Health fix (substrate broker + `spring.rabbitmq`) IMPLEMENTED: payment `9778e21` + k3d-manager substrate.
**Run:** `1789549631-2079`, runner `m2`, tier `vcluster`, 24 passed / 33 failed / 102 total
**Runner commit:** `ec4874fe62cab1ba120729dc5d48454f7d50dcc7`

## Failing tests (9)
- `api/payments.spec.ts` — should return healthy status
- `api/payments.spec.ts` — should process payment successfully with mock gateway
- `api/payments.spec.ts` — should handle idempotent payment requests
- `api/payments.spec.ts` — should reject duplicate payment for same order
- `api/payments.spec.ts` — should retrieve payment by ID
- `api/payments.spec.ts` — should retrieve payment by order ID
- `api/payments.spec.ts` — should retrieve payments by customer ID
- `api/payments.spec.ts` — should process full refund
- `api/payments.spec.ts` — should process partial refund

## Sample errors
- Error: expect(received).toBe(expected) // Object.is equality / Expected: "UP" / Received: "DOWN"
- SyntaxError: Unexpected end of JSON input

## Triage hint
a behaviour change; read the failing test.

## Next step
A human (or Claude) verifies the root cause, then writes the fix spec here before any code change.

---

## Update 2026-09-24 — ROOT CAUSE FOUND for the health assertion

**Verified by:** Claude, live on `ubuntu-hostinger` (read-only).
**Scope note:** this explains the `Expected: "UP" / Received: "DOWN"` failure. The other
eight failures and the `Unexpected end of JSON input` sample are **not** yet explained —
see "Still unexplained" below. Do not assume one fix closes all nine.

### One sentence

`application.yml` declares the RabbitMQ block at the **top level** (`rabbitmq:`) instead of
under `spring:`, so Spring Boot's `RabbitAutoConfiguration` never binds it, falls back to its
default `localhost:5672`, and the stock `RabbitHealthIndicator` reports `DOWN` — which drags
the aggregate `/actuator/health` to HTTP 503 even though RabbitMQ is healthy and reachable.

### The defect

`shopping-cart-payment/src/main/resources/application.yml:64-70`

```yaml
# RabbitMQ Configuration
rabbitmq:                  # <- column 0: top-level, NOT under spring:
  host: ${RABBITMQ_HOST:rabbitmq.shopping-cart-data.svc.cluster.local}
  port: ${RABBITMQ_PORT:5672}
```

Spring Boot binds `spring.rabbitmq.*`. This block is `rabbitmq.*`. There is no `rabbitmq`
key anywhere under `spring:` in the file, and no `@ConfigurationProperties` class or
`ConnectionFactory`/`CachingConnectionFactory` bean in `src/main/java` that would bind it
manually. So autoconfiguration uses its own defaults.

The Deployment env vars are correct and are **not** the problem — they are being interpolated
into a block that nothing reads:

```
RABBITMQ_HOST = rabbitmq.shopping-cart-data.svc.cluster.local
RABBITMQ_PORT = 5672
```

### Measured evidence (live, 2026-09-24)

| Check | Result |
|---|---|
| `/actuator/health` | **503** `{"status":"DOWN","groups":["liveness","readiness"]}` |
| `/actuator/health/liveness` | `{"status":"UP"}` |
| `/actuator/health/readiness` | `{"status":"UP"}` |
| `/actuator/info` | 200 |
| `/api/v1/payments` (no token) | 401 — app serves correctly |
| Pod | `payment-service-75c8875969-vchns` `1/1 Running` |
| `rabbitmq-0` in `shopping-cart-data` | `1/1 Running`, 30d |
| DNS `rabbitmq.shopping-cart-data.svc.cluster.local` | resolves to `10.43.129.122` |
| `nc -z rabbitmq.shopping-cart-data.svc.cluster.local 5672` **from the payment pod** | `nc_exit=0` — **reachable** |
| `nc -z localhost 5672` from the payment pod | `nc_exit=1` — **refused** |

Pod log, timestamped to the exact second of the probe (the indicator is evaluated per request):

```
2026-09-24 13:10:40.782 [http-nio-8084-exec-6] WARN o.s.b.a.amqp.RabbitHealthIndicator - Rabbit health check failed
org.springframework.amqp.AmqpConnectException: java.net.ConnectException: Connection refused
```

The refusal is against `localhost`, not against the configured host. That is the proof: the
network path to RabbitMQ works, and Spring is not using it.

### Why this hid, and why it is the interesting part

The broken indicator belongs to **neither** the `liveness` nor the `readiness` group. Kubernetes
polls only the groups. So:

- the container stays `Ready` and remains in the Service,
- the ArgoCD Application reports `Healthy`,
- no alert fires anywhere,

while `/actuator/health` — which is exactly what `api/payments.spec.ts` asserts — returns 503.

**The system was fine; the signal was disconnected.** This is the same shape as the Pushgateway
service-name drift (`docs/bugs/2026-06-09-pushgateway-deployment-metrics-gap.md`): a health
surface that nothing watches can be wrong indefinitely.

Environment-independent: because the defect is a YAML key path, Spring targets `localhost:5672`
on **every** substrate. It therefore explains the `DOWN` on the vcluster tier where this run
failed just as well as on hostinger, without needing the vcluster to have a broker at all.
Compare `docs/bugs/2026-09-15-e2e-substrate-missing-payment.md`.

### Blast radius — likely health-only, NOT messaging

No file under `src/main/java` references `rabbit` or `amqp`. The dependency comes from the
custom `wilddog64/rabbitmq-client-java` (`pom.xml:74-78`), which reads the top-level
`rabbitmq.*` block itself and transitively pulls `spring-boot-starter-amqp` — and it is that
starter's autoconfiguration that registers a stock connection factory on `localhost` plus the
health indicator checking it.

So the service most likely publishes correctly through its own client while a health check for
a connection it never uses reports `DOWN`. **This must be confirmed before fixing** — see the
first task below. If the custom client turns out to share the autoconfigured factory, this is a
live messaging outage, not a cosmetic one.

### Proposed fix — NOT YET APPROVED, and shopping-cart is spec-then-Codex

Preferred: nest the block so Spring binds it.

```yaml
spring:
  rabbitmq:
    host: ${RABBITMQ_HOST:rabbitmq.shopping-cart-data.svc.cluster.local}
    port: ${RABBITMQ_PORT:5672}
    virtual-host: ${RABBITMQ_VHOST:/}
    username: ${RABBITMQ_USERNAME:guest}
    password: ${RABBITMQ_PASSWORD:guest}
```

Note `vhost:` becomes `virtual-host:` under Spring's binder. The top-level `rabbitmq.vault.*`
subtree is read by the custom client and must be preserved, so this is a duplication or a
careful split — **not** a straight move. Decide which consumer owns which keys first.

Rejected alternative: disabling `RabbitHealthIndicator` via
`management.health.rabbit.enabled=false`. That would turn the panel green while leaving the
misconfigured connection factory in place — a false green, which is worse than the current
honest red.

### Regression test (the point of the exercise)

A test that asserts `/actuator/health` returns 200 would have caught this. Nothing does today;
the e2e suite caught it only as an opaque string comparison after the fact. Add an assertion that
the aggregate health is `UP`, not merely that the probe groups are.

### Still unexplained — do not close this doc on the health fix alone

- The other **eight** `api/payments.spec.ts` failures (process payment, idempotency, duplicate
  rejection, retrieve by ID / order / customer, full and partial refund). These exercise real
  payment operations and are not obviously downstream of a health indicator.
- `SyntaxError: Unexpected end of JSON input`. The 503 body is valid JSON
  (`{"status":"DOWN","groups":[...]}`), so that sample came from a **different** request
  returning an empty body. Find which.
- Whether the vcluster tier even had a payment substrate for that run.

### Hermes detection gap

Hermes filed this doc from e2e triage, which is the only path that caught it. None of its
sensors (`eso`, `argocd`, `reachability`, `status_checks`, `node_pressure`,
`stale_acg_registration`, `kine`, `alert_delivery`, `ci`, `github_token_expiry`) probe an
application's aggregate `/actuator/health`, and the two that come closest both report green
here by design: `argocd` sees `Healthy`, `node_pressure` sees `1/1 Running`. A sensor that
compares aggregate health against probe-group health would have caught this class on the day
it shipped.

Implemented by `docs/plans/v1.40.0-hermes-app-health-delta-sensor.md` (commit pending verification).

---

## Update 2026-09-29 — the eight `Unexpected end of JSON input` failures explained

**Verified by:** Claude (cloud session), from source only: `shopping-cart-payment@87819d4`,
`shopping-cart-e2e-tests@7601aa1`, and `scripts/etc/e2e/`. No live cluster access. Recurred on
run `1790248982-25275` (runner `m2`, tier `vcluster`) with the same 9 failures.

**Answer to "whether the vcluster tier even had a payment substrate":** yes.
`scripts/etc/e2e/payment.yaml` deploys it and the Job sets `PAYMENT_URL=http://payment.<ns>.svc:8084`.
This run has no `ECONNREFUSED`, so the service is reached.

### Why every non-health request gets an empty body — two independent defects

Each alone is enough to fail all eight tests; both must be fixed.

1. **Path mismatch.** `tests/helpers/api-client.ts` `PaymentClient` calls `/api/payments`,
   `/api/payments/<id>`, `/api/payments?orderId=`, `/api/payments/<id>/refund`. The service maps
   `@RequestMapping("/api/v1/payments")` (`PaymentController.java:21`; the Go rewrite's
   `go/internal/payment/handler.go:21-26` uses `/api/v1/payments` too). No handler exists at
   `/api/payments`.
2. **Auth cannot be switched off.** `SecurityConfig.java` permits only `/actuator/**` and requires
   an authenticated JWT for everything else; controller methods also require a `PAYMENT_*` role via
   `@PreAuthorize`. Nothing in `src/main` reads `OAUTH2_ENABLED`, so the substrate's
   `OAUTH2_ENABLED=false` is inert. The client sends only `X-User-ID` and `X-Correlation-ID` — no
   bearer. Spring Security rejects before routing with **401 and an empty body**, and
   `responseData()` calls `response.json()` unconditionally, which throws
   `SyntaxError: Unexpected end of JSON input`. That is why the sample error hides the status code.

### Health failure on the vcluster tier

Independent of the `spring.rabbitmq` key-path defect above, the e2e substrate deploys **no RabbitMQ
at all**, so even after that fix `RabbitHealthIndicator` reports `DOWN` there and
`/actuator/health` stays 503. The substrate needs a broker, or the health test must assert the
probe groups on this tier. Decide which; do not disable the indicator (rejected above).

### Fix options (operator decision; shopping-cart is spec-then-Codex)

- Paths: change `PaymentClient` to `/api/v1/payments` (test repo), matching both service
  implementations. Do not add an unversioned alias in the service.
- Auth, choose one:
  a. an e2e-only Spring profile in `shopping-cart-payment` that permits the API when
     `OAUTH2_ENABLED=false`, or
  b. the e2e client mints a real token from a substrate Keycloak and sends
     `Authorization: Bearer` with a `PAYMENT_USER` role.
  (a) is cheaper; (b) tests the real security path.
- Test harness: make `responseData()` assert `response.ok()` and include status + body text before
  parsing, so the next failure names its status instead of `Unexpected end of JSON input`.
- Also noted: the substrate pins payment `sha-a672ee42…`; the payment repo's latest image commit is
  `87819d4` (`sha-cced3440…`). Not a cause of these failures.

## Alert 2026-09-29

The operator received `[FIRING] E2EVerificationFailing on hub (3)` (severity `warning`, so email, not
SMS). The rule is `e2e_last_run_pass == 0` for 10 minutes, so it is working as designed: it reports
the failures root-caused above. It clears once the path and auth fixes land and a run passes.

---

## Fix spec — option (b), real Keycloak token (operator decision 2026-10-02)

**Status after this spec:** the eight API failures (paths + auth). The health test
(`should return healthy status`) is **out of scope** here: it still needs the `spring.rabbitmq` key-path fix plus a
broker-or-probe-group decision (see 2026-09-29 above), so `E2EVerificationFailing` does not clear on this fix alone.

### New finding — the payment service cannot authorize any real token (likely production too)

`SecurityConfig.java` uses `.oauth2ResourceServer(oauth2 -> oauth2.jwt())` with **no**
`JwtAuthenticationConverter`. Spring's default maps only the `scope` claim to `SCOPE_*` authorities, so every
`@PreAuthorize("hasAnyRole('PAYMENT_USER', …)")` is false for a Keycloak token, which carries roles in
`realm_access.roles`. Every authenticated payment call returns **403**. `PaymentControllerTest` never saw it:
`@WithMockUser(roles = "PAYMENT_USER")` injects `ROLE_PAYMENT_USER` directly and skips JWT conversion.
`shopping-cart-order` already has the converter (`OAuth2SecurityConfig.KeycloakGrantedAuthoritiesConverter`).
Option (a) would have hidden this; (b) exposes it.

### Repos and branches (already created from `origin/main`; do not switch)

| Repo | Branch |
|---|---|
| `shopping-carts/shopping-cart-payment` | `fix/payment-jwt-keycloak-roles` |
| `shopping-carts/shopping-cart-e2e-tests` | `fix/payment-client-v1-bearer` |
| `k3d-manager` | `k3d-manager-v1.40.0` |

### A. `shopping-cart-payment` — map Keycloak roles

1. New `src/main/java/com/shoppingcart/payment/config/KeycloakGrantedAuthoritiesConverter.java`
   (public class, `Converter<Jwt, Collection<GrantedAuthority>>`). Port the order service's realm-role and
   resource-role extraction: `realm_access.roles` plus every `resource_access.<client>.roles`, each mapped to
   `ROLE_` + `toUpperCase()` with `-` replaced by `_`. **Do not** port the `groups` extraction: a group name must
   not grant a role. A missing or malformed claim yields no authority, never an exception.
2. `SecurityConfig.java`: add a `JwtAuthenticationConverter` bean using that converter, and change
   `.oauth2ResourceServer(oauth2 -> oauth2.jwt())` to
   `.oauth2ResourceServer(oauth2 -> oauth2.jwt(jwt -> jwt.jwtAuthenticationConverter(jwtAuthenticationConverter())))`.
   Change nothing else in the chain (`permitAll` on `/actuator/**`, CSRF, session, `httpBasic`).
3. Tests, new `src/test/java/com/shoppingcart/payment/config/KeycloakGrantedAuthoritiesConverterTest.java`:
   - `realm_access.roles = [PAYMENT_USER, payment-write]` → `ROLE_PAYMENT_USER`, `ROLE_PAYMENT_WRITE`;
   - `resource_access.payment-service.roles = [PAYMENT_READ]` → `ROLE_PAYMENT_READ`;
   - no `realm_access` / no `resource_access` → empty, no exception;
   - `groups = [/PAYMENT_ADMIN]` alone → empty (groups do not grant roles).
4. One `PaymentControllerTest` case that goes **through** the converter: `@Import(SecurityConfig.class)` if needed,
   and `SecurityMockMvcRequestPostProcessors.jwt().jwt(j -> j.claim("realm_access", Map.of("roles", List.of("PAYMENT_USER")))).authorities(new KeycloakGrantedAuthoritiesConverter())`
   on `GET /api/v1/payments/{id}` → not 403. And the same with `roles = [GUEST]` → 403.
5. Gate: `./mvnw -o -q test` (offline; `~/.m2` is populated). If offline resolution fails, say so and stop; do not
   enable network.

### B. `shopping-cart-e2e-tests` — v1 paths, a real bearer, honest failures

1. `tests/helpers/auth.ts`: split the token fetch out of the `OAUTH2_ENABLED` gate:
   - new exported `mintToken(request): Promise<string>` that does the password grant and caches, as today, but
     **throws** `Error("Keycloak token request failed: <status> <body text>")` on a non-2xx response or a missing
     `access_token`;
   - `getAuthToken` keeps its current contract (returns `null` when disabled or on failure) by calling `mintToken`
     inside its existing `try`.
2. `tests/helpers/api-client.ts` `PaymentClient`:
   - paths → `/api/v1/payments`, `/api/v1/payments/${paymentId}`, `/api/v1/payments/order/${orderId}`,
     `/api/v1/payments/customer/${customerId}`, `/api/v1/payments/${paymentId}/refund`;
   - `getHeaders()` becomes `async` and always sends `Authorization: Bearer ${await mintToken(this.request)}` plus
     the existing `X-Correlation-ID`. The service has no unauthenticated mode, so there is no flag. Keep `X-User-ID`.
   - `getPaymentByOrderId`: 404 → `null`; otherwise one `Payment` (the endpoint returns an object, not a list).
   - `checkHealth` unchanged.
3. `responseData()`: if `!response.ok()`, throw
   `Error(\`HTTP ${response.status()} ${response.url()}: ${(await response.text()).slice(0, 500)}\`)` before parsing.
   The `getPaymentByOrderId` 404 is checked before calling it. **Do not** change any other client's call sites;
   if a currently-passing spec relied on parsing a non-2xx body, list it in the report instead of working around it.
4. Gate: `npx tsc --noEmit` clean. Do not run Playwright (no substrate).

### C. `k3d-manager` — substrate Keycloak and Job wiring

1. New `scripts/etc/e2e/keycloak.yaml`: ConfigMap `e2e-keycloak-realm` (key `shopping-cart-realm.json`), Deployment
   `keycloak` and Service `keycloak` (port 8080), labels as the other substrate files.
   - Image `quay.io/keycloak/keycloak:24.0` (the tag the repo already uses). Args `start-dev --import-realm`, realm
     mounted at `/opt/keycloak/data/import`.
   - Env: `KC_HOSTNAME_URL=http://keycloak:8080` (fixes the token `iss` regardless of caller), `KC_HEALTH_ENABLED=true`,
     `E2E_KC_CLIENT_SECRET` and `E2E_KC_USER_PASSWORD` from Secret `e2e-keycloak-credentials` (keys
     `client-secret`, `user-password`). No admin user.
   - Readiness `/health/ready` on 8080; requests `cpu 100m / memory 512Mi`, limits `1000m / 1Gi`.
   - Realm JSON: realm `shopping-cart`, `enabled: true`; realm roles `PAYMENT_USER`, `PAYMENT_WRITE`; confidential
     client `e2e-tests` with `directAccessGrantsEnabled: true`, `standardFlowEnabled: false`,
     `secret: "${E2E_KC_CLIENT_SECRET}"`; user `e2e-user` (enabled, `emailVerified: true`, realm roles
     `PAYMENT_USER`, `PAYMENT_WRITE`, credential type `password`, `value: "${E2E_KC_USER_PASSWORD}"`,
     `temporary: false`). Keycloak's import resolves `${ENV}` placeholders; no literal secret goes in git.
2. `scripts/etc/e2e/kustomization.yaml`: add `keycloak.yaml` to `resources` before `payment.yaml`.
3. `scripts/etc/e2e/payment.yaml` env: add `OAUTH2_ISSUER_URI=http://keycloak:8080/realms/shopping-cart` and
   `OAUTH2_JWK_SET_URI=http://keycloak:8080/realms/shopping-cart/protocol/openid-connect/certs`. Leave the rest.
4. `scripts/plugins/e2e.sh`:
   - new `_e2e_provision_keycloak_secret <kubeconfig>`, modelled on `_e2e_provision_datastore_secret`: values from
     `E2E_KC_CLIENT_SECRET` / `E2E_KC_USER_PASSWORD` or `od -An -N24 -tx1 /dev/urandom | tr -d ' \n'`, created
     with `--dry-run=client -o yaml | apply`; nothing echoed.
   - `_e2e_deploy_substrate`: call it right after `_e2e_provision_pull_secret`, and add `keycloak` to the rollout
     loop **before** `payment`.
   - `_e2e_job_manifest` (vcluster tier only; leave `_e2e_sandbox_job_manifest` alone) env:
     `KEYCLOAK_URL=http://keycloak:8080`, `KEYCLOAK_REALM=shopping-cart`, `KEYCLOAK_CLIENT_ID=e2e-tests`,
     `TEST_USERNAME=e2e-user`, and `KEYCLOAK_CLIENT_SECRET` / `TEST_PASSWORD` via `secretKeyRef` on
     `e2e-keycloak-credentials`. Keep `OAUTH2_ENABLED=false` (the orchestrator flow must stay skipped on this tier).
5. Tests in `scripts/tests/plugins/e2e.bats` (stubbed, no cluster):
   - `_e2e_job_manifest` output has the five Keycloak env names, `secretKeyRef` for the two secrets, and no literal
     password value;
   - `_e2e_deploy_substrate` creates `e2e-keycloak-credentials` before `apply -k` and waits for `keycloak` before
     `payment` (order from the stub's call log);
   - with `E2E_KC_USER_PASSWORD=s3cr3t-sentinel`, the sentinel never appears in any recorded `_e2e_kc` **argv** line
     except as the `--from-literal` value of the `create secret` call;
   - `kubectl kustomize scripts/etc/e2e` (or `kustomize build`) renders, contains `kind: Deployment` `keycloak`, and
     the realm JSON parses with `jq` after extraction.
   - Mutations, `cp`-restored and `cmp`-proved: drop `keycloak` from the rollout loop → red; inline a literal
     `value:` for `TEST_PASSWORD` → red.
6. Gates: `bats scripts/tests/plugins/e2e.bats scripts/tests/plugins/e2e_image_prune.bats` green; `shellcheck
   scripts/plugins/e2e.sh` no new warnings. `e2e_prune_images` must still list the Keycloak image (it is a plain
   `image:`); add it to the image-prune test if that test enumerates substrate images.

### Rules (all three repos)

- No cluster, network, or git commits; leave every change uncommitted. Claude verifies and commits.
- Do not touch `CHANGELOG.md` or any memory-bank.
- Report: files changed per repo, each gate's output, each mutation's result.

### Rollout (operator, in order)

1. Payment PR merges → CI builds `sha-<new>`; bump the `shopping-cart-payment` `newTag` in
   `scripts/etc/e2e/kustomization.yaml` to it (Claude does this commit).
2. e2e-tests PR merges → its image is published; bump `E2E_IMAGE_TAG` if it is pinned.
3. Run `e2e_verify_vcluster`. Expected: the eight payment API tests pass; `should return healthy status` still
   fails (out of scope above). Live-verify that the token's `iss` is `http://keycloak:8080/realms/shopping-cart`
   (realm import resolved the placeholders if the password grant succeeds at all).
4. Production check (read-only, operator): with a real user token, `GET /api/v1/payments/customer/<id>` on the
   payment service returned 403 before the payment image rollout and does not after.

### Lead, unverified — the sandbox-tier `stripe` failure

`_e2e_sandbox_job_manifest` sets `KEYCLOAK_URL=https://keycloak.3ai-talk.org/realms/shopping-cart`, but
`auth.ts` appends `/realms/<realm>/…` itself, so the token URL has the realm twice, and the Job sets no
`KEYCLOAK_CLIENT_*` / `TEST_*`, so the defaults (`e2e-tests` / `e2e-user`) are used against the production realm.
`getAuthToken` then returns `null` and the orchestrator falls back to `X-User-ID`. Not fixed here; triage
separately.

### Resolution — option (b) implementation (2026-10-02)

Implemented by Codex, verified by Claude:

- `shopping-cart-payment` `fix/payment-jwt-keycloak-roles` `d2f2d55`: `KeycloakGrantedAuthoritiesConverter`, wired in
  `SecurityConfig`; converter tests and two controller cases through the converter. **Not run locally:** the private
  `rabbitmq-client` 1.0.2 package needs GitHub Packages auth that this laptop's `~/.m2` lacks, and `/usr/bin/java`
  is the macOS stub (use `openjdk@21`). The branch CI (`ci.yaml`, `fix/**`) is the gate.
- `shopping-cart-e2e-tests` `fix/payment-client-v1-bearer` `df6b9c1`: v1 paths, `mintToken`, honest `responseData`.
  `tsc --noEmit` reports the same 11 errors as `origin/main` (pre-existing, other specs); none are new.
- k3d-manager: substrate `keycloak.yaml`, payment issuer/JWK env, `_e2e_provision_keycloak_secret`, Job env via
  `secretKeyRef`. `e2e.bats` + `e2e_image_prune.bats` 63/63; mutations (no keycloak rollout wait, literal
  `TEST_PASSWORD`, no secret provisioning) red.

---

## Fix spec — health on Tier 1: a substrate RabbitMQ broker + the `spring.rabbitmq` key path (operator decision 2026-10-02)

The operator chose a real broker over relaxing the health test to the probe groups. Both defects from the 2026-09-24
and 2026-09-29 updates must be fixed, because each alone keeps `/actuator/health` at 503.

**Confirmed before fixing (2026-10-02):** `rabbitmq-client` (`com.shoppingcart:rabbitmq-client`) registers its own
`RabbitMQClientAutoConfiguration`, `ConnectionManager` and `RabbitMQHealthIndicator`, and binds the top-level
`rabbitmq.*` block. Spring Boot's stock `RabbitHealthIndicator` uses the separate auto-configured factory, which binds
`spring.rabbitmq.*`. So the key-path defect is health-only, not a messaging outage, and the top-level block must stay.

### A. `shopping-cart-payment`, same branch `fix/payment-jwt-keycloak-roles`

1. `src/main/resources/application.yml`: add a `rabbitmq:` child **inside the existing top-level `spring:` mapping**
   (do not create a second `spring:` key; YAML would silently keep only one):
   ```yaml
     rabbitmq:
       host: ${RABBITMQ_HOST:rabbitmq.shopping-cart-data.svc.cluster.local}
       port: ${RABBITMQ_PORT:5672}
       virtual-host: ${RABBITMQ_VHOST:/}
       username: ${RABBITMQ_USERNAME:guest}
       password: ${RABBITMQ_PASSWORD:guest}
   ```
   Leave the top-level `rabbitmq:` block (including `vault:`) unchanged. Do **not** add
   `management.health.rabbit.enabled=false` (rejected 2026-09-24: a false green).
2. Test, new `src/test/java/com/shoppingcart/payment/config/RabbitPropertiesBindingTest.java`: load
   `application.yml` with `YamlPropertySourceLoader` and assert `spring.rabbitmq.host`, `.port`, `.virtual-host`,
   `.username`, `.password` exist with the env placeholders above, and that top-level `rabbitmq.host` and
   `rabbitmq.vault.enabled` still exist. Mutation: delete the `spring.rabbitmq` block → red.
3. Gate: the branch CI (`ci.yaml` runs on `fix/**`). The local build cannot resolve the private `rabbitmq-client`
   package; do not try to fix that.

### B. `k3d-manager` — the broker

1. New `scripts/etc/e2e/rabbitmq.yaml`: Deployment and Service `rabbitmq` (port 5672, name `amqp`), labels as the
   other substrate files, `app.kubernetes.io/component: datastore`.
   - Image `rabbitmq:3.12-alpine`: the same 3.12 line as production (`shopping-cart-infra` pins
     `rabbitmq:3.12-management-alpine`); the management plugin is not needed here.
   - Env `RABBITMQ_DEFAULT_USER=e2e`; `RABBITMQ_DEFAULT_PASS` via `secretKeyRef` on `e2e-datastore-credentials`, key
     `rabbitmq-password`.
   - Readiness: exec `rabbitmq-diagnostics -q ping`, `initialDelaySeconds 10`, `periodSeconds 5`,
     `timeoutSeconds 5`, `failureThreshold 24`. Requests `100m / 256Mi`, limits `500m / 512Mi`.
2. `scripts/etc/e2e/kustomization.yaml`: add `rabbitmq.yaml` to `resources` after `redis.yaml`.
3. `scripts/etc/e2e/payment.yaml` env: `RABBITMQ_HOST=rabbitmq`, `RABBITMQ_PORT=5672`, `RABBITMQ_USERNAME=e2e`,
   `RABBITMQ_PASSWORD` via `secretKeyRef` (`e2e-datastore-credentials` / `rabbitmq-password`). Keep
   `RABBITMQ_VAULT_ENABLED=false`.
4. `scripts/plugins/e2e.sh`:
   - `_e2e_provision_datastore_secret`: add `rabbitmq-password` from `E2E_RABBITMQ_PASSWORD` or the same `od`
     generator.
   - `_e2e_deploy_substrate`: rollout loop becomes `postgres redis rabbitmq product-catalog basket order keycloak
     payment`.
5. Tests (`scripts/tests/plugins/e2e.bats`, `e2e_image_prune.bats`; stubbed):
   - the datastore secret call carries a `rabbitmq-password` literal and no other new key;
   - `rabbitmq` is waited for before `payment`;
   - `kubectl kustomize scripts/etc/e2e` renders a `rabbitmq` Deployment, and payment's `RABBITMQ_PASSWORD` is a
     `secretKeyRef`, never a literal `value`;
   - `e2e_prune_images` lists `rabbitmq:3.12-alpine`.
   - Mutations, `cp`-restored and `cmp`-proved: drop `rabbitmq` from the rollout loop → red; drop the
     `rabbitmq-password` literal → red.
6. Gates: `bats scripts/tests/plugins/e2e.bats scripts/tests/plugins/e2e_image_prune.bats` green;
   `shellcheck scripts/plugins/e2e.sh` clean.

### Rules

- No cluster, network, or git commits; leave every change uncommitted. Do not touch `CHANGELOG.md` or memory-bank.
- Do not modify files outside those named above.

### Rollout

Same as option (b): the payment PR merges → bump the substrate payment pin → `e2e_verify_vcluster`. Expected: all nine
`api/payments.spec.ts` tests pass. If `/actuator/health` is still `DOWN`, read its `components` in the payment pod (no
auth needed for `/actuator/**`) before changing anything: another indicator (for example the client's
`VaultHealthIndicator`) may be next in line.

### Resolution — broker and key path (2026-10-02)

- **Payment** (`fix/payment-jwt-keycloak-roles`, `9778e21`): `spring.rabbitmq.*` added inside the existing
  `spring:` key (one top-level `spring:`, checked with `yq`); the library's top-level `rabbitmq:` block is
  unchanged. New `RabbitPropertiesBindingTest`. Java is gated by branch CI.
- **k3d-manager substrate**: new `scripts/etc/e2e/rabbitmq.yaml` (`rabbitmq:3.12-alpine`, user `e2e`,
  password from `e2e-datastore-credentials`/`rabbitmq-password`, readiness `rabbitmq-diagnostics -q ping`);
  payment gets `RABBITMQ_*` env, password via `secretKeyRef`; the rollout waits for `rabbitmq` before payment.
- Gates: `e2e.bats` + `e2e_image_prune.bats` 66/66, shellcheck clean. Claude's mutations (literal password in
  payment env, broker dropped from the kustomization, `rabbitmq-password` dropped from the Secret) each went red;
  restores `cmp`-proved.
- Still needed for a green Tier 1: merge both payment fixes and the e2e-tests fix, bump the substrate payment pin,
  then a live `e2e_verify_vcluster` run.
