# Task Spec: Shopping Cart CI Stabilization — P1 + P2

**Branch:** `fix/ci-stabilization` (already cut on all repos)
**Agent:** Codex
**Priority:** P1 first, then P2

---

## Context

Five shopping-cart service repos have failing CI. This spec covers all P1 and P2 fixes.
All changes go on the `fix/ci-stabilization` branch in each affected repo.
All PRs target `main`.

**Do NOT touch:**
- Any logic outside of what is specified below
- Any file not listed in each fix section
- Do not add comments, refactor, or clean up surrounding code

---

## P1 Fix 1 — `shopping-cart-frontend`

**Repo:** `wilddog64/shopping-cart-frontend`
**Branch:** `fix/ci-stabilization`
**Failure:** TypeScript `type-check` job — 5 errors in `tsc --noEmit`

### Exact errors from CI log

```
src/components/layout/Header.tsx(3,38): error TS6133: 'Package' is declared but its value is never read.
src/components/layout/ProtectedRoute.tsx(3,10): error TS6133: 'Navigate' is declared but its value is never read.
src/config/api.ts(2,34): error TS2339: Property 'env' does not exist on type 'ImportMeta'.
src/config/api.ts(3,36): error TS2339: Property 'env' does not exist on type 'ImportMeta'.
src/config/api.ts(4,33): error TS2339: Property 'env' does not exist on type 'ImportMeta'.
src/config/auth.ts(4,34): error TS2339: Property 'env' does not exist on type 'ImportMeta'.
src/config/auth.ts(5,36): error TS2339: Property 'env' does not exist on type 'ImportMeta'.
src/config/auth.ts(6,31): error TS2339: Property 'env' does not exist on type 'ImportMeta'.
src/stores/cartStore.ts(3,21): error TS6196: 'CartItem' is declared but never used.
```

### Fix A — `src/components/layout/Header.tsx`

Current import line 3:
```ts
import { ShoppingCart, User, LogOut, Package } from 'lucide-react'
```
Change to:
```ts
import { ShoppingCart, User, LogOut } from 'lucide-react'
```

### Fix B — `src/components/layout/ProtectedRoute.tsx`

Current import line 3:
```ts
import { Navigate, useLocation } from 'react-router-dom'
```
Change to:
```ts
import { useLocation } from 'react-router-dom'
```

### Fix C — `src/stores/cartStore.ts`

Current import line 3:
```ts
import type { Cart, CartItem } from '@/types'
```
Change to:
```ts
import type { Cart } from '@/types'
```

### Fix D — `tsconfig.json`

Current `compilerOptions` has no `types` field. Add `"types": ["vite/client"]`:

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "types": ["vite/client"],
    ...
  }
}
```

Add `"types": ["vite/client"]` after the `"lib"` line. Do not change any other field.

### Commit message

```
fix: resolve TypeScript type-check errors blocking CI

- Remove unused Package import from Header.tsx
- Remove unused Navigate import from ProtectedRoute.tsx
- Remove unused CartItem type import from cartStore.ts
- Add "types": ["vite/client"] to tsconfig.json to fix ImportMeta.env errors
```

---

## P1 Fix 2 — `shopping-cart-product-catalog`

**Repo:** `wilddog64/shopping-cart-product-catalog`
**Branch:** `fix/ci-stabilization`
**Failure:** `Build, Scan & Push / build-push` — Trivy scan exits 1 on fixable HIGH/CRITICAL CVEs in `python:3.11-slim` base image

### Fix — `Dockerfile`

Add `RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*` to both
the builder stage and the runtime stage, immediately after each `FROM` line.

**Builder stage** — after `FROM python:3.11-slim as builder` + `WORKDIR /app`:

```dockerfile
FROM python:3.11-slim as builder

WORKDIR /app

RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
```

**Runtime stage** — after `FROM python:3.11-slim`:

```dockerfile
FROM python:3.11-slim

# Upgrade system packages to pick up security patches
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd -r appgroup && useradd -r -g appgroup -u 1000 appuser
```

Do not change any other part of the Dockerfile.

### Commit message

```
fix: upgrade system packages in Docker image to resolve Trivy HIGH/CRITICAL CVEs

Add apt-get upgrade to both builder and runtime stages so all system
packages are patched before Trivy scan runs.
```

---

## P2 Fix 1 — `shopping-cart-payment`

**Repo:** `wilddog64/shopping-cart-payment`
**Branch:** `fix/ci-stabilization`
**Failure:** `Build and Test` job — `./mvnw` fails with:
`-Dmaven.multiModuleProjectDirectory system property is not set.`

### Fix — `.github/workflows/ci.yaml`

Add `-Dmaven.multiModuleProjectDirectory=.` to every `./mvnw` invocation.

Find all lines containing `./mvnw` and append the flag. There are 3 occurrences:

1. `run: ./mvnw clean package -DskipTests -B`
   → `run: ./mvnw clean package -DskipTests -B -Dmaven.multiModuleProjectDirectory=.`

2. `run: ./mvnw test -B`
   → `run: ./mvnw test -B -Dmaven.multiModuleProjectDirectory=.`

3. `run: ./mvnw verify -P integration-tests -B`
   → `run: ./mvnw verify -P integration-tests -B -Dmaven.multiModuleProjectDirectory=.`

### Commit message

```
fix: add -Dmaven.multiModuleProjectDirectory=. to mvnw invocations

Fixes "system property is not set" error when Maven wrapper initializes
in GitHub Actions environment.
```

---

## P2 Fix 2 — `rabbitmq-client-java` + `shopping-cart-order`

**Repos:** `wilddog64/rabbitmq-client-java` AND `wilddog64/shopping-cart-order`
**Branch:** `fix/ci-stabilization` on both repos
**Failure:** `shopping-cart-order` Build & Test fails:
`Could not find artifact com.shoppingcart:rabbitmq-client:jar:1.0.0-SNAPSHOT`

The `rabbitmq-client-java` repo (multi-module: parent `rabbitmq-client-parent`, submodule
`rabbitmq-client` with groupId `com.shoppingcart` artifactId `rabbitmq-client`) exists but
has no GitHub Packages publish step in its CI.

### Fix A — `rabbitmq-client-java`: add publish job to `.github/workflows/java-ci.yml`

Add a `publish` job after the existing `build` job:

```yaml
  publish:
    name: Publish to GitHub Packages
    runs-on: ubuntu-latest
    needs: [build]
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up JDK
        uses: actions/setup-java@v4
        with:
          java-version: ${{ env.JAVA_VERSION }}
          distribution: 'temurin'
          cache: maven

      - name: Publish to GitHub Packages
        run: mvn -B deploy -DskipTests
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### Fix B — `rabbitmq-client-java`: add `distributionManagement` to root `pom.xml`

Add inside the `<project>` element (after `<description>`):

```xml
    <distributionManagement>
        <repository>
            <id>github</id>
            <name>GitHub Packages</name>
            <url>https://maven.pkg.github.com/wilddog64/rabbitmq-client-java</url>
        </repository>
    </distributionManagement>
```

### Fix C — `rabbitmq-client-java`: add `settings.xml` for authentication

Create `.github/maven-settings.xml`:

```xml
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">
  <servers>
    <server>
      <id>github</id>
      <username>${env.GITHUB_ACTOR}</username>
      <password>${env.GITHUB_TOKEN}</password>
    </server>
  </servers>
</settings>
```

Update the publish job's `mvn deploy` command to use it:
```yaml
        run: mvn -B deploy -DskipTests -s .github/maven-settings.xml
```

### Fix D — `shopping-cart-order`: add GitHub Packages repository to `pom.xml`

In `shopping-cart-order/pom.xml`, add a `<repositories>` section so Maven can resolve
the published `rabbitmq-client`:

```xml
    <repositories>
        <repository>
            <id>github-rabbitmq-client</id>
            <name>GitHub Packages — rabbitmq-client-java</name>
            <url>https://maven.pkg.github.com/wilddog64/rabbitmq-client-java</url>
        </repository>
    </repositories>
```

Also add `.github/maven-settings.xml` to `shopping-cart-order`:

```xml
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">
  <servers>
    <server>
      <id>github-rabbitmq-client</id>
      <username>${env.GITHUB_ACTOR}</username>
      <password>${env.GITHUB_TOKEN}</password>
    </server>
  </servers>
</settings>
```

Update `shopping-cart-order/.github/workflows/ci.yml` build step:
```yaml
      - name: Build with Maven
        run: mvn -B verify -s .github/maven-settings.xml
```

### Commit messages

**rabbitmq-client-java:**
```
fix: add GitHub Packages publish job and distributionManagement

Enables shopping-cart-order to resolve com.shoppingcart:rabbitmq-client
as a Maven dependency from GitHub Packages.
```

**shopping-cart-order:**
```
fix: add GitHub Packages repository for rabbitmq-client dependency

Configures Maven to resolve com.shoppingcart:rabbitmq-client:1.0.0-SNAPSHOT
from wilddog64/rabbitmq-client-java GitHub Packages.
```

---

## Execution Order

1. P1 fixes first — `shopping-cart-frontend` and `shopping-cart-product-catalog` are independent
2. P2 fixes — do `rabbitmq-client-java` publish first, then `shopping-cart-order`
3. All PRs: `fix/ci-stabilization` → `main`
4. After each PR merges, verify the CI run on `main` passes

## Verification

After each fix is committed on `fix/ci-stabilization`:
- Run `gh pr create` targeting `main`
- Confirm CI passes on the PR before merging
- Do NOT merge until CI is green

## Memory-bank update

When complete, update `k3d-manager/memory-bank/progress.md` and `activeContext.md`:
- Mark each P1/P2 item done with commit SHA
- Note which CI jobs are now passing
