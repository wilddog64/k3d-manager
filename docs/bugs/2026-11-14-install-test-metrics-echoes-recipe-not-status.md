# Bug: `make install-test-metrics` echoes its recipe instead of reporting status

**Status:** OPEN — captured 2026-11-14 by Claude (operator request)
**Priority:** P3
**Waiting on:** dispatch — since 2026-11-14
**Triage:** passed over (1st), unassigned — operator grooming 2026-11-15 (v1.45.0 at the 10-P3 cap: "Pass over today's 3")
**Introduced by:** pre-existing
**Should have been caught by:** review
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Cosmetic output issue where `make install-test-metrics` echoes raw recipe lines rather than reporting load status while installation still succeeds.)
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unreachable from the M4)

## Symptom

On the M5 (2026-11-14), `make install-test-metrics` printed the raw `sed` and `launchctl` shell code
(`Makefile:107-117`, no `@` prefix) and nothing after it. The operator asked for the status of the
run instead of the code. The install did work: `launchctl print gui/<uid>/com.k3d-manager.test-metrics`
over SSH showed the agent loaded (`state = not running`, `runs = 0`), but the output never said so.

## Fix direction

- Prefix the recipe lines with `@`.
- Print one status line per step, e.g.
  `[install-test-metrics] wrote ~/Library/LaunchAgents/com.k3d-manager.test-metrics.plist`,
  `[install-test-metrics] loaded gui/<uid>/com.k3d-manager.test-metrics` (or
  `skipped load (K3DM_AGENT_LOAD=0)`), and a final check from `launchctl print` (loaded yes/no).
- Exit non-zero if `launchctl bootstrap` fails or the agent is not loaded afterwards.
- Offline test with a stub `launchctl` and a scratch HOME: no `sed`/`launchctl` command text in the
  output, status lines present, rc non-zero when the stub bootstrap fails.

Batch with other Makefile P3s; the Makefile is busy until `parallel-offline-tests-b` lands (one
dispatch per file).
