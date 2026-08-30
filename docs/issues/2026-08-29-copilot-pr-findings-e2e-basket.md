# Copilot PR findings — e2e #8 + basket #44 (2026-08-29)

Addresses actionable Copilot review comments on the two E2E Tier-1 fix PRs.
Codex handoff spec. Implement EXACTLY the old/new blocks below — no interpretation.

## Before You Start

- `git pull` the latest in each work repo.
- Branch (all work repos already exist — check them out, do NOT create new ones):
  - `shopping-cart-e2e-tests`: `fix/e2e-order-status-enum`
  - `shopping-cart-basket`: `fix/basket-update-quantity-zero`
- Read each target file in full before editing.

---

## Repo 1 — shopping-cart-e2e-tests (branch `fix/e2e-order-status-enum`)

### Change 1a — add `PROCESSING` to the `Order.status` union
File: `tests/helpers/api-client.ts`

OLD:
```ts
  status: 'PENDING' | 'PAID' | 'SHIPPED' | 'COMPLETED' | 'CANCELLED'
```
NEW:
```ts
  status: 'PENDING' | 'PAID' | 'PROCESSING' | 'SHIPPED' | 'COMPLETED' | 'CANCELLED'
```

### Change 1b — normalize product price/quantity in createProduct
File: `tests/helpers/api-client.ts`

OLD:
```ts
  async createProduct(data: Partial<Product>): Promise<Product> {
    const response = await this.request.post(`${this.baseUrl}/api/products`, {
      data,
    })
    return responseData<Product>(response)
  }
```
NEW:
```ts
  async createProduct(data: Partial<Product>): Promise<Product> {
    const response = await this.request.post(`${this.baseUrl}/api/products`, {
      data,
    })
    const product = await responseData<Product>(response)
    return { ...product, price: Number(product.price), quantity: Number(product.quantity) }
  }
```

### Change 1c — normalize product price/quantity in updateProduct
File: `tests/helpers/api-client.ts`

OLD:
```ts
  async updateProduct(id: string, data: Partial<Product>): Promise<Product> {
    const response = await this.request.patch(`${this.baseUrl}/api/products/${id}`, {
      data,
    })
    return responseData<Product>(response)
  }
```
NEW:
```ts
  async updateProduct(id: string, data: Partial<Product>): Promise<Product> {
    const response = await this.request.patch(`${this.baseUrl}/api/products/${id}`, {
      data,
    })
    const product = await responseData<Product>(response)
    return { ...product, price: Number(product.price), quantity: Number(product.quantity) }
  }
```

Commit message (e2e repo, verbatim):
`fix(e2e): normalize product numbers on create/update; add PROCESSING to Order status union`

---

## Repo 2 — shopping-cart-basket (branch `fix/basket-update-quantity-zero`)

Copilot's concern: with `binding:"min=0"` and no `required`, an omitted `quantity`
(`{}` body) binds as `0` and silently removes the item. Fix = pointer field so
`required` rejects a missing field while an explicit `{"quantity":0}` still passes.

### Change 2a — pointer field in the model
File: `internal/model/cart.go`

OLD:
```go
type UpdateItemRequest struct {
	Quantity int `json:"quantity" binding:"min=0"`
}
```
NEW:
```go
type UpdateItemRequest struct {
	Quantity *int `json:"quantity" binding:"required,min=0"`
}
```

### Change 2b — dereference in the handler
File: `internal/handler/cart_handler.go`

OLD:
```go
	cart, err := h.service.UpdateItemQuantity(c.Request.Context(), customerID, itemID, req.Quantity)
```
NEW:
```go
	cart, err := h.service.UpdateItemQuantity(c.Request.Context(), customerID, itemID, *req.Quantity)
```

### Change 2c — binding regression test (new file)
File: `internal/handler/cart_handler_binding_test.go` (create)

Add a self-contained gin/httptest test that exercises ONLY `ShouldBindJSON`
into `model.UpdateItemRequest` via a throwaway route — no service/repo needed:
- `{}` body  → route returns HTTP 400 (bind error on missing `quantity`).
- `{"quantity":0}` body → route returns HTTP 200 and the bound `*req.Quantity == 0`.
- `{"quantity":3}` body → route returns HTTP 200 and `*req.Quantity == 3`.

Use `gin.SetMode(gin.TestMode)`, `gin.New()`, a POST route that does
`var req model.UpdateItemRequest; if err := c.ShouldBindJSON(&req); err != nil { c.Status(400); return }`
then echoes `*req.Quantity`, and `httptest.NewRecorder()` + `http.NewRequest`.
Package `handler`. Import `github.com/gin-gonic/gin` (already a dependency).

Commit message (basket repo, verbatim):
`fix(basket): require explicit quantity on item update (pointer field) + binding test`

---

## Rules

- Edit ONLY the files listed above. No unrelated refactors, no other files.
- e2e repo: `npx tsc --noEmit` must not introduce NEW errors (pre-existing errors are OK — capture the before/after count).
- basket repo: `go build ./...` and `go test ./...` must pass — paste the output.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT create a PR. Do NOT commit to `main`. Work only on the named feature branches.
- Do NOT run any cluster / kubectl / docker / make command. Pure code + local build/test only.
- Do NOT edit memory-bank files.

## Definition of Done

- [ ] e2e repo: changes 1a/1b/1c committed with the exact message above.
- [ ] basket repo: changes 2a/2b/2c committed with the exact message above.
- [ ] `go build ./...` + `go test ./...` pass in basket — output pasted.
- [ ] tsc new-error count unchanged in e2e — before/after pasted.
- [ ] `git push origin <branch>` succeeded in BOTH repos — do NOT report done until pushed.
- [ ] Report back: one commit SHA per repo + `git rev-parse origin/<branch>` for each.
