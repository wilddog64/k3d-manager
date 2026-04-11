# Spec: shopping-cart-order — bump rabbitmq-client to 1.0.1

## Context

`order-service` pods are in `CrashLoopBackOff` because `RabbitMQHealthIndicator`
(inside `rabbitmq-client-1.0.0-SNAPSHOT.jar`) throws a `NullPointerException` in
`ConnectionManager.getStats()` before the first AMQP channel is opened. The liveness
probe hits `/actuator/health` → sees DOWN → Kubernetes kills the pod → loop.

`rabbitmq-client v1.0.1` (merged 2026-04-11, PR #4) fixes the NPE with a try/catch in
`getStats()`. The released jar is in GitHub Packages.

A local workaround `RabbitHealthConfig.java` was added in commit `c813340` to guard the
health check, but it uses the wrong bean name (`"rabbitHealthIndicator"`) versus the
library's bean (`"rabbitMQHealthIndicator"`), so both run in parallel and the NPE is never
intercepted. The workaround must be deleted when bumping to `1.0.1`.

When this PR merges to `main`, the existing `publish` CI job invokes the reusable
`build-push-deploy.yml` from `shopping-cart-infra`, which:
1. Builds a new Docker image with `rabbitmq-client-1.0.1` embedded
2. Pushes `ghcr.io/wilddog64/shopping-cart-order:sha-<sha>` and `:latest`
3. Updates `k8s/base/kustomization.yaml` `newTag` to `sha-<sha>` and commits to `main`
4. ArgoCD detects the kustomization change and deploys the fixed image automatically

---

## Before You Start

```
Branch (shopping-cart-order): fix/rabbitmq-client-1.0.1

git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-order \
  fetch origin && \
  git checkout -b fix/rabbitmq-client-1.0.1 origin/main
```

Read these files in full before touching anything:
- `pom.xml`
- `src/main/java/com/shoppingcart/order/config/RabbitHealthConfig.java`
- `src/test/java/com/shoppingcart/order/config/RabbitHealthConfigTest.java`
- `CHANGELOG.md`

---

## Changes

### 1. `pom.xml` — bump dependency, remove TODO comment

**Old (lines 48–54):**
```xml
        <!-- RabbitMQ Client Library (local dependency) -->
        <!-- TODO: Replace with Maven coordinates once published -->
        <dependency>
            <groupId>com.shoppingcart</groupId>
            <artifactId>rabbitmq-client</artifactId>
            <version>1.0.0-SNAPSHOT</version>
        </dependency>
```

**New:**
```xml
        <!-- RabbitMQ Client Library -->
        <dependency>
            <groupId>com.shoppingcart</groupId>
            <artifactId>rabbitmq-client</artifactId>
            <version>1.0.1</version>
        </dependency>
```

### 2. Delete `RabbitHealthConfig.java`

```
src/main/java/com/shoppingcart/order/config/RabbitHealthConfig.java
```

This class was a workaround for the NPE that is now fixed in `1.0.1`. It also used the
wrong bean name so it never intercepted the failing call. Delete the file entirely.

### 3. Delete `RabbitHealthConfigTest.java`

```
src/test/java/com/shoppingcart/order/config/RabbitHealthConfigTest.java
```

Test for the deleted class. Delete the file entirely.

### 4. `CHANGELOG.md` — add entry under `[Unreleased]`

Add under the existing `### Changed` section (or create it if absent):

```markdown
### Changed
- Bump `rabbitmq-client` dependency from `1.0.0-SNAPSHOT` to `1.0.1`; remove
  `RabbitHealthConfig` workaround — NPE in `ConnectionManager.getStats()` is fixed
  at source in `1.0.1`, eliminating the `CrashLoopBackOff` on pod startup
```

---

## Files Changed

| File | Action |
|------|--------|
| `pom.xml` | Edit — bump version, remove TODO comment |
| `src/main/java/com/shoppingcart/order/config/RabbitHealthConfig.java` | Delete |
| `src/test/java/com/shoppingcart/order/config/RabbitHealthConfigTest.java` | Delete |
| `CHANGELOG.md` | Edit — add entry under `[Unreleased]` |

---

## Rules

- Run `mvn -B verify -s .github/maven-settings.xml` locally with `GITHUB_TOKEN` set — build must pass before committing
- No other files modified
- Do NOT commit to `main` — work on `fix/rabbitmq-client-1.0.1` only
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)

---

## Definition of Done

- [ ] `pom.xml` shows `<version>1.0.1</version>` for `rabbitmq-client`, TODO comment removed
- [ ] `RabbitHealthConfig.java` is deleted
- [ ] `RabbitHealthConfigTest.java` is deleted
- [ ] `CHANGELOG.md` has the entry under `[Unreleased]`
- [ ] Commit message (exact):
  ```
  fix(deps): bump rabbitmq-client to 1.0.1; remove RabbitHealthConfig workaround
  ```
- [ ] Branch pushed: `git push origin fix/rabbitmq-client-1.0.1`
- [ ] SHA reported back

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the four listed above
- Do NOT commit to `main`
- Do NOT modify `k8s/base/kustomization.yaml` — CI updates it automatically after merge
- Do NOT add or modify Docker/CI workflows — the `publish` job already handles Docker build + push
