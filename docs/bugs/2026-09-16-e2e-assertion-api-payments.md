# Bug: e2e assertion — api-payments

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-16 by k3dm-hermes
**Status:** OPEN, CONFIRMED (triage by Claude, 2026-10-01) — real: payment `/actuator/health` returns 503 in the e2e substrate. Awaiting the operator's choice: (a) a test-only profile or (b) a real Keycloak token.
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
