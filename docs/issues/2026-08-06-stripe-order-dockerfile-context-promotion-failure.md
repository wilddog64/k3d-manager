# Stripe order image promotion failed on Dockerfile path

## What was tested

After order PR #63 merged as `800b6576c44525849628fb78329f04e0261450da`, the
`Build, Scan & Push` job `31132281743` ran with:

```text
dockerfile: Dockerfile
context: go
```

BuildKit invoked `--file Dockerfile ... go` and loaded the repository-root Java
Dockerfile. The job failed with:

```text
COPY src ./src
ERROR: ... "/src": not found
```

The Java CI and Checkstyle jobs passed; no image was published or promoted.

## Root cause

The reusable workflow's `file` input is repository-root-relative, while the
build context is `go`. The order caller passed `Dockerfile`, selecting the root
Java image instead of `go/Dockerfile`.

## Fix

Order follow-up branch `fix/stripe-live-go-dockerfile-path` changes the caller
to `dockerfile: go/Dockerfile` while retaining `context: go`.

Follow-up PR: https://github.com/wilddog64/shopping-cart-order/pull/64
