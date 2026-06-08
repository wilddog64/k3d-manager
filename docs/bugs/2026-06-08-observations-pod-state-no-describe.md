# Bug: OBSERVATIONS filing speculates on pod state without running kubectl describe

**Branch:** `k3d-manager-v1.6.4`
**Date:** 2026-06-08
**Files:** `bin/k3dm-webhook`

---

## Problem

When an agent notices a pod in a non-Running state (ContainerCreating, CrashLoopBackOff,
Pending, Error, OOMKilled) and files an OBSERVATION, it guesses at the root cause from the
pod status column alone. It does not run `kubectl describe pod` to read the Events section,
which is the only reliable source of the actual failure reason.

Result: filed bug docs contain speculative causes ("missing PVC", "image pull failure",
"insufficient permissions") that are often wrong, wasting triage time.

**Example:** `docs/bugs/2026-06-08-acg-kube-prometheus-stack-operator-pod-stuck-in-containercreating.md`
guessed PVC/image/permissions. The actual cause was a missing TLS secret, visible
immediately in `kubectl describe pod` Events.

---

## Root Cause

The OBSERVATIONS rules say "do not speculate" and "be confident" but give no concrete
instruction for pod-state findings. Agents interpret these rules as applying to logical
reasoning, not data collection — so they file observations based on what they can already
see rather than running a follow-up command.

---

## Fix

Add an explicit pod-state rule to the `Rules for OBSERVATIONS` section in all three agent
system prompts (Claude, Gemini, Codex).

### Change 1 — `bin/k3dm-webhook`: Claude OBSERVATIONS rules (line ~1918)

**Exact old block:**

```python
        "Rules for OBSERVATIONS: only include issues you are confident are real bugs or "
        "misconfigurations. Do not speculate. Each observation must be a distinct issue "
        "unrelated to the question. Limit to 2 observations maximum."
    )
```

**Exact new block:**

```python
        "Rules for OBSERVATIONS: only include issues you are confident are real bugs or "
        "misconfigurations. Do not speculate. Each observation must be a distinct issue "
        "unrelated to the question. Limit to 2 observations maximum.\n"
        "Pod-state rule: if you notice a pod not in Running/Completed state "
        "(ContainerCreating, CrashLoopBackOff, Pending, Error, OOMKilled), run "
        "`kubectl describe pod <name> -n <namespace> --context <ctx>` first and include "
        "the Events section in the BODY. Never guess the cause from status alone."
    )
```

### Change 2 — `bin/k3dm-webhook`: Gemini OBSERVATIONS rules (line ~1947)

Same replacement — identical old block, identical new block.

### Change 3 — `bin/k3dm-webhook`: Codex OBSERVATIONS rules (line ~2085)

Same replacement — identical old block, identical new block.

---

## Files Changed

| File | Change |
|------|--------|
| `bin/k3dm-webhook` | Add pod-state diagnosis rule to OBSERVATIONS in all three agent system prompts |

---

## Rules

- `python3 -m py_compile bin/k3dm-webhook` — no syntax errors
- No other files touched

---

## Definition of Done

- [ ] All three OBSERVATIONS `Rules for` blocks contain the pod-state rule
- [ ] `python3 -m py_compile bin/k3dm-webhook` passes
- [ ] Committed and pushed to `k3d-manager-v1.6.4`
- [ ] memory-bank updated with commit SHA

**Commit message (exact):**
```
fix(webhook): require kubectl describe before filing pod-state OBSERVATIONS
```
