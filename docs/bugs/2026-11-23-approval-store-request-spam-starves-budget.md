# Bug: approval store: same-uid request spam holds the pending slot and hourly budget; records never pruned

**Status:** OPEN — captured 2026-11-23
**Priority:** P3
**Classified:** P2 by gemini-4-argon-medium, 2026-11-25 — same-uid request spam can exhaust the approval rate limit and leave final records unpruned, with local process termination or store cleanup as workarounds
**Triage:** carry → v1.47.0 — triage 2026-11-25, operator ("go with your recommendation"); was: next-minor → v1.47.0 candidate at the next /release-groom (operator, 2026-11-25); Argon blind classification, Claude verified
**Branch:** `k3d-manager-v1.47.0`
**Introduced by:** v1.45.0 plan 2a (approval store)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-25
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unavailable: cluster context missing); grep of docs/bugs for the key terms found no match
**Detected by:** v1.45.0 red-team gate, 2026-11-22, on `7dfb7238` — see [docs/issues/2026-11-23-v1.45.0-red-team.md](../issues/2026-11-23-v1.45.0-red-team.md)
**Severity:** denial of service on remote promotion; unbounded record growth.
**Findings:** Fable 7 (Low). Claude: plausible, P3.

## What is wrong

`scripts/lib/hub_approval.py:327-331`: one pending record, 3 per hour, 5 non-final. A same-uid process requesting every 15 minutes
keeps the operator's request `rate_limited`. Final records are never pruned; the daemon serves one client at a time.

## Fix direction

Approver-authenticated cancel of a pending record; prune final records by age; per-connection timeout.
