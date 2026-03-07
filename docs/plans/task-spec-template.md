# Task Spec Template

All task specs issued to agents must follow this format.
The **Change Checklist** is mandatory — agents must tick off only listed items.
Any change not on the checklist is forbidden, even if it seems like an improvement.

---

# [version] — [Agent] Task: [Short Title]

## Context

[1-3 sentences explaining why this task exists and what triggered it.]

---

## Critical Rules

1. **Edit only the files and lines listed in the Change Checklist below. Nothing else.**
2. Do not modify test files unless explicitly listed.
3. Run `shellcheck` on every touched `.sh` file and report output.
4. Commit your own work — self-commit is your sign-off.
5. **Push your branch and confirm CI is green before updating memory-bank.** Use `gh run list --repo <owner>/<repo> --limit 3` to verify. Never report COMPLETE without a green CI run URL.
6. Update memory-bank to report completion — include the CI run URL.
7. **NEVER run `git rebase`, `git reset --hard`, or `git push --force`.**

---

## Change Checklist

Tick each item as you complete it. Do not add items.

- [ ] `path/to/file.sh` line NNN — [exact description of change]
- [ ] `path/to/file.sh` line NNN — [exact description of change]

**Forbidden:** Any line, file, or pattern not listed above.

---

## Expected Result

[What the code should look like after the change. Include before/after snippets.]

```bash
# Before:
<old code>

# After:
<new code>
```

---

## Verification

[Exact commands to run to confirm the fix works. Include expected output.]

```bash
<verification command>
```

**For BATS test tasks — always verify in a clean environment:**

```bash
# Unset residual shell state before running — catches env-dependent false positives
env -i HOME="$HOME" PATH="$PATH" ./scripts/k3d-manager test <suite> 2>&1 | tail -10
```

Never report a test as passing if it was only run in an interactive shell session
where `SCRIPT_DIR`, `CLUSTER_PROVIDER`, or other k3d-manager env vars may be set.

---

## Completion Report (required)

Update memory-bank with:
```
Task: [title]
Status: COMPLETE / BLOCKED
Files changed: [list]
Shellcheck: PASS / [issues found]
CI run: [URL from gh run list] — PASS / FAIL / not applicable
Verification: [output]
Unexpected findings: [anything outside task scope — report, do not fix]
```

**Do not set Status: COMPLETE without a green CI run URL. No CI URL = not done.**
