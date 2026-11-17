# dispatch stall probe: the DB fallback matches by the newest agy log, which on a resumed run is newer than the conversation DB

**Status:** OPEN — captured 2026-11-17 from Argon's blind review of PR #162 (v1.44.1), verified by Claude
**Priority:** P3 — only used when `lsof` cannot see the open conversation DB; worst case a stall sample is missing or counts another task's steps
**Introduced by:** f3828ad9 (stall detector A1, k3d-manager-v1.44.1)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision
**Prior art:** none above threshold. Exact slug: no match; keyword grep of docs/bugs: no match. `make find-similar-docs` not run (vector store unreachable from this machine: no k3d-k3d-cluster context).
**Filed:** 2026-11-17

## Symptom

When `lsof` finds no open `.db` for the worker, `_dispatch_stall_db_sample` (`bin/k3dm-codex-dispatch:1056-1068`) takes the newest `agy*.log` from `_dispatch_stall_newest_log` and picks the one conversation DB created within 10 s after that log. On a resumed run the newest log is `agy-<n>.log` (written at resume, `bin/k3dm-codex-dispatch:230`), but the resume reuses the original conversation (`--conversation "$session_id"`), whose DB is older. So the fallback finds nothing, or a different task's DB if one was created within those 10 s.

## Verified by Claude (2026-11-17)

Read the code at the lines above. The run's `session` file already holds the conversation ID for agy resumes and is the better source. Not reproduced live.
