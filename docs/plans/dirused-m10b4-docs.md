# dirused M10b4: docs for scheduled purge

**Status:** OPEN — SPEC rev 2, 2026-11-23; starts after M10b3 lands; awaiting intent approval
**Tracked:** separately from k3d-manager releases (OOB repo). This file sits in k3d-manager only so `codex-dispatch start` can read it.
**Parent:** [M10b](dirused-m10b-scheduled-purge.md) §9. Fourth of four; after [M10b3](dirused-m10b3-runplan-windows.md).
**Repo / branch:** wilddog64/dirused / `m10b-scheduled-purge`
**Risk:** low — docs only
**Implementer:** Flash
**Verifier:** Claude, offline
**Filed:** 2026-11-23
**Intent approved:** pending
**Approval:** operator, 2026-11-23 — split, docs as the last child

## Change

- `docs/purge.md`: new "Scheduled purge" section: the three `/schedule` forms (preview, `/confirm`, `/confirm /yes`) with the preview
  shown; time and zone rules; logged-on only (disconnected is fine; signed out → `missed`); held files are skipped and Tomcat is never
  stopped by a scheduled run (stop/start is M10d); the plan folder and program copy and why; every `/schedule /list` state with its
  meaning, including `interrupted` and `permissions changed — not run`; `/schedule /cancel`; every `/runplan` refusal and what to do;
  the report format; scheduling per node (the host comes from the list's UNC paths; save one list per server with `/savelist` and
  schedule each; a multi-host list is refused; `/schedule /list` shows each plan's host); a console window may flash at run time; old plan folders are not cleaned up yet.
- `README.md`: usage lines matching `ArgParser` and one preview-then-confirm example.
- `CHANGELOG.md`: `[Unreleased]` bullets for M10b1–M10b3; no new version header.

## Files

`docs/purge.md`, `README.md`, `CHANGELOG.md` only.

## Acceptance

```yaml
must:
  - id: B4-M1
    text: "docs/purge.md has a 'Scheduled purge' section covering each item in Change, including a per-node example with two servers; README usage text equals ShortUsageText's /schedule lines; CHANGELOG [Unreleased] has the bullets and no new version header; every refusal string in M10b3's interface appears in docs/purge.md"
evidence:
  - id: E-B4
    proves: [B4-M1]
    kind: offline
    command: "git diff --stat shows only the three files; for each M10b3 interface 'refused:' string, grep -F finds it in docs/purge.md; diff of README usage block against ArgParser ShortUsageText /schedule lines is empty"
    intent: "The guide tells you how to preview, schedule, check and cancel a purge, why held logs are skipped, and what each state and refusal means."
interface:
  - "docs/purge.md#scheduled-purge"
```
