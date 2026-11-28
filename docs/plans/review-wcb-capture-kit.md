# Review: web console part B capture kit (blind spec review)

**Filed:** 2026-11-27
**Repo / branch:** `k3d-manager` / `k3d-manager-v1.47.0`
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Neon (agy, `gemini-4-neon-high`), role review; Fable reviews the same text separately

## Task

Review [`web-console-b-capture-kit.md`](web-console-b-capture-kit.md) against the capture plan it implements,
[`v1.45.0-web-console-b-captures.md`](v1.45.0-web-console-b-captures.md), and the code and capture files on this
branch. You get the specs and the repository, nothing else. Do not edit any file; write your review as your final answer.
No network calls; never read Keychain values; do not run `sudo`, `launchctl`, `sshd`, `cloudflared` or `security`.

Answer:

- Fidelity: does the kit keep every safety rule of the capture plan (isolation, capture authority, scratch directories,
  port single owner, token handling, filters, version header)? Where does the kit change a capture's method (for
  example running all browser profiles on the scratch LaunchDaemon, or the C15 rekey through the root driver), and does
  the change still prove what the capture plan says that capture proves?
- Root driver: is the request-file design (operator-writable `(1)/req/` read by a root process, name-only requests) safe?
  Races, symlinks, TOCTOU on the ownership check, a request arriving while a profile is mid-switch, a second driver.
  Is K4 (a) staging adequate for a root tool on two Macs?
- Recorder: can it prove C5 and C4 as the plan defines them (pty, control keys reaching the program, terminal replies,
  principal inspection before the principal match)? Anything that would make a result void without the kit noticing?
- Token path in `api`: any way the token reaches argv, env, a file, a log or a crash traceback?
- C8 validity rule and C9 prompting: are they mechanised correctly?
- Tests: can each Acceptance evidence item be built offline as described, and can each `must_not` actually fail?
  Missing positive controls, stubs not proven to be on PATH, fixtures that do not assert their target.
- Decisions K1–K4: is any recommendation wrong or missing an option? Is K1 (a)'s routing argument correct?
- Anything missing from `## Files` or `## Contract readers`.

## Files

| File | Change |
|---|---|
| `docs/plans/web-console-b-capture-kit.md` | read only (start here) |
| `docs/plans/v1.45.0-web-console-b-captures.md` | read only |
| `docs/plans/v1.45.0-web-console-ssh-behind-cloudflare-access.md` | read only |
| `docs/captures/2026-11-19-web-console/`, `docs/captures/2026-11-19-web-console-c/`, `docs/captures/2026-11-21-web-console-a-live/` | read only |
| `scripts/lib/web_console_common.sh`, `bin/k3dm-web-console-sshd` | read only |

## What NOT to Do

- Do not edit, create, stage or commit any file. Do not contact any host.

## Output

Findings most severe first, each tagged BLOCKER / MAJOR / MINOR with file:line evidence and a concrete fix, then a
verdict: READY, NEEDS FIXES, or REWRITE.

## Acceptance

```yaml
must:
  - id: M1
    text: every finding cites file:line and a concrete fix; the review ends with a verdict
must_not:
  - id: N1
    text: the reviewer changes any file or makes a network call
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: git status --short in the review worktree is empty; report has findings and a verdict
    intent: A second model checks the capture-kit spec against the capture plan before anyone builds it, so the scripts you run as root keep every safety rule.
interface: none
```
