# Follow-up: order-management flow spec still uses retired statuses (2026-08-29)

## Source
Copilot review on `shopping-cart-e2e-tests` PR #8 (order-status alignment).

## Finding
`tests/flows/order-management.spec.ts` references order statuses that the order
service does not implement:
- `CONFIRMED` — no such state; the service uses `PAID`.
- `DELIVERED` — no such state; the terminal state is `COMPLETED`.

Service enum (deployed Go order `5603388`):
`PENDING → PAID → PROCESSING → SHIPPED → COMPLETED` (plus `CANCELLED`).
Transitions: PENDING→PAID|CANCELLED; PAID→PROCESSING|CANCELLED;
PROCESSING→SHIPPED|CANCELLED; SHIPPED→COMPLETED; COMPLETED/CANCELLED terminal.

## Why it was deferred (not in PR #8)
- These flow specs are **not exercised by the Tier-1 vCluster gate** (Tier-1 runs
  the `tests/api/` specs; flows are skipped there), so they are not gate-blocking.
- Alignment is a careful per-test rewrite (~24 tests, ~13 status sites), several of
  which assert status-history contents and cancel-legality semantics that must be
  re-derived against the real enum. Bundling an un-validatable rewrite into PR #8
  would make it harder to review and could ship subtly-wrong tests.

## Proposed mapping (to be verified per test intent)
- `CONFIRMED` → `PAID`
- `DELIVERED` → `COMPLETED` (insert the legal `PAID→PROCESSING→SHIPPED→COMPLETED`
  chain where a test jumps straight to the terminal state)
- status-history assertions (`statuses.toContain('CONFIRMED')`) → update to the
  mapped values
- "should not cancel delivered order" → assert cancel fails on `COMPLETED` (terminal)

## Scope
`tests/flows/order-management.spec.ts` only. Own PR/branch off `main`.
Validate by running the flows project locally against a live order service (they
are not part of the Tier-1 api project).
