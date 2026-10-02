# Bug: payment image carries 3 CRITICAL Tomcat CVEs that the latest Spring Boot BOM does not fix

**Filed:** 2026-10-02
**Status:** FIXED payment `90e3052` on `fix/payment-cve-bom-overrides` (Codex; Claude-verified: pom.xml only, effective-pom re-run shows all 5 fixed versions, branch CI 37068823246 green, 139 unit + 139 integration tests = main); PR pending merge, then Rollout
**Repo (work):** `wilddog64/shopping-cart-payment` (`~/src/gitrepo/personal/shopping-carts/shopping-cart-payment`)
**Branch (work repo):** `fix/payment-cve-bom-overrides`, from `origin/main`
**Spec branch:** `k3d-manager-v1.41.0`
**Found by:** hub Grafana "Firing Alerts by Category": Trivy CRITICAL on `wilddog64/shopping-cart-payment`, cluster `ubuntu-hostinger`
**Related:** `docs/issues/2026-08-30-payment-cve-remediation.md` (the earlier BOM bump; this is a recurrence with new CVEs)

## Symptom

The hostinger trivy-operator VulnerabilityReport for `payment-service` (image `sha-cced344…@sha256:50253e83…`), 2026-10-02:

| Package | Installed | Severity | Fixed in |
|---|---|---|---|
| org.apache.tomcat.embed:tomcat-embed-core | 10.1.55 | 3 CRITICAL (CVE-2026-65182, -65905, -68525) | 10.1.58 |
| com.fasterxml.jackson.core:jackson-core / jackson-databind | 2.21.4 | 5 HIGH | 2.21.7 |
| com.rabbitmq:amqp-client | 5.25.0 | 4 HIGH | 5.34.0 |
| org.apache.httpcomponents.core5:httpcore5 (+h2) | 5.3.6 | 2 HIGH | 5.4.3 |
| org.postgresql:postgresql | 42.7.11 | 1 HIGH | 42.7.12 |

## Root cause

All five come from the Spring Boot BOM. `pom.xml` has not changed since `cced344`, and `spring-boot-starter-parent`
**3.5.16 is the latest 3.5.x** on Maven Central. Its BOM pins exactly the vulnerable versions:
`tomcat.version 10.1.55`, `jackson-bom.version 2.21.4`, `rabbit-amqp-client.version 5.25.0`,
`httpcore5.version 5.3.6`, `postgresql.version 42.7.11` (confirmed locally with `help:effective-pom`). Re-pinning
the image to a newer build therefore changes nothing; the fix is BOM override properties, which the 2026-08-30
remediation already allowed for.

Separately, hostinger runs `cced344` because its digest pin
(`k3d-manager: services/shopping-cart-payment/kustomization.yaml:34`) is updated by hand and was last moved in
v1.37.0. That re-pin is Claude's downstream step (see Rollout), not part of this spec.

## Fix (payment repo, `pom.xml` only)

In the `<properties>` block. Old:
```xml
        <testcontainers.version>1.21.4</testcontainers.version>
    </properties>
```
New:
```xml
        <testcontainers.version>1.21.4</testcontainers.version>
        <!-- CVE overrides: Spring Boot 3.5.16 BOM still ships these vulnerable versions (Trivy, 2026-10-02).
             Drop each one once the parent BOM reaches it. -->
        <tomcat.version>10.1.60</tomcat.version>
        <jackson-bom.version>2.21.7</jackson-bom.version>
        <rabbit-amqp-client.version>5.34.0</rabbit-amqp-client.version>
        <httpcore5.version>5.4.4</httpcore5.version>
        <postgresql.version>42.7.13</postgresql.version>
    </properties>
```

No other file changes. No parent version change (3.5.16 is already the latest 3.5.x).

## Gate (paste output)

Use JDK 21: `export JAVA_HOME=/opt/homebrew/opt/openjdk@21` (`/usr/bin/java` is the macOS stub). The full Maven
build can't run locally (the private `rabbitmq-client` package needs GitHub Packages auth), but the effective POM can.

1. `./mvnw -q -B help:effective-pom -Doutput="$TMPDIR/eff.xml"` exits 0, and
   `grep -A1 -E '<artifactId>(tomcat-embed-core|jackson-databind|amqp-client|httpcore5|postgresql)</artifactId>' "$TMPDIR/eff.xml" | grep -o '<version>[^<]*' | sort -u`
   shows `10.1.60`, `2.21.7`, `5.34.0`, `5.4.4` and `42.7.13`, and none of `10.1.55`, `2.21.4`, `5.25.0`, `5.3.6`, `42.7.11`.
2. `git diff --stat origin/main` shows only `pom.xml`.
3. Push the branch. `ci.yaml` runs on the push; **Build and Test**, **Integration Tests**, **Checkstyle & SpotBugs**
   and **Security Scan** must all succeed. Report the run id and the unit-test count from the Build and Test log
   (`Tests run: N, Failures: 0`).

If the build fails because of the `httpcore5` 5.4 line (the BOM's `httpclient5` 5.5.2 was built against core 5.3.6),
stop and report the failing test or compile error; do not swap in other versions on your own.

## Definition of Done

- [ ] Fix applied exactly; only `pom.xml` changed
- [ ] Gates 1–3 output pasted
- [ ] Commit message: `fix(deps): override Tomcat, Jackson, amqp-client, httpcore5 and PostgreSQL to clear CRITICAL/HIGH CVEs`
- [ ] Pushed to `origin/fix/payment-cve-bom-overrides`; report `git rev-parse origin/fix/payment-cve-bom-overrides`

## What NOT to Do

- Do NOT create a PR; do NOT merge
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files other than `pom.xml`
- Do NOT commit to `main`, and do NOT build off `fix/payment-java-response-gateway-transaction-id` (PR #80)
- Do NOT change the Spring Boot parent version
- Do NOT edit the k3d-manager pins or the memory-bank

## Rollout (Claude, after merge)

1. Wait for the `main` image `sha-<merge>`; confirm the CI Trivy scan is clean of these CVEs.
2. Re-pin hostinger: `services/shopping-cart-payment/kustomization.yaml` `digest` → the new image digest.
3. Bump the e2e substrate pin `scripts/etc/e2e/kustomization.yaml` (shared with the PR #80 follow-up).
4. Confirm the hostinger VulnerabilityReport shows 0 CRITICAL for `payment-service` and the Trivy alert clears.
