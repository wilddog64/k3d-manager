# Bug: approval card says "with none" and its confirm dialog says "Approve repair?" / "Run Run"

**Status:** OPEN — capture
**Priority:** P3 (cosmetic; the card and buttons carry the right request)
**Classified:** P3 by gemini-4-argon-medium, 2026-11-25 — Cosmetic wording glitches ("with none", "Approve repair?", "Run Run") in the cloud approval card and confirmation dialog
**Triage:** carry → v1.47.0 — triage 2026-11-25, operator ("go with your recommendation")
**Branch:** `k3d-manager-v1.47.0`
**Introduced by:** v1.46.0 plan 1 a (`358f10b9`, card text) and c (`4e3f3c81`, relay confirm dialog)
**Should have been caught by:** live check
**Introducing change reviewed:** yes (Fable)
**Waiting on:** dispatch — since 2026-11-25
**Prior art:** none above threshold (vector store unavailable; exact-slug pass found nothing)
**Filed:** 2026-11-25
**Detected by:** operator screenshots, v1.46.0 plan 1 E-P1-live

## Observed

- Card: "Cloud request `20261126T014053Z-make-e2e` asks to run `make-e2e` with none." for a request with no args.
- Confirm dialog on Approve: title "Approve repair?", body "Run Run cloud request make-e2e? Blast radius: …" (the repair
  dialog title is reused and the action label already starts with "Run").

## Fix direction

Card: say "with no arguments" (or drop the clause) when args are empty. Dialog: a cloud-request title ("Approve cloud
request?") and no doubled verb. Tests on the card text and the relay's confirm object.
