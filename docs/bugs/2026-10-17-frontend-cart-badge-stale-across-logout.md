# Bug: Header cart badge shows the previous user's item count after logout/login

**Status:** OPEN — cause confirmed by code read + live check; not yet fixed
**Priority:** P3
**Branch:** `k3d-manager-v1.43.5` (moved from v1.43.4 by the operator, 2026-10-17: "move 3, and 4 to next release")
**Approval:** pending
**Found:** 2026-10-17, operator (logged out `developer`, logged in as `admin`, badge showed 3)
**Affected:** `shopping-cart-frontend` (`src/stores/cartStore.ts`, `src/components/layout/Header.tsx`, `src/hooks/useCart.ts`)

## Symptom

After logging out as `developer` (3 items) and in as `admin` (empty cart), the header badge showed
**3**. Opening the Cart page corrected it to empty. Logging back in as `developer`, the badge showed
the stale **0** until the Cart page was opened, which then listed all 3 items.

The server side is correct and per-user. Live check 2026-10-17: Redis `cart:<keycloak sub>` keys map
to `developer` (3 items), `admin` (empty) and `k3dm-smoke` (empty); no cart was lost or shared.

## Root cause

- `cartStore` is wrapped in zustand `persist` (`name: 'cart-storage'`, `partialize` keeps
  `itemCount`), so the count lives in `localStorage` with no owner.
- `Header.handleLogout` calls `auth.signoutRedirect()` only — nothing clears `cart-storage`.
- The header reads `itemCount` from the store, and only `CartPage` calls `useCart()`, so the server
  cart is not fetched on login; the badge shows whatever the last user left behind.
- `guest-cart-token` in `localStorage` is not cleared on logout either; the next login merges any
  guest cart into whichever account signs in next.

Probably also the origin of the 2026-10-13 report in
`docs/bugs/2026-10-13-shopping-cart-cart-lost-after-logout-login.md` (badge 0 after login reads as
an empty cart).

## Fix direction

Clear the cart store (and its persisted copy) on logout, and fetch the cart whenever an authenticated
session starts — e.g. call `useCart()` from the header, or key the persisted state by `sub`. Decide
deliberately whether a guest token should survive logout. Do not drop server-side per-user keying.

## Acceptance

```yaml
must:
  - id: M1
    text: After user A (N items) logs out and user B (M items) logs in, the header badge shows M without visiting the Cart page.
  - id: M2
    text: After logout, before any login, the badge is not shown or shows 0, and localStorage holds no item count from the previous user.
  - id: M3
    text: The Cart page still lists the logged-in user's own server-side items.
must_not:
  - id: N1
    text: The badge never shows another user's item count after a user switch.
  - id: N2
    text: Logout never deletes or modifies the server-side cart (user A's items are still there when A logs back in).
  - id: N3
    text: A guest cart token left by one session is not merged into a different account's cart without that user acting as the guest first.
evidence:
  - id: E1
    proves: [M1, M2, N1]
    kind: offline
    text: Vitest/RTL test switching auth users with mocked cart API; red on pre-fix code.
  - id: E2
    proves: [M3, N2]
    kind: offline
    text: Test that logout makes no DELETE/clear call to the cart API and the next login refetches.
  - id: E3
    proves: [M1, N1, N2]
    kind: live
    text: Operator or Claude repeats developer(3) -> logout -> admin(0) -> logout -> developer(3) on frontend.3ai-talk.org; badge correct at each step without opening the Cart page.
interface:
  - src/stores/cartStore.ts (useCartStore)
  - src/components/layout/Header.tsx (logout button, badge)
  - src/hooks/useCart.ts (useCart)
  - localStorage keys cart-storage, guest-cart-token
```
