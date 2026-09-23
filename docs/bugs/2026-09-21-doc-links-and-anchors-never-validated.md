# Bug: broken doc links and heading anchors were never validated

**Branch:** `k3d-manager-v1.36.0`
**Filed:** 2026-09-21
**Status:** FIXED
**Files:** `scripts/check-doc-links.py`, `scripts/tests/bin/test_check_doc_links.py`,
`.githooks/pre-commit`, `Makefile`, plus 10 docs with broken links

## Evidence

A README audit found the vCluster E2E harness guide listed three times, twice labelled
"(Tier 1)", all three links pointing at the bare file — so following "Tier 2" landed on a
page titled "(Tier 1)" (fixed in `f3b9be22`). Nothing in the repo would have caught it: a
link to a missing path or a non-existent `#anchor` renders normally and fails only when a
reader clicks it.

`memory/feedback_issue_doc_links_precommit.md` recorded this gap on 2026-04-06 (four 404
issue-doc links) and re-confirmed on 2026-09-17 that `scripts/check-doc-links.sh` and
`.pre-commit-config.yaml` **have never existed** in this repo. The proposal sat unbuilt for
five months while the debt grew.

A first sweep over 1,725 tracked Markdown files found **13 genuinely broken links**.

## Root cause

No gate. `.githooks/pre-commit` validated subtree edits and ran `_agent_audit`/`_agent_lint`;
neither looks at links. Relative-path and anchor correctness was left to manual review, which
is exactly the kind of check humans skip.

## Fix

`scripts/check-doc-links.py` (stdlib only, matching the repo's Python convention) validates
every relative link and heading anchor. Wired into `.githooks/pre-commit` over **staged files
only**, so pre-existing debt elsewhere cannot block an unrelated commit, plus
`make check-doc-links` for the full sweep. Bypass: `K3DM_SKIP_DOC_LINKS=1`.

Three false-positive classes had to be handled, each of which would have made the gate
useless by crying wolf:

1. **Inline code.** A DNS regex — `` `[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?` `` — is
   syntactically `[text](target)`. Code spans are blanked before matching.
2. **`path:line` references.** This repo writes clickable `bin/k3dm-webhook:95`; the line
   suffix is stripped before the existence check.
3. **Anchor slug rules.** `github-slugger` does `.replace(/ /g, '-')` — **each** space
   becomes its own hyphen, so `/claude / /gemini / /codex Commands` slugs to
   `claude--gemini--codex-commands` with doubled hyphens. An initial implementation collapsed
   whitespace runs and reported three *correct* links as broken. Caught before committing any
   "fix" to them.

Fenced code blocks are skipped for both links and headings — a `# Requires a host context`
shell comment is not a heading.

## Links fixed

Standing docs — retargeted:

| File | Was | Now |
|---|---|---|
| `docs/architecture/ingress-port-forwarding.md` | `../howto/vault-pki-setup.md` | `../guides/security/04-vault-pki.md` |
| `docs/howto/jenkins-cli-ssl-trust.md` | `../../README.md#jenkins-authentication-modes` | `../guides/jenkins-authentication.md` |
| `docs/howto/jenkins-cli-ssl-trust.md` | `../../README.md#vault-pki-setup` | `../guides/security/04-vault-pki.md` |
| `docs/howto/ldap-bulk-user-import.md` | `../bin/get-ldap-password` | `../../bin/get-ldap-password` |
| `docs/howto/slack-slash-commands.md` | `#create-slack-app` | `#1-create-slack-app` |

Historical records (4 `docs/issues/2026-05-*`, 1 archived plan) — dead links **unlinked to
inline code**, text preserved. Rewriting a record to point somewhere it never pointed would
falsify it; the reference still reads, without a false promise of a working link. This also
removed three neighbouring links whose absolute `/Users/cliang/...` paths resolved on this
machine only — they are meaningless to any other reader and on github.com.

## Discovered, NOT fixed — `bin/acg-up` was renamed to `bin/cluster-up`

The dead `/Users/cliang/.../bin/acg-up` links exposed a rename: `bin/acg-up` / `bin/acg-down`
became `bin/cluster-up` / `bin/cluster-down` in **v1.7.1** (`0c9b2707`), and **219 files still
say `bin/acg-up`**. No code references the old names, so nothing is broken at runtime — but
standing docs (README's ACG table, `docs/architecture/cloudflare-slack-relay.md` "Step 10h/14c",
`docs/guides/`) instruct readers to run a script that does not exist. The link checker does not
catch these because they are plain code spans, not links.

Historical bugs/issues/retros should keep the old name — that is what was true then. The
standing-doc sweep is a separate, user-approved change; it is deliberately not bundled here.

## Verification

- `python3 scripts/check-doc-links.py` → `1725 file(s) OK`
- `pytest scripts/tests/bin/test_check_doc_links.py` → **23 passed**, covering each
  false-positive class, the slug rules, duplicate-heading suffixes, and a live-tree gate
- Failure path proved: a file with one bad link exits 1 and names `file:line`
- `shellcheck .githooks/pre-commit` → clean
