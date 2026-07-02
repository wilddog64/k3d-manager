# Issue: webhook failure analysis still shells out to retired `gemini-cli`

**Date:** 2026-07-02  
**Component:** `bin/k3dm-webhook` failure-analysis path

## Symptom

A `cluster-up` failure-analysis reply included a hard auth error from the retired Google CLI:

```text
Error authenticating: IneligibleTierError: This client is no longer supported for Gemini Code Assist for individuals. To continue using Gemini, please migrate to the Antigravity suite of products: https://antigravity.google
    at throwIneligibleOrProjectIdError (file:///opt/homebrew/lib/node_modules/@google/gemini-cli/bundle/chunk-6T7N6JF2.js:307446:11)
    at _doSetupUser (file:///opt/homebrew/lib/node_modules/@google/gemini-cli/bundle/chunk-6T7N6JF2.js:307435:5)
    at process.processTicksAndRejections (node:internal/process/task_queues:104:5) {
  ineligibleTiers: [
    {
      reasonCode: 'UNSUPPORTED_CLIENT',
      reasonMessage: 'This client is no longer supported for Gemini Code Assist for individuals. To continue using Gemini, please migrate to the Antigravity suite of products: https://antigravity.google',
      tierId: 'free-tier',
      tierName: 'Gemini Code Assist for individuals'
    }
  ]
}
```

The job itself was being killed; the failure analysis path was what emitted the CLI error.

## Root Cause

`bin/k3dm-webhook::_call_gemini()` still defaulted to `gemini`, which now resolves to the retired
`@google/gemini-cli` package on this machine. That package no longer supports the current free-tier
flow, so the analysis subprocess dies before producing any useful diagnosis.

## Fix

- Default the analysis subprocess to `agy` instead of `gemini`.
- Keep the existing `K3DM_GEMINI_BIN` override for compatibility.
- Update the user-facing how-to so it no longer instructs people to authenticate the retired CLI.

## Follow-up

Confirm the live webhook deployment is restarted after the code change so future failure analysis
uses the Antigravity CLI path.
