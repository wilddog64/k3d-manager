# stall-watch ledger events lack the `project` key for non-k3d-manager tasks

**Status:** OPEN
**Priority:** P3
**Introduced by:** 6972d10a (multi-project M1: `project` ledger key added via `_dispatch_ledger_event` only)
**Should have been caught by:** spec
**Introducing change reviewed:** no
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Minor telemetry omission where `stall_detected` ledger events omit the `project` field, with no current impact because per-project readers do not exist yet.)
**Waiting on:** operator decision
**Prior art:** not run (vector store unreachable: context `k3d-k3d-cluster` does not exist; exact-slug glob found none)

## Report

Luna's M1 report (2026-11-17, `multi-project-m1-registry-dispatch.run/last-message-2.md`): `bin/k3dm-dispatch-stall-watch`
writes `stall_detected` straight to `ledger.jsonl` (`bin/k3dm-dispatch-stall-watch:74`), outside `_dispatch_ledger_event`,
so a stalled dirused task's `stall_detected` row has no `project`. M1's Acceptance M1 says "every ledger event for it carries
project=dirused". The M1 spec's Contract readers listed stall-watch as a reader only, not a writer — a spec defect. Luna kept
to the Files table and flagged it instead of editing the file.

## Impact

Readers treat a missing `project` as k3d-manager, so a dirused stall is attributed to k3d-manager in any per-project view
(M3 dashboards). No effect today: no per-project reader exists yet.

## Fix sketch

In stall-watch's `jq` call, read `$_root/$version/$slug.run/project` and add `project` when it is set and not `k3d-manager`
(the pattern `_dispatch_ledger_event` uses). Test: a stalled fake dirused task's `stall_detected` row has `project == "dirused"`;
a k3d-manager task's row has no `project` key.
