# Order Java verify blocked by GitHub Packages auth

## What was tested

Ran the order repo Java CI equivalent locally in Docker:

```bash
docker run --rm -e GITHUB_ACTOR=codex -e GITHUB_TOKEN=dummy -v /Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-order:/w -w /w maven:3.9.9-eclipse-temurin-21 mvn -B verify -s .github/maven-settings.xml
```

## Actual output

```text
[INFO] BUILD FAILURE
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  01:21 min
[INFO] Finished at: 2026-06-18T03:21:42Z
[INFO] ------------------------------------------------------------------------
[ERROR] Failed to execute goal on project shopping-cart-order: Could not collect dependencies for project com.shoppingcart:shopping-cart-order:jar:1.0.0-SNAPSHOT
[ERROR] Failed to read artifact descriptor for com.shoppingcart:rabbitmq-client:jar:1.0.1
[ERROR] 	Caused by: The following artifacts could not be resolved: com.shoppingcart:rabbitmq-client:pom:1.0.1 (absent): Could not transfer artifact com.shoppingcart:rabbitmq-client:pom:1.0.1 from/to github-rabbitmq-client (https://maven.pkg.github.com/wilddog64/rabbitmq-client-java): status code: 401, reason phrase: Unauthorized (401)
```

## Root cause

The local Docker Maven run does not have valid GitHub Packages credentials for the
`github-rabbitmq-client` repository that serves `com.shoppingcart:rabbitmq-client:1.0.1`.
The workflow on GitHub Actions uses the real `GITHUB_TOKEN`, so this is a local auth
limitation, not a code or schema failure.

## Recommended follow-up

Re-run `mvn -B verify -s .github/maven-settings.xml` in GitHub Actions or in an environment
with a valid GitHub Packages token if a local Java verify is needed again.
