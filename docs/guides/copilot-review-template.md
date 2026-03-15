# Copilot Review Record — Template

Copy this file to `docs/issues/YYYY-MM-DD-<feature>-copilot-review.md` for each PR
that received a Copilot review. Fill in every section. Do not leave placeholders.

---

## Header

| Field | Value |
|---|---|
| Date | YYYY-MM-DD |
| Repo | `owner/repo` |
| PR | [#N — title](https://github.com/owner/repo/pull/N) |
| Branch | `feature-branch-name` |
| Reviewed commit | `<sha>` |
| Copilot review rounds | N |
| Total findings | N (P1: N · P2: N · Nit: N) |
| All resolved | Yes / No |

---

## Quick Summary

> One paragraph. What was reviewed, what Copilot caught, what was fixed.
> Written for someone who was not in the PR and has 30 seconds.

---

## Finding Index

| # | Severity | File | Short description | Status |
|---|---|---|---|---|
| 1 | P1 | `scripts/foo.sh` | What the bug is in 10 words | Fixed `abc1234` |
| 2 | P2 | `scripts/bar.sh` | What the bug is in 10 words | Fixed `abc1234` |
| 3 | Nit | `README.md` | What the nit is in 10 words | Fixed `abc1234` |

**Severity guide:**
- **P1** — correctness or security bug; would cause data loss, broken functionality, or a
  vulnerability in any realistic use. Must fix before merge.
- **P2** — latent bug or design flaw; works today but breaks under plausible conditions
  (wrong OS, edge-case input, environment variation). Fix before merge when feasible.
- **Nit** — style, consistency, or docs issue with no functional impact. Fix opportunistically.

---

## Findings

### Finding 1 — `<short title>` (P1 / P2 / Nit)

**File:** `path/to/file.sh` line N

**Problem:**
What the code does today. Why it is wrong. What breaks and under what conditions.
Be specific: include the bad line or pattern if it helps.

**Fix:**
What was changed. Why the fix is correct.

**Commit:** `<sha>`

---

### Finding 2 — `<short title>` (P1 / P2 / Nit)

**File:** `path/to/file.sh` line N

**Problem:**
...

**Fix:**
...

**Commit:** `<sha>`

---

<!-- Repeat for each finding -->

---

## Lessons

Short, reusable takeaways. Write these so a future agent or engineer can learn from them
without reading the full finding detail.

- **Lesson title** — one sentence explanation. Example: "Bash inner functions are always
  global — never define helpers inside another function without a collision-resistant name."
- **Lesson title** — ...

---

## Process Notes (optional)

Anything about the review process itself worth capturing — number of rounds needed,
whether Copilot flagged the same issue twice, review latency, etc.
