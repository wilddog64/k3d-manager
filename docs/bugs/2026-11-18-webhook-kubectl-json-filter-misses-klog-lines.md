# Webhook `_kubectl_json` drops only `Warning: ` lines; other stderr lines still fail the Vault-sealed check open

**Status:** OPEN — captured 2026-11-18 from Fable's blind diff review of PR #163 (v1.44.2), verified by Claude
**Priority:** P3 — needs external-behaviour proof before dispatch
**Introduced by:** 59dd12e5 (W1 fix, v1.44.2)
**Should have been caught by:** spec
**Introducing change reviewed:** no
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Unproven potential edge case where non-`Warning:` stderr lines from `kubectl` would cause `_kubectl_json` parsing to fail open to the LLM fallback.)
**Waiting on:** operator decision
**Prior art:** docs/bugs/2026-11-17-vault-sealed-landed-review-findings.md (W1) — read; this is a gap in that fix. `make find-similar-docs` not run (vector store unreachable).
**Filed:** 2026-11-18

## Symptom

`_kubectl_json` (`bin/k3dm-webhook:2054`) strips lines starting with exactly `Warning: `; `_posix_spawn_capture` still
merges stderr. Any other stderr line (klog `I1117 … request.go] Waited for … client-side throttling`, `E… memcache.go`)
makes `json.loads` fail, Vault reads "state unavailable", and the sealed short-circuit falls back to the LLM. Fable
confirmed this on the function with injected lines. **Unproven:** whether kubectl v1.37.2 prints such lines at default
verbosity on the hub (client-go logs long throttling waits; needs a capture per the prove-external-behaviour rule).

## Fix sketch

Parse from the first line that starts with `{` (kubectl `-o json` output starts at column 0), or capture stderr
separately for these two reads. Test: klog line before and after the JSON → sealed detected.
