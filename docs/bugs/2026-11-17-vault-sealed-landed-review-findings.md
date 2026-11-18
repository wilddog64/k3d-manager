# Bug: vault-sealed landings (fadf8438, bea02b84) — post-land Fable review findings

**Status:** LIVE-VERIFIED — fixes deployed on the hub 2026-11-18 (promote 637061f1, tag hub-promote/20261118T012954Z). Landed as webhook W1–W6 in 59dd12e5; Hermes H1–H3, H5 in ebdd140a; guide H4 in 4ecee69c. Claude verified offline: pre-fix red 5/5 in each, all 10 spec mutations red, targeted suites green.
**Priority:** P2 (proposed: the webhook sealed check fails open on any kubectl warning; the rest are P3 hygiene)
**Introduced by:** fadf8438 (Hermes, Luna) and bea02b84 (webhook, Flash), both v1.44.2
**Should have been caught by:** review
**Introducing change reviewed:** no (the specs had Argon + Fable; the two diffs had no diff review before land)
**Fix commit:** `8352227d`
**Live evidence:** 2026-11-18 · run claude-hub-pane-deployed-code-read · env m5 · scenario webhook-and-hermes-run-fixed-code-after-promote · commit 637061f1 · proves fix
**Prior art:** `docs/bugs/2026-11-17-hermes-r7-signing-restore-offered-when-vault-sealed.md`, `docs/bugs/2026-10-12-hermes-has-no-vault-sealed-sensor.md` (exact-slug pass; `find-similar-docs` not run) — the specs these landings implemented; none records these defects.
**Filed:** 2026-11-17

## Source

Blind Fable diff reviews, 2026-11-17: webhook bea02b84 (67K tokens), Hermes fadf8438 (97K tokens). Claude re-read every
finding below against the code on `k3d-manager-v1.44.2`; unverified or speculative findings are not listed.

## Webhook (bea02b84)

| # | Finding | Where |
|---|---|---|
| W1 | `_posix_spawn_capture` dups stderr into the stdout file (`POSIX_SPAWN_DUP2, 1, 2`). A kubectl `Warning:` line (deprecation, throttling) makes `json.loads` fail, so Vault reads "state unavailable" and counts as **not sealed**: the sealed short-circuit silently falls back to the LLM diagnosis this fix exists to avoid. | `bin/k3dm-webhook:1456`, parse at `:2062` |
| W2 | The four new tests record argv but never assert on it: no offline evidence that the reads are exactly the two specified argv (N1: no exec, no Secret read), and nothing checks per-alert diagnostics are skipped when sealed. | `scripts/tests/bin/test_webhook_analyze_routing.py:439`, `:465` |
| W3 | One pod missing a label makes the whole Vault line "state unavailable", so a second unlabelled pod masks a sealed one. | `bin/k3dm-webhook:2072-2076` |
| W4 | The reads pass no `--request-timeout`; only the 15 s spawn timeout bounds them. | `bin/k3dm-webhook:2159-2166` |
| W5 | Dead branch `if not diag_parts` (the Vault part is always appended now). | `bin/k3dm-webhook:2214` |
| W6 | Pre-existing: `argocd_app` passed to kubectl without `--`. | `bin/k3dm-webhook:2197` |

## Hermes (fadf8438)

| # | Finding | Where |
|---|---|---|
| H1 | `sealed = labels["vault-sealed"] == "true"`: any value other than `"true"` (empty, `"True"`, garbage) reads as unsealed rather than unknown. | `scripts/lib/hermes/sensors.py:908` |
| H2 | The r7 precondition `all(pod.get("sealed") is False for pod in pods)` is true for an empty pod list, so r7 can be offered when `vault_seal` is healthy with no pod data. | `scripts/lib/hermes/repairs.py:205` |
| H3 | The resolved text uses `timestamp()[11:16]` (no `Z`, no zone) and always says "without a repair", even if one ran. | `bin/k3dm-hermes:285-286` |
| H4 | `docs/guides/hermes.md` does not describe the new card lines (Root cause, Recommended, Withdrawn). | `docs/guides/hermes.md` |
| H5 | The incident text says "ESO and ArgoCD failures listed below follow from it" even when ArgoCD is not a contributor (seen live 2026-11-17 15:25:15Z: contributors eso + vault_seal). | `scripts/lib/hermes/correlator.py` `_template` |

Lower (not verified as defects, test hygiene): Recommended line twice on interactive cards; debounce counts samples, not cycles;
tests use window=1 and single pods.

## Fix direction (not decided)

One follow-up dispatch per file group: webhook W1–W5 (capture stderr separately for these two reads; assert argv; per-pod
unknown), Hermes H1–H3 and H5, and Claude writes H4. W6 rides along only if the webhook dispatch already touches that line.

## Live verification (Claude, 2026-11-18 ~01:35Z, read-only, hub pane work:1.0)

The spec evidence is offline only, so the live check proves the deployed processes run the fixed code:
- Hub checkout HEAD 637061f1, clean (`git status --porcelain` 0), `bin/` and `scripts/` identical to 637061f1; `bin/k3dm-webhook` unchanged between 59dd12e5 and 637061f1.
- Webhook (launchd, long-running, PID 75816): file mtime 15:43:18 PST < process start 16:01:13 PST, so the running process loaded the W1–W6 code. No restart needed.
- Hermes (launchd interval job): each run starts fresh from the 637061f1 checkout (H1–H3, H5).
- Not exercised: a real sealed-Vault alert through the webhook (E2 of the r7 bug stays open there).
