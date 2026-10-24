# Dispatch live smoke — detached worker survives Codex CLI

**Date:** 2026-10-20
**Purpose:** E2 live evidence for `docs/bugs/2026-10-20-codex-dispatch-background-process-lost-no-terminal-status.md`. This is a throw-away spec used only to prove that a `bin/k3dm-codex-dispatch start` launched from Codex CLI keeps its worker alive after the launching command returns.

## Files

- `scratch/dispatch-smoke.txt`

## Task

Create the file `scratch/dispatch-smoke.txt` containing exactly one line: `dispatch smoke ok`. Change nothing else. Do not run any other command than what is needed to write that file and `cat` it.

## Rules

- Do not touch `memory-bank/`, `bin/`, or `scripts/`.
- Your last message must list every file you changed.
