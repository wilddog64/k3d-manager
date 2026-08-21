# Bugfix: shopping-cart-payment — golangci-lint go1.25 toolchain mismatch

**Repo:** `shopping-cart-payment`
**Branch (create off `origin/main`):** `fix/golangci-go125-toolchain`
**Files:** `.github/workflows/go-ci.yml`

---

## Problem

The `go` CI job fails on every Go Dependabot PR (e.g. #37 pgx, #38 net) at the
golangci-lint step:

```
Error: can't load config: the Go language version (go1.23) used to build
golangci-lint is lower than the targeted Go version (1.25.0)
Failed executing command with error: ...
golangci-lint exit with code 3
```

**Root cause:** `go-ci.yml` pins `golangci/golangci-lint-action@v9` with
`version: v2.5.0`. The golangci-lint `v2.5.0` binary is built with an older Go
toolchain (go1.23) and refuses to lint code targeting go1.25. golangci-lint
gained go1.25 support in **v2.7.2**. This is a CI-toolchain defect, independent
of the Dependabot bumps — it blocks all Go PRs.

---

## Reproduction

Open any Go Dependabot PR (#37 / #38) → `go` check fails at the
`golangci/golangci-lint-action` step with the version-mismatch error above.

---

## Fix

### Change 1 — `.github/workflows/go-ci.yml`: bump the golangci-lint version

**Exact old block (lines 30–33):**

```yaml
      - uses: golangci/golangci-lint-action@v9
        with:
          version: v2.5.0
          working-directory: go
```

**Exact new block:**

```yaml
      - uses: golangci/golangci-lint-action@v9
        with:
          version: v2.7.2
          working-directory: go
```

---

## Files Changed

| File | Change |
|------|--------|
| `.github/workflows/go-ci.yml` | pin golangci-lint `v2.5.0` → `v2.7.2` (go1.25-compatible) |

---

## Rules

- Change ONLY the `version:` value on the golangci-lint step. Do not touch
  `setup-go`, `go.mod`, `go.sum`, or any other step.
- Pin an explicit version — do NOT use `version: latest` (supply-chain rule).
- If `v2.7.2` still reports a build-Go < go1.25, bump to the earliest later v2
  release whose binary is built with Go ≥ 1.25 (verify on the golangci-lint
  releases page), and record which version you used.

---

## Definition of Done

- [ ] `go-ci.yml` line 32 reads `version: v2.7.2` (or a verified-newer go1.25 build)
- [ ] `grep -c 'version: v2.5.0' .github/workflows/go-ci.yml` → `0`
- [ ] The `go` CI check passes on a Go PR (rerun the check on #37 or push the
      branch and confirm the golangci step is green)
- [ ] Committed and pushed to `fix/golangci-go125-toolchain`
- [ ] memory-bank updated with the commit SHA and task status

**Commit message (exact):**
```
fix(go-ci): bump golangci-lint to v2.7.2 for go1.25 toolchain compatibility
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `.github/workflows/go-ci.yml`
- Do NOT change `setup-go`, `go.mod`, or the go directive
- Do NOT commit to `main` — work on `fix/golangci-go125-toolchain`
