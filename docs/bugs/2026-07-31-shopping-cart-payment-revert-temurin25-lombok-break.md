# Bugfix: shopping-cart-payment — revert eclipse-temurin 21→25 (JDK 25 breaks Lombok 1.18.30 image build)

**Repo:** `shopping-cart-payment`
**Branch (create off `origin/main`):** `fix/revert-temurin25-jdk-lombok-break`
**Files:** `Dockerfile` (the Java service Dockerfile at repo root — NOT `go/Dockerfile`)

---

## Problem

PR #28 (`build(deps): bump eclipse-temurin from 21-jre-alpine to 25-jre-alpine`,
merge commit `4074d19` on `main`) bumped **both** stages of the Java `Dockerfile`
from `eclipse-temurin:21` to `eclipse-temurin:25`. This broke the image build:

```
#17 [ERROR] COMPILATION ERROR :
#17 [ERROR] .../dto/PaymentResponse.java:[29,31] cannot find symbol
    symbol:   method builder()
    location: class com.shoppingcart.payment.dto.PaymentResponse
...
ERROR: failed to solve: process "/bin/sh -c mvn package -DskipTests -B" did not complete successfully: exit code: 1
```

**Root cause:** `PaymentResponse` (and other DTOs/entities) use Lombok `@Data` /
`@Builder`. Lombok has **no explicit version** in `pom.xml` — it is managed by the
Spring Boot parent `3.2.0`, which pins **Lombok 1.18.30**. Lombok 1.18.30 predates
JDK 25 and its annotation processor no-ops under it, so none of the generated
methods (`builder()`, `getId()`, …) exist → `cannot find symbol`.

**Why CI did not catch it:** the required status checks (`Build and Test`,
`Checkstyle & SpotBugs`, `Integration Tests`, `Security Scan`) compile on the
runner's **JDK 21** (`JAVA_VERSION: 21`). Only the `Build, Scan & Push` job builds
the Docker image on **JDK 25**, and that job is **non-required AND skipped on PRs**
(runs only on merge to `main`). So #28 merged green and broke `main`'s image build.

**Impact:** `main`'s image build fails; the `latest` / `sha-<gitsha>` image is NOT
republished (stale, pre-#28 image still on the registry). This also blocks the
Hub `app-cve-scan` Spec 1 deploy, which needs a fresh payment `main` build.

**Decision (2026-07-31):** #28 was an accidental merge. Revert to the known-good
`eclipse-temurin:21` base. JDK 25 becomes a deliberate future upgrade (paired with
a Lombok bump to ≥1.18.38) if wanted — out of scope here.

---

## Reproduction

On `origin/main`:

```
docker build -f Dockerfile .
```

→ fails at `mvn package -DskipTests -B` with `cannot find symbol` on Lombok-generated
methods. Equivalently: the `Build, Scan & Push` job on the #28 merge commit
(`4074d19`) is red.

---

## Fix

Revert the two `FROM` lines #28 changed — restore `eclipse-temurin:21`.

### Change 1 — `Dockerfile` builder stage (line 5)

**Exact old:**

```dockerfile
FROM eclipse-temurin:25-jdk-alpine AS builder
```

**Exact new:**

```dockerfile
FROM eclipse-temurin:21-jdk-alpine AS builder
```

### Change 2 — `Dockerfile` runtime stage (line 29)

**Exact old:**

```dockerfile
FROM eclipse-temurin:25-jre-alpine AS runtime
```

**Exact new:**

```dockerfile
FROM eclipse-temurin:21-jre-alpine AS runtime
```

The rest of the `Dockerfile` is unchanged. Do not touch `pom.xml`, `go/Dockerfile`,
or any other file.

---

## Files Changed

| File | Change |
|------|--------|
| `Dockerfile` | both stages `eclipse-temurin:25-*-alpine` → `eclipse-temurin:21-*-alpine` (revert of #28) |

---

## Rules

- Change ONLY the two `FROM` lines. No `pom.xml`, no `go/Dockerfile`, no other file.
- Keep the pinned minor tags (`21-jdk-alpine`, `21-jre-alpine`) exactly — supply-chain rule, no `latest`.
- Also update `CHANGELOG.md` under `## [Unreleased] → ### Fixed` with a one-line entry
  (this is allowed here since it is the same revert change; keep it to one bullet).

---

## Definition of Done

- [ ] `Dockerfile` line 5 reads `FROM eclipse-temurin:21-jdk-alpine AS builder`
- [ ] `Dockerfile` line 29 reads `FROM eclipse-temurin:21-jre-alpine AS runtime`
- [ ] `grep -c 'eclipse-temurin:25' Dockerfile` → `0`
- [ ] `CHANGELOG.md` has a one-line `### Fixed` entry for the revert
- [ ] Committed and pushed to `fix/revert-temurin25-jdk-lombok-break`
- [ ] memory-bank updated with the commit SHA and task status

**Note on verification:** the `Build, Scan & Push` image build is skipped on PRs, so
it will NOT run on this branch — do not wait for it. This is a pure revert to a
base image that built and published successfully for months before #28; the image
build is validated on merge to `main`. Report the required checks (Build and Test,
Checkstyle, Integration Tests, Security Scan) green on the PR.

**Commit message (exact):**
```
fix(docker): revert Java base image to eclipse-temurin:21 (JDK 25 breaks Lombok 1.18.30)
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify `pom.xml`, `go/Dockerfile`, or any file other than `Dockerfile` and `CHANGELOG.md`
- Do NOT attempt the alternative fix (bumping Lombok) — that is a separate, deliberate change
- Do NOT commit to `main` — work on `fix/revert-temurin25-jdk-lombok-break`
- Creating the PR: leave to Claude (Claude runs /create-pr). Push the branch only.
