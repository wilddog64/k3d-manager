# Bug: `acg-up` used an escaped `curl -w` format string for Keycloak realm import status

## Status
Fixed

## What happened
While reconciling the Keycloak `argocd` client, the realm import path was found to use:

```bash
curl -sf -o /dev/null -w "%%{http_code}" ...
```

That format string returns the literal text `%{http_code}` instead of the actual HTTP status code, which makes the import result handling unreliable.

## Root Cause
The status formatter was double-escaped in the shell script.

## Fix
Changed the format string to:

```bash
curl -sf -o /dev/null -w "%{http_code}" ...
```

## Follow-up
Keep `curl -w` format strings unescaped unless the shell itself requires it. In this case, the extra `%` was a bug.
