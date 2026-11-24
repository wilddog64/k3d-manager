# Bug: on a new hub, acg_provision hides a failed key import and acg_extend checks a stale profile directory

**Status:** OPEN
**Priority:** P2 — on k3d-manager's new M5 hub, `acg-up` cannot provision and no sandbox extend works
**Approval:** operator, 2026-11-01 ("go ahead to dispatch hub fixes")
**Filed:** 2026-11-01
**Detected by:** Claude, k3d-manager jobs `87c78389` and `e7a0ecfb` on the M5
**Branch:** `fix/acg-hub-ec2-key-and-extend-profile`
**Consumer specs (full evidence):** k3d-manager `docs/bugs/2026-11-01-hub-has-no-ec2-ssh-key-acg-up-fails.md`
(the `acg_provision` half), k3d-manager `docs/bugs/2026-11-01-acg-extend-guard-reads-stale-profile-dir.md`

## Part A — `acg_provision` key handling (`scripts/lib/acg/acg.sh`, lines ~226-231)

Observed: with no `~/.ssh/k3d-manager-key.pem`, `ssh-keygen -y -f <pem> > <key>.pub` failed, but the redirect left
a 0-byte `k3d-manager-key.pub`. The next run skipped derivation, imported empty material, and the import error was
hidden (`--soft ... >/dev/null 2>&1`). `create-stack` then failed for every instance:
`The key pair 'k3d-manager-key' does not exist`.

Fix:
1. A missing pem fails before any `aws` call, with a message naming the path and `make machine-setup ROLE=hub`.
2. Derive the `.pub` into a temp file and move it into place only on success. Treat a 0-byte `.pub` as missing.
3. Show import errors. If the import fails because the pair already exists, compare its fingerprint
   (`aws ec2 describe-key-pairs`) with the local key. On a mismatch, fail before `create-stack` and name both
   fingerprints.
4. Before `create-stack`, confirm the key pair exists in the region (`describe-key-pairs`). If it doesn't, fail.

## Part B — `acg_extend.js` / `acg_restart.js` profile directory

Observed: `ERROR: Auth dir is empty (~/.local/share/k3d-manager/profile)` right after a valid CDP login. The
session lives in `PLAYWRIGHT_AUTH_DIR` (default `~/.local/share/k3d-manager/pw-profile`, `cdp.sh`). Both scripts
hard-code the old `profile` directory for the first-run guard and the `launchPersistentContext` fallback.

Fix:
1. Both scripts resolve `process.env.PLAYWRIGHT_AUTH_DIR || ~/.local/share/k3d-manager/pw-profile`.
2. The first-run guard runs only on the persistent-context fallback. When CDP is reachable, the extend proceeds.

## Files

- `scripts/lib/acg/acg.sh`
- `scripts/tests/lib/` BATS for `acg_provision` (new or existing acg suite)
- `scripts/lib/acg/playwright/acg_extend.js`, `scripts/lib/acg/playwright/acg_restart.js`
- `scripts/lib/acg/tests/` jest tests
- `CHANGE.md`

## What NOT to do

- Do not generate, copy or rotate the key in `acg_provision`; key creation belongs to the consumer's machine-setup.
- Do not print key material.
- Do not change `_ACG_KEY_NAME` or `_ACG_KEY_PEM`.
- Tests use a scratch HOME (asserted not to be the real one) and stub `aws`/`ssh-keygen`/CDP. Stub AWS errors take
  their text from a real read-only capture (k3d-manager M5, 2026-11-01): the CloudFormation event above and
  `DryRunOperation`. Name the host and date in a comment.
- Bash 3.2 compatible; `set -euo pipefail`; shellcheck clean; `npm run check` and `npm test` green.

## Acceptance

```yaml
must:
  M1: acg_provision with a missing pem exits non-zero before any aws call, naming the path and make machine-setup ROLE=hub
  M2: a 0-byte k3d-manager-key.pub next to a valid pem is re-derived, then imported
  M3: an import duplicate whose fingerprint matches the local key proceeds to create-stack (paired positive control for N2)
  M4: with CDP reachable and no ~/.local/share/k3d-manager/profile dir, acg_extend passes the guard
  M5: acg_extend.js and acg_restart.js use PLAYWRIGHT_AUTH_DIR when set, else ~/.local/share/k3d-manager/pw-profile
must_not:
  N1: a failed ssh-keygen derivation never leaves a k3d-manager-key.pub behind
  N2: a sandbox key pair with a different fingerprint never reaches create-stack; the error names both fingerprints
  N3: create-stack is never called when describe-key-pairs does not find the key pair
  N4: with CDP unreachable and an empty profile dir, acg_extend still exits non-zero with the bootstrap message (paired control for M4)
  N5: neither script reads ~/.local/share/k3d-manager/profile; no key material in any output
evidence:
  E1:
    proves: [M1, M2, M3, N1, N2, N3, N5]
    kind: offline
    intent: You will see BATS with a scratch HOME and stub aws/ssh-keygen logging argv show no aws call for a missing pem, re-derivation of an empty .pub, create-stack after a matching duplicate, and a stop before create-stack on a mismatch or an absent pair (M1/M2/N1/N3 red on the pre-fix acg.sh).
    what: env -i ... bats scripts/tests/lib/
  E2:
    proves: [M4, M5, N4, N5]
    kind: offline
    intent: You will see jest in a scratch HOME pass the guard with a stub CDP and no profile dir (red on the pre-fix script), fail with CDP down and an empty pw-profile, and resolve PLAYWRIGHT_AUTH_DIR.
    what: cd scripts/lib/acg && npm test
  E3:
    proves: [M1, M2, M4]
    kind: live
    intent: You will see, after the k3d-manager subtree pull, /cluster-up aws on the M5 extend the sandbox and create the stack.
    what: operator Slack; Claude reads the job output on the M5
interface:
  - acg_provision (scripts/lib/acg/acg.sh)
  - node scripts/lib/acg/playwright/acg_extend.js <sandbox-url>; acg_restart.js
  - ~/.ssh/k3d-manager-key.pem, ~/.ssh/k3d-manager-key.pub
  - env PLAYWRIGHT_AUTH_DIR, HOME; CDP http://localhost:9222
  - aws ec2 import-key-pair / describe-key-pairs; aws cloudformation deploy
```
