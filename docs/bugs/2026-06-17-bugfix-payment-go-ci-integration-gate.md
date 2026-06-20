# Bugfix: payment Go CI — gate the integration test (`-tags integration`)

**Spec repo:** k3d-manager (`k3d-manager-v1.7.1`)
**Work repo:** `shopping-cart-payment`
**Branch (all work repos):** `feat/go-rewrite`
**Files:** `.github/workflows/go-ci.yml`

---

## Problem

The Go integration test (`go/internal/payment/integration_test.go`, gated by
`//go:build integration`) is never run in CI. The `go-ci` workflow's only test step is
`go test ./... -race -cover`, which compiles out every file behind the `integration` build
tag. As a result:

- `f2e47ff` shipped the integration test **RED** (`integration_test.go:80: list payments:
  no rows in result set`) and CI stayed green — the double-advance bug was invisible to CI.
- `6ee63e3` fixed the bug and the test now passes, but **only when run by hand**. If the
  store regresses, CI will not catch it again.

**Root cause:** `go test ./...` does not pass `-tags integration`, so the build-tagged
acceptance test is excluded from the only place it would otherwise run.

---

## Reproduction

```bash
# In shopping-cart-payment/go, with the current go-ci.yml test step:
go test ./... -race -cover        # PASSES — integration test is compiled out, never runs
go test -tags integration ./internal/payment/...   # the ONLY way the test runs
```

**Symptom:** a broken store list method (double-advance) keeps CI green because the test
that exercises it is build-tag-gated and CI omits the tag.

---

## Fix

Add a second job, `integration`, to `.github/workflows/go-ci.yml` that stands up a throwaway
Postgres service container and runs the build-tagged test with `-tags integration`. The test
seeds the real Java Flyway migrations itself (`src/main/resources/db/migration/V1__*.sql`,
`V2__*.sql`), so the service only needs an empty database and a DSN.

The existing `go` job (gofmt / vet / golangci-lint / unit tests / docker build) is unchanged.
The workflow-level `permissions: contents: read` already applies to the new job — do not add
an elevated per-job `permissions` block.

### Change 1 — `.github/workflows/go-ci.yml`: append the `integration` job

**Exact old block (last two steps of the `go` job, end of file):**

```yaml
      - run: go test ./... -race -cover
      - run: docker build -f Dockerfile .
```

**Exact new block:**

```yaml
      - run: go test ./... -race -cover
      - run: docker build -f Dockerfile .

  integration:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: go
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: payment
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U postgres -d payment"
          --health-interval 5s
          --health-timeout 5s
          --health-retries 10
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: "1.21"
          cache-dependency-path: go/go.sum
      - run: go test -tags integration -count=1 ./internal/payment/...
        env:
          PAYMENT_INTEGRATION_DSN: postgres://postgres:postgres@localhost:5432/payment?sslmode=disable
```

> Why `working-directory: go` matters: `go test` runs the test binary with CWD set to the
> package dir (`go/internal/payment`), so the test's relative migration paths
> (`../../../src/main/resources/db/migration/...`) resolve to the repo-root `src/` tree.
> Do not move or rewrite those paths.

---

## Files Changed

| File | Change |
|------|--------|
| `.github/workflows/go-ci.yml` | Add an `integration` job: Postgres service container + `go test -tags integration ./internal/payment/...` |

---

## Rules

- Touch **only** `.github/workflows/go-ci.yml`. Do NOT modify `store.go`, `integration_test.go`,
  or any other workflow.
- Do NOT change the existing `go` job.
- Keep `permissions: contents: read` — the new job must NOT add an elevated `permissions` block
  (the workflow-level grant already covers it).
- Pin all actions to a version tag (`actions/checkout@v4`, `actions/setup-go@v5`) and the
  service image to a pinned tag (`postgres:16-alpine`) — no `@main`/`@latest`/floating tags.
- The DSN password is a throwaway service-container literal — do NOT route it through Vault or
  a secret; it never leaves the runner.
- Validate the YAML parses: `python3 -c 'import yaml,sys; yaml.safe_load(open(".github/workflows/go-ci.yml"))'`
  must exit 0 (run from the repo root).
- Run `_agent_audit` before reporting done.

---

## Definition of Done

- [ ] `.github/workflows/go-ci.yml` has a new `integration` job with the Postgres service and
      the `-tags integration` test step exactly as specified
- [ ] The existing `go` job is byte-for-byte unchanged
- [ ] YAML parses cleanly (`yaml.safe_load` exits 0)
- [ ] `./scripts/k3d-manager _agent_audit` clean
- [ ] Committed and pushed to `feat/go-rewrite` in `shopping-cart-payment`
- [ ] memory-bank updated with commit SHA and task status
- [ ] After push, the `go-ci` workflow run shows the new `integration` job **green** on the
      branch (this is the gate — confirm it actually ran and passed, do NOT report done on the
      push alone)

**Commit message (exact):**
```
ci(payment): gate Go integration test behind a Postgres service job

go-ci ran only `go test ./...`, which compiles out the //go:build
integration test, so the double-advance regression in f2e47ff stayed
invisible to CI. Add an integration job with a throwaway Postgres
service and run `go test -tags integration ./internal/payment/...`.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `.github/workflows/go-ci.yml`
- Do NOT alter the existing `go` job or any other workflow
- Do NOT add an elevated `permissions` block to the new job
- Do NOT commit to `main` — work on `feat/go-rewrite`
