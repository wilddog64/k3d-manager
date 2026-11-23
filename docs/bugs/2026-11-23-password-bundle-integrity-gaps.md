# Bug: travel bundle: recipient set, bundle and freshness are not integrity-protected

**Status:** OPEN — captured 2026-11-23
**Priority:** P3
**Introduced by:** v1.45.0 travel-bundle plan
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unavailable: cluster context missing); grep of docs/bugs for the key terms found no match
**Detected by:** v1.45.0 red-team gate, 2026-11-22, on `7dfb7238` — see [docs/issues/2026-11-23-v1.45.0-red-team.md](../issues/2026-11-23-v1.45.0-red-team.md)
**Severity:** hardening. A same-uid process on the hub can already read the passwords; these give persistence, phishing or false freshness.
**Findings:** Astra 2 (High, downgraded), Astra 3, Astra 7, Fable 9, Fable 10, Fable 13. Claude: Astra 2 confirmed, others plausible, P3.

## What is wrong

- LaunchAgent PATH starts with `~/.local/bin:~/bin` (`scripts/etc/launchd/com.k3d-manager.password-bundle.plist.tmpl:11`) and
  `make`, `shasum`, `age` are called by name (`scripts/plugins/password_bundle.sh:142-151`). Downgraded from High: a same-uid
  process can already run `make show-service-passwords`.
- `add_recipient` silently replaces an existing name's key (`:98-101`); meta lists names only (`:152-154`); no alert on change.
- Recipient-removal race: an older publisher can restore a removed recipient (`:111-159`).
- Bundle and meta are unauthenticated; `show` trusts plaintext `generated_at` and prints the payload raw (`:236-244`).
- Freshness recorded when the delivered file is missing (`:9-15,144-149`); a partial lookup failure publishes `N/A` and reports
  success (`Makefile:1116-1193`).
- Removing a recipient revokes nothing already copied (document).

## Fix direction

Absolute tool paths or a fixed PATH; key fingerprints in meta and a recipient-set hash metric with alert; lock around
read-modify-publish; sign bundle + meta; `generated_at` inside the payload; strip control characters on display; fail publish on
`N/A`; document non-revocation.
