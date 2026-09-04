# rabbitmq-client-java — Spring Boot 3.5 / Spring Cloud 2025.0.x baseline upgrade

**Filed:** 2026-08-30
**Repo (work):** `rabbitmq-client-java` (`~/src/gitrepo/personal/shopping-carts/rabbitmq-client-java`)
**Spec repo:** k3d-manager (this file)
**Type:** Dependency baseline upgrade — unblocks the payment CVE remediation
**Related:** `docs/issues/2026-08-30-payment-cve-remediation.md` (payment is PAUSED on this).

---

## Why

`shopping-cart-payment` cannot move to Spring Boot 3.5.16 (the CVE remediation) because it
transitively inherits **Spring Cloud 2023.0.0 (Leyton, Boot 3.2.x train)** from this library.
Spring Cloud's `CompatibilityVerifierAutoConfiguration` fails fast under Boot 3.5:

```
CompatibilityNotMetException: Spring Boot [3.5.16] is not compatible with this Spring Cloud
release train, action = 'Change Spring Boot version to one of the following versions [3.2.x]'
```

This library is the source of the pin, so it is the correct place to fix it (user decision
2026-08-30, Option C). It genuinely uses the Vault stack (`org.springframework.vault.core.VaultTemplate`,
`spring-cloud-starter-vault-config`, `VaultCredentialManager`, `VaultHealthIndicator`), so the
Spring Cloud train bump must be validated here against the library's own Testcontainers
(RabbitMQ + Vault) integration suite — not silenced downstream.

## Current state (verified 2026-08-30)

- Multi-module: `rabbitmq-client` (the jar payment consumes) + `rabbitmq-cli` + `rabbitmq-examples`.
- Version **1.0.1**, Java 21.
- `pom.xml` props: `<spring-boot.version>3.2.0</spring-boot.version>` (line 37),
  `<spring-cloud.version>2023.0.0</spring-cloud.version>` (line 38).
- Spring Boot + Spring Cloud imported as BOMs in `<dependencyManagement>` via those props.
- CI `.github/workflows/java-ci.yml` publishes to GitHub Packages via `mvn -B deploy` on push to `main`
  (and on release). Pre-push hook blocks direct pushes to `main` → feature branch + PR only.

## Remediation strategy

1. **Bump the two version properties** (pom.xml):
   - `<spring-boot.version>` `3.2.0` → **3.5.16** (match the payment target exactly).
   - `<spring-cloud.version>` `2023.0.0` → **2025.0.0** (the release train paired with Boot 3.5.x —
     confirm the exact latest 2025.0.x patch on Maven Central and use it).
2. **Fix compile/test breaks** across Boot 3.2→3.5 / Spring Cloud 2023→2025 / Spring Vault. Expect
   possible touch points in the Vault code (`VaultTemplate` construction/usage, `VaultCredentialManager`,
   `VaultHealthIndicator`) and Spring AMQP (`CachingConnectionFactory`, `ConnectionManager.getStats`).
   Keep changes **minimal and behaviour-preserving** — no change to credential-fetch, health, or
   connection semantics. List every code change in the commit body.
3. **Bump the library version** `1.0.1` → **1.0.2** in all module poms (parent + 3 modules) so the
   payment service can pin the new, Boot-3.5-compatible artifact. (If the maintainer prefers a
   `-SNAPSHOT` flow, that decision is Claude's to confirm — default here is a clean `1.0.2`.)
4. **Do NOT touch the payment repo.** Repinning `shopping-cart-payment`'s `<rabbitmq-client.version>`
   to `1.0.2` and finishing the payment CVE bump is Claude's downstream step after this publishes.

## Before You Start

- `cd ~/src/gitrepo/personal/shopping-carts/rabbitmq-client-java`
- Read the whole `pom.xml`, the three module poms, and the Vault/connection classes under
  `rabbitmq-client/src/main/java/com/shoppingcart/rabbitmq/`.
- **Branch (work repo): `feat/spring-boot-3.5-upgrade`** — create from `origin/main`:
  `git fetch origin && git checkout -b feat/spring-boot-3.5-upgrade origin/main`. Never commit to `main`
  (a pre-push hook blocks it anyway).
- Toolchain: JDK 21. Integration tests use Testcontainers (RabbitMQ + Vault) → they need a Docker daemon.

## Definition of Done

- [ ] `<spring-boot.version>` = 3.5.16, `<spring-cloud.version>` = latest 2025.0.x (report the exact value).
- [ ] Library version bumped `1.0.1` → `1.0.2` in parent + all module poms.
- [ ] `mvn -B clean verify` **green** (unit + failsafe integration tests). Paste the final `BUILD SUCCESS`.
      Integration tests need Docker — if the executing sandbox has no Docker/JDK, STOP and report; the
      build gate is then run by Claude in a `maven:3.9-eclipse-temurin-21` container with the Docker socket mounted.
- [ ] Every Java code change listed explicitly in the commit body; auth/Vault/connection behaviour preserved.
- [ ] Commit message (verbatim):
      `chore(deps): upgrade Spring Boot 3.2.0 -> 3.5.16 and Spring Cloud 2023.0.0 -> 2025.0.x`
- [ ] `git push origin feat/spring-boot-3.5-upgrade` — do NOT report done until the push succeeds.
- [ ] Report: commit SHA (confirmed on `origin/feat/spring-boot-3.5-upgrade`), exact chosen versions,
      the list of code changes, and the `mvn clean verify` result.

## What NOT to Do

- Do NOT clone the repo into a scratch/temp dir — work in place.
- Do NOT create a PR. (Claude gates PR creation.)
- Do NOT merge or push to `main`.
- Do NOT skip pre-commit / pre-push hooks (`--no-verify`).
- Do NOT modify the `shopping-cart-payment` repo or any k3d-manager file.
- Do NOT change Vault credential-fetch, health, connection, or AMQP semantics — dependency + compile-compat only.
- Do NOT add speculative dependency overrides — only what a failing build proves is needed.

## Rules

- `mvn -B clean verify` must pass before commit.
- LF line endings; preserve existing pom indentation.
- If the Boot 3.5 / Spring Cloud 2025 jump requires more than trivial code changes to the Vault or
  connection path, **stop and report** — that is a human-review signal on a security-sensitive path,
  not an autonomous rewrite.
