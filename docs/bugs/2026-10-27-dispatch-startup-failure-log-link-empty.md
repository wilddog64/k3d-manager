# Bug: failed startup Log link opens an empty Loki view

**Status:** OPEN — source-level cause confirmed; implementation not dispatched
**Priority:** P3
**Filed:** 2026-10-27
**Branch:** `k3d-manager-v1.43.9`
**Related:** `docs/bugs/2026-10-25-dispatch-run-log-not-viewable-from-grafana.md`

Failed startup rows with codex_exit.exit evidence offer a Grafana Log link, but
the shipper deliberately ships only landing-test logs. The local codex.log
contains the startup error while the linked Loki view is empty. Historical
exit127 rows are valid; their later retry2 succeeded and landed.

[Verbatim evidence and source analysis](../issues/2026-10-27-dispatch-startup-exit127-empty-grafana-log.md).

A scoped fix should show unsupported evidence as local-only/unavailable with
a clear explanation, preserving the existing prohibition on shipping codex.log.
Do not rewrite failed historical attempts as successful or ship transcripts.
