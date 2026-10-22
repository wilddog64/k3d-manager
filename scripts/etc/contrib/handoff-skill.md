# /handoff

Prepare and validate a task handoff to an AI agent. Usage: `/handoff codex` or `/handoff gemini`.

The argument specifies the target agent. If no argument is given, ask the user which agent.

---

## Steps — both agents

1. **Confirm the spec exists** — check `docs/plans/` for the task spec file. If it does not exist, stop and write it first.

2. **Verify the spec has all required sections:**
   - `## Before You Start` — memory-bank read + git pull + target file reads
   - `## Definition of Done` — checkbox list with exact commit message and SHA report requirement
   - `## What NOT to Do` — must include:
     - Do NOT update `memory-bank/` — Claude will do that after verifying the SHA
     - Do NOT create a PR
     - Do NOT skip pre-commit hooks (`--no-verify`)
     - Do NOT modify files outside the listed targets

3. **Push the branch** — agent must be able to `git pull` to get the latest spec:
   ```bash
   git push origin $(git branch --show-current)
   ```

4. **Confirm memory-bank is current** — `memory-bank/activeContext.md` and `memory-bank/progress.md` must reflect the task as assigned before the agent starts.

---

## Handoff block — Codex

**Multi-repo tasks:** If the spec targets repos OTHER than k3d-manager, make the
distinction explicit in the handoff block — separate "get the spec" step from
"do the work" step so Codex doesn't confuse the spec repo with the work repos.

Print this for copy-paste to Codex:

**Single-repo task (work is in k3d-manager):**
```
Branch: <current branch>
Spec: docs/plans/<spec-file>.md
First: git pull origin <branch>
Then: read the spec in full — implement exactly what is written, no interpretation
Commit message: <exact message from spec>
Report back: commit SHA only — do NOT update memory-bank
```

**Multi-repo task (work is in other repos):**
```
Step 1 — get the spec: git pull origin <branch> in k3d-manager repo
Step 2 — read: docs/plans/<spec-file>.md in full before touching anything
Step 3 — work in: <list target repos and their branches>
Commit message (all repos): <exact message from spec>
Report back: one SHA per repo — do NOT update memory-bank
```

**Additional Codex checks:**
- Spec must have exact old/new code blocks (not descriptions — literal code)
- `## Rules` must include shellcheck + test run gates

---

## Handoff block — Gemini

**Multi-repo tasks:** Same distinction as Codex — separate "get the spec" from "do the work."

Print this for copy-paste to Gemini:

**Single-repo task:**
```
Branch: <current branch>
Spec: docs/plans/<spec-file>.md
First command: hostname && uname -n
Then: git pull origin <branch> && read the spec in full before doing anything
```

**Multi-repo task:**
```
First command: hostname && uname -n
Step 1 — get the spec: git pull origin <branch> in k3d-manager repo
Step 2 — read: docs/plans/<spec-file>.md in full before doing anything
Step 3 — work in: <list target repos and their branches>
```

---

## Checklist (Claude verifies after agent reports done)

### Codex
- [ ] SHA exists: `git log <branch> --oneline | grep <sha>`
- [ ] Diff matches spec: `git show <sha> --stat` + `git show <sha>`
- [ ] Only spec-listed files touched (no memory-bank, no issue docs, no unrelated files)
- [ ] shellcheck passes with zero new warnings
- [ ] BATS tests pass if spec required them
- [ ] Commit message matches spec exactly

### Gemini
- [ ] Gemini reported actual command output, not a summary
- [ ] SHA exists: `git log <branch> --oneline | grep <sha>`
- [ ] Diff matches spec: `git show <sha>`
- [ ] Memory-bank updated by Gemini with results
- [ ] No scope creep — diff touches only files in spec

---

## Known Codex Failure Modes (check for these)

- Reads the wrong spec (wrong version number) — verify he named the correct file
- Updates memory-bank despite explicit prohibition — do not revert if content is accurate, but note it
- Adds unsolicited refactors — flag if functional impact
- Reports done after completing only the first file of multiple — check `--stat` carefully
- Fabricates a SHA — always `git log` to confirm it exists on the branch
