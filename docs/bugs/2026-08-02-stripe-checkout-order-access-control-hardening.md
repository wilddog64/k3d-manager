# Bugfix: Stripe checkout — order service access-control hardening (Copilot #2 aud/azp + #4 IDOR)

**Coordinating repo:** k3d-manager (this file). **Work repo:** `shopping-cart-order`.
**Branch (work repo):** `fix/order-access-control-hardening` off `origin/main`.
**Files:** `go/internal/auth/jwt.go`, `go/internal/config/config.go`, `go/cmd/server/main.go`,
`go/internal/order/handler.go`, plus test updates in `go/internal/order/handler_test.go`.

Source: deferred Copilot findings register
`docs/issues/2026-08-02-stripe-checkout-copilot-deferred-hardening.md` — items **#2** (aud/azp,
`jwt.go:139`, HIGH) and **#4** (IDOR, order reads not customer-scoped, `main.go:76` handlers, HIGH).
These are the two access-control gaps that go **live** at the Stripe/OAuth2 enablement flip, so they
must land before it.

---

## Problem

Both live only when `OAUTH2_ENABLED=true` (the enablement path), so they are latent on `main` today.

1. **#2 — audience/azp not validated.** `JWTValidator.ValidateToken` checks signature + issuer
   (`jwt.go:113-117`) but extracts `aud` without ever validating it (`jwt.go:136`), and never looks at
   `azp`. Any token signed by the same Keycloak realm — including one minted for a *different* client —
   is accepted by the order service.

2. **#4 — order reads are not scoped to the authenticated customer (IDOR).**
   - `GetOrder` (`handler.go:170`) fetches any order by id and returns it with **no ownership check** —
     any authenticated user can read any order by guessing/knowing its UUID.
   - `ListOrdersByCustomer` (`handler.go:185`) reads `customerId` from the **query string** and trusts
     it, so any authenticated user can list any other customer's orders by passing their id.

**Root cause:** the auth middleware already resolves the caller identity into the gin context
(`httpx.SetCustomerID` ← JWT `sub`, empty subject already rejected in `httpx/auth.go:36`), but the read
handlers ignore it, and the validator never enforces the token's intended audience.

---

## Design decision — audience enforcement is configurable and OFF by default

Keycloak access tokens minted for the **frontend** client typically carry `aud: ["account"]` and
`azp: <frontend-client-id>` — **not** `order-service`. The order validator's `clientID` defaults to
`"order-service"` (`config.go:68`), and the basket service runs the byte-identical validator today
*without* an audience check — strong evidence the live tokens do **not** carry `order-service` in `aud`.
A hard `aud == order-service` check would therefore **reject the very tokens the live flow uses** the
moment OAuth2 is enabled.

So enforcement is gated on a new env var **`OAUTH2_EXPECTED_AUDIENCE`** (default `""`):

- **empty (default):** skip enforcement, log one warning at startup. Code lands on `main` with **zero
  behavior change** — nothing breaks.
- **set:** accept the token iff `aud` contains the value **OR** `azp` equals it; otherwise reject with
  `ErrInvalidAudience`.

The value is set to the **verified** audience/azp during enablement bring-up (see checklist), once a
real token can be inspected. This is the only safe way to enforce an audience you have not yet observed.

---

## Fix

### Change 1 — `go/internal/auth/jwt.go`: add `ErrInvalidAudience`

**Exact old block (lines 27-28):**

```go
	// ErrJWKSFetch is returned when JWKS cannot be fetched
	ErrJWKSFetch = errors.New("failed to fetch JWKS")
```

**Exact new block:**

```go
	// ErrJWKSFetch is returned when JWKS cannot be fetched
	ErrJWKSFetch = errors.New("failed to fetch JWKS")
	// ErrInvalidAudience is returned when the token audience/azp doesn't match the expected value
	ErrInvalidAudience = errors.New("invalid audience")
```

### Change 2 — `go/internal/auth/jwt.go`: add `expectedAudience` field

**Exact old block (lines 44-53):**

```go
// JWTValidator validates JWT tokens using Keycloak JWKS
type JWTValidator struct {
	issuerURI  string
	clientID   string
	jwksURL    string
	keys       map[string]*rsa.PublicKey
	keysMutex  sync.RWMutex
	httpClient *http.Client
	logger     *zap.Logger
}
```

**Exact new block:**

```go
// JWTValidator validates JWT tokens using Keycloak JWKS
type JWTValidator struct {
	issuerURI        string
	clientID         string
	expectedAudience string
	jwksURL          string
	keys             map[string]*rsa.PublicKey
	keysMutex        sync.RWMutex
	httpClient       *http.Client
	logger           *zap.Logger
}
```

### Change 3 — `go/internal/auth/jwt.go`: thread `expectedAudience` through the constructor

**Exact old block (lines 55-70):**

```go
// NewJWTValidator creates a new JWT validator
func NewJWTValidator(issuerURI, clientID string, logger *zap.Logger) *JWTValidator {
	// Normalize issuer URI (remove trailing slash)
	issuerURI = strings.TrimSuffix(issuerURI, "/")

	return &JWTValidator{
		issuerURI: issuerURI,
		clientID:  clientID,
		jwksURL:   issuerURI + "/protocol/openid-connect/certs",
		keys:      make(map[string]*rsa.PublicKey),
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
		logger: logger,
	}
}
```

**Exact new block:**

```go
// NewJWTValidator creates a new JWT validator
func NewJWTValidator(issuerURI, clientID, expectedAudience string, logger *zap.Logger) *JWTValidator {
	// Normalize issuer URI (remove trailing slash)
	issuerURI = strings.TrimSuffix(issuerURI, "/")

	if expectedAudience == "" {
		logger.Warn("OAUTH2_EXPECTED_AUDIENCE is empty; token audience/azp will not be enforced")
	}

	return &JWTValidator{
		issuerURI:        issuerURI,
		clientID:         clientID,
		expectedAudience: expectedAudience,
		jwksURL:          issuerURI + "/protocol/openid-connect/certs",
		keys:             make(map[string]*rsa.PublicKey),
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
		logger: logger,
	}
}
```

### Change 4 — `go/internal/auth/jwt.go`: enforce audience/azp after issuer validation

**Exact old block (lines 113-119):**

```go
	// Validate issuer
	iss, _ := claims["iss"].(string)
	if iss != v.issuerURI {
		return nil, ErrInvalidIssuer
	}

	// Extract claims
```

**Exact new block:**

```go
	// Validate issuer
	iss, _ := claims["iss"].(string)
	if iss != v.issuerURI {
		return nil, ErrInvalidIssuer
	}

	// Validate audience / authorized party — reject tokens minted for other clients.
	// Enforced only when an expected audience is configured (see OAUTH2_EXPECTED_AUDIENCE).
	if v.expectedAudience != "" {
		aud := getAudienceClaim(claims)
		azp := getStringClaim(claims, "azp")
		if !containsString(aud, v.expectedAudience) && azp != v.expectedAudience {
			return nil, ErrInvalidAudience
		}
	}

	// Extract claims
```

### Change 5 — `go/internal/auth/jwt.go`: add `containsString` helper

**Exact old block (lines 301-308):**

```go
// Helper functions

func getStringClaim(claims jwt.MapClaims, key string) string {
	if val, ok := claims[key].(string); ok {
		return val
	}
	return ""
}
```

**Exact new block:**

```go
// Helper functions

func containsString(list []string, target string) bool {
	for _, s := range list {
		if s == target {
			return true
		}
	}
	return false
}

func getStringClaim(claims jwt.MapClaims, key string) string {
	if val, ok := claims[key].(string); ok {
		return val
	}
	return ""
}
```

### Change 6 — `go/internal/config/config.go`: add `OAuth2ExpectedAudience` field

**Exact old block (lines 31-34):**

```go
	OAuth2Enabled   bool
	OAuth2IssuerURI string
	OAuth2JWKSetURI string
	OAuth2ClientID  string
```

**Exact new block:**

```go
	OAuth2Enabled          bool
	OAuth2IssuerURI        string
	OAuth2JWKSetURI        string
	OAuth2ClientID         string
	OAuth2ExpectedAudience string
```

### Change 7 — `go/internal/config/config.go`: load `OAUTH2_EXPECTED_AUDIENCE`

**Exact old block (lines 65-68):**

```go
		OAuth2Enabled:   getEnvAsBool("OAUTH2_ENABLED", false),
		OAuth2IssuerURI: getEnv("OAUTH2_ISSUER_URI", ""),
		OAuth2JWKSetURI: getEnv("OAUTH2_JWK_SET_URI", ""),
		OAuth2ClientID:  getEnv("OAUTH2_CLIENT_ID", "order-service"),
```

**Exact new block:**

```go
		OAuth2Enabled:          getEnvAsBool("OAUTH2_ENABLED", false),
		OAuth2IssuerURI:        getEnv("OAUTH2_ISSUER_URI", ""),
		OAuth2JWKSetURI:        getEnv("OAUTH2_JWK_SET_URI", ""),
		OAuth2ClientID:         getEnv("OAUTH2_CLIENT_ID", "order-service"),
		OAuth2ExpectedAudience: getEnv("OAUTH2_EXPECTED_AUDIENCE", ""),
```

### Change 8 — `go/cmd/server/main.go`: pass expected audience to the validator

**Exact old block (line 62):**

```go
		validator := auth.NewJWTValidator(cfg.OAuth2IssuerURI, cfg.OAuth2ClientID, logger)
```

**Exact new block:**

```go
		validator := auth.NewJWTValidator(cfg.OAuth2IssuerURI, cfg.OAuth2ClientID, cfg.OAuth2ExpectedAudience, logger)
```

### Change 9 — `go/internal/order/handler.go`: import `httpx`

**Exact old block (lines 3-13):**

```go
import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/shopspring/decimal"
	"go.uber.org/zap"
)
```

**Exact new block:**

```go
import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/shopspring/decimal"
	"github.com/wilddog64/shopping-cart-order/internal/httpx"
	"go.uber.org/zap"
)
```

### Change 10 — `go/internal/order/handler.go`: ownership check in `GetOrder`

**Exact old block (lines 170-183):**

```go
func (h *Handler) GetOrder(c *gin.Context) {
	id, ok := parseOrderID(c, h.logger)
	if !ok {
		return
	}

	orderEntity, err := h.service.GetOrder(c.Request.Context(), id)
	if err != nil {
		handleServiceError(c, err)
		return
	}

	c.JSON(http.StatusOK, toOrderResponse(orderEntity))
}
```

**Exact new block:**

```go
func (h *Handler) GetOrder(c *gin.Context) {
	id, ok := parseOrderID(c, h.logger)
	if !ok {
		return
	}

	orderEntity, err := h.service.GetOrder(c.Request.Context(), id)
	if err != nil {
		handleServiceError(c, err)
		return
	}

	// Ownership check: never disclose another customer's order. 404 (not 403) avoids leaking existence.
	if orderEntity.CustomerID != httpx.GetCustomerID(c) {
		writeError(c, http.StatusNotFound, "NOT_FOUND", "order not found")
		return
	}

	c.JSON(http.StatusOK, toOrderResponse(orderEntity))
}
```

### Change 11 — `go/internal/order/handler.go`: scope `ListOrdersByCustomer` to the authenticated subject

**Exact old block (lines 185-190):**

```go
func (h *Handler) ListOrdersByCustomer(c *gin.Context) {
	customerID := strings.TrimSpace(c.Query("customerId"))
	if customerID == "" {
		writeError(c, http.StatusBadRequest, "BAD_REQUEST", "customerId is required")
		return
	}
```

**Exact new block:**

```go
func (h *Handler) ListOrdersByCustomer(c *gin.Context) {
	// Always list the authenticated caller's own orders — ignore any client-supplied customerId.
	customerID := strings.TrimSpace(httpx.GetCustomerID(c))
	if customerID == "" {
		writeError(c, http.StatusUnauthorized, "UNAUTHORIZED", "authenticated customer required")
		return
	}
```

---

## Test updates — `go/internal/order/handler_test.go`

Update existing `GetOrder` / `ListOrdersByCustomer` tests so the gin context carries a customer id
(the handlers now read it). Set it the same way the auth middleware does:

```go
httpx.SetCustomerID(c, "<customer-id-matching-the-fixture-order>")
```

Add two negative tests proving the gate:

- **GetOrder cross-customer → 404:** context customer `"other-user"`, fetched order owned by
  `"owner-user"` → expect `http.StatusNotFound`, body not the order.
- **ListOrdersByCustomer ignores query param:** context customer `"owner-user"`, request URL carries
  `?customerId=someone-else` → service is called with `"owner-user"` (assert via the fake/mock store),
  never `"someone-else"`.

If the current tests build requests through the full router, ensure they run with
`MockAuthMiddleware` (which sets the customer from `X-User-ID`, default `dev-user`) so the context is
populated; otherwise set it directly on the `*gin.Context` as above.

---

## Files Changed

| File | Change |
|------|--------|
| `go/internal/auth/jwt.go` | add `ErrInvalidAudience`, `expectedAudience` field + ctor param, aud/azp enforcement, `containsString` helper |
| `go/internal/config/config.go` | add `OAuth2ExpectedAudience` field + `OAUTH2_EXPECTED_AUDIENCE` load (default `""`) |
| `go/cmd/server/main.go` | pass `cfg.OAuth2ExpectedAudience` to `NewJWTValidator` |
| `go/internal/order/handler.go` | import `httpx`; ownership check in `GetOrder` (404); scope `ListOrdersByCustomer` to authenticated subject |
| `go/internal/order/handler_test.go` | populate customer context; 2 new negative tests (cross-customer 404, query-param ignored) |

---

## Rules

- `gofmt -l go/` → no output (all changed files formatted)
- `go build ./...` clean
- `go vet ./...` clean
- `go test -count=1 ./...` green (incl. new negative tests, uncached)
- No other files touched. No `go.mod`/`go.sum` changes (uses only existing deps + stdlib).

---

## Definition of Done

- [ ] All 11 exact blocks applied byte-for-byte + the test updates
- [ ] `gofmt`/`go build`/`go vet`/`go test -count=1 ./...` all green uncached
- [ ] Committed and pushed to `fix/order-access-control-hardening` (branched off `origin/main`)
- [ ] Order-repo memory-bank updated as a **separate** commit (keep the fix commit scope-clean)
- [ ] Report the fix commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(order): scope order reads to authenticated customer and enforce token audience
```

---

## Enablement checklist (Claude, at the OAuth2 flip — NOT part of this Codex task)

The audience enforcement is inert until `OAUTH2_EXPECTED_AUDIENCE` is set. Before/at enablement:

- [ ] Obtain a real access token from the live flow and inspect its `aud` and `azp`.
- [ ] Either (a) add a Keycloak **audience mapper** so tokens carry `order-service` in `aud` and set
      `OAUTH2_EXPECTED_AUDIENCE=order-service`, or (b) set `OAUTH2_EXPECTED_AUDIENCE` to the observed
      frontend `azp` (client id). Prefer (a) — a dedicated audience is the standard Keycloak pattern.
- [ ] Confirm the live F e2e run (`OAUTH2_ENABLED=true STRIPE_E2E=true`) still passes with enforcement on.

---

## What NOT to Do

- Do NOT create a PR (Claude opens it after verifying).
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the listed targets.
- Do NOT commit to `main` — work on `fix/order-access-control-hardening`.
- Do NOT change `CreateOrder` body-trust of `customerId` here — related but out of scope for this
  gate; it is tracked separately (checkout orchestrator already derives the customer from context).
- Do NOT set a non-empty default for `OAUTH2_EXPECTED_AUDIENCE` — it must stay `""` so this lands
  without breaking the current flow.
