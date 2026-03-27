# Issue: ACG Session E2E Test Failure — 2026-03-27

## Description
The E2E live test for `_antigravity_ensure_acg_session` failed because the `gemini` CLI tool encountered a `429 RESOURCE_EXHAUSTED` error from the Google AI backend. The model `gemini-3.1-pro-preview` reported "No capacity available on the server."

## Environment
- Machine: `m4-air.local`
- Branch: `k3d-manager-v0.9.17`
- Browser: Antigravity (CDP port 9222)

## Verbatim Output
```
INFO: Checking ACG session in Antigravity browser...
Keychain initialization encountered an error: An unknown error occurred.
Using FileKeychain fallback for secure storage.
Loaded cached credentials.
Attempt 1 failed with status 429. Retrying with backoff... GaxiosError: [{
  "error": {
    "code": 429,
    "message": "No capacity available for model gemini-3.1-pro-preview on the server",
    "errors": [
      {
        "message": "No capacity available for model gemini-3.1-pro-preview on the server",
        "domain": "global",
        "reason": "rateLimitExceeded"
      }
    ],
    "status": "RESOURCE_EXHAUSTED",
    "details": [
      {
        "@type": "type.googleapis.com/google.rpc.ErrorInfo",
        "reason": "MODEL_CAPACITY_EXHAUSTED",
        "domain": "cloudcode-pa.googleapis.com",
        "metadata": {
          "model": "gemini-3.1-pro-preview"
        }
      }
    ]
  }
}
]
```

## Root Cause
Server-side capacity limits for the `gemini-3.1-pro-preview` model.

## Recommended Follow-up
Retry the test when server capacity is restored or investigate if a different model can be used by the `gemini` CLI.
