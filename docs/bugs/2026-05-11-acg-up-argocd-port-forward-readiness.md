# Bug: `acg-up` does not fail fast when the Argo CD localhost:8080 forward never becomes reachable

**Date:** 2026-05-11  
**Severity:** High — fresh `make up` can leave Safari pointing at a dead `localhost:8080`
**Status:** Fixed in `bin/acg-up`

## Symptom

After a fresh sandbox bootstrap, Safari shows:

> Safari can’t connect to the server  
> Safari can’t open the page “localhost:8080/auth/login?...” because Safari can’t connect to the server “localhost”.

That indicates the Argo CD local listener is missing, even though `make up` completed the Argo CD launchd setup step.

## Root Cause

`bin/acg-up` installs the Argo CD launchd agent and then only performs a single best-effort `curl` check. If `localhost:8080` never becomes healthy, the script logs a message and continues instead of failing fast.

That allows the rest of the bootstrap flow to proceed even though the UI listener never came up.

## Required Fix

Harden `bin/acg-up` step 4b so it:

1. waits for `http://localhost:8080/healthz` to become reachable,
2. fails the bootstrap if it does not become ready within a bounded timeout, and
3. prints the Argo CD port-forward log tail on failure.

## Fix Applied

`bin/acg-up` now waits for `http://localhost:8080/healthz` to become reachable after loading the
Argo CD launchd agent and exits non-zero with the log tail if the listener never comes up.

## Follow-up

Add a focused regression test for the Argo CD port-forward readiness gate so the bootstrap stops if
the listener never comes up.
