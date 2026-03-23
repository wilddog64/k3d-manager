# Contributed Scripts and Templates — `scripts/etc/contrib/`

Reusable scripts and templates for projects using the spec-driven multi-agent workflow.
These are not part of the Bash library — they are standalone tools you copy into your
repo or your local Claude Code installation.

---

## `agent-pickup.sh`

**Purpose:** Agent orientation script — run at the start of any Codex or Gemini session.
Prints branch, recent commits, pending specs from `docs/plans/`, and
`memory-bank/activeContext.md` summary.

**Install:**
```bash
cp scripts/lib/foundation/scripts/etc/contrib/agent-pickup.sh bin/agent-pickup.sh
chmod +x bin/agent-pickup.sh
```

**Usage:**
```bash
bin/agent-pickup.sh
```

Agents run this as their first command to orient themselves without being told what
to do. Works in any repo that follows the `docs/plans/` + `memory-bank/` convention.

---

## `handoff-skill.md`

**Purpose:** Claude Code skill template for preparing and validating agent task handoffs.
Covers both Codex (pure code tasks) and Gemini (cluster verification tasks), including
multi-repo task handling.

**Install:**
```bash
cp scripts/lib/foundation/scripts/etc/contrib/handoff-skill.md ~/.claude/commands/handoff.md
```

**Usage:** In Claude Code, run `/handoff codex` or `/handoff gemini`.

**What it does:**
1. Confirms the spec exists in `docs/plans/` and has all required sections
2. Reminds you to push the branch before handoff
3. Prints the exact copy-paste block for the agent
4. Distinguishes single-repo vs multi-repo tasks (spec repo ≠ work repo)
5. Provides a post-completion verification checklist

**Multi-repo note:** When the spec lives in one repo (e.g. `k3d-manager`) but the work
targets other repos (e.g. `shopping-cart-*`), the handoff block separates "get the spec"
from "do the work" to prevent the agent from confusing which repo to commit into.

**Companion skills** (also installable from this directory):
- `agent-pickup.sh` — agent-side orientation (agents run this, not Claude)

---

## `statusline.sh`

**Purpose:** Enhanced Claude Code status line — shows model, git branch, context usage,
session cost, and API limits in the terminal prompt.

**Install:** Use the `/statusline-setup` skill in Claude Code, or see
[`scripts/etc/contrib/statusline.sh`](../scripts/etc/contrib/statusline.sh) directly.

---

## Workflow Overview

These three tools work together as the agent collaboration layer:

```
Claude writes spec → /handoff codex|gemini → agent runs bin/agent-pickup.sh → implements spec
                         ↑                                                          ↓
                   validates gates                                        Claude verifies SHA
```

For the full spec-driven multi-agent workflow, see the
[k3d-manager CLAUDE.md](https://github.com/wilddog64/k3d-manager/blob/main/CLAUDE.md).
