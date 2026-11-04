# Bug: acg-up on the new hub fails at once because no EC2 SSH key exists, and machine-setup never creates one

**Status:** OPEN — machine-setup half `08c94b0f` + `15549a06` landed and verified; lib-foundation PR #73 merged and subtree synced in `c22646e1`; duplicate-key fingerprint follow-up and E3 live verification remain pending
**Priority:** P2
**Severity:** medium — `/cluster-up aws` on the M5 hub fails before provisioning; workaround: create the key by hand on the M5
**Approval:** operator, 2026-11-01 ("should each node has its own ssh key intead of copying over?" — yes, one key per node; hub-migration gaps are filed as found); dispatch go: operator, 2026-11-01 ("go ahead to dispatch hub fixes")
**Filed:** 2026-11-01
**Detected by:** Claude, job `87c78389` on the M5
**Affected:** `bin/k3dm-machine-setup` (hub role), `scripts/lib/foundation/scripts/lib/acg/acg.sh` (`acg_provision`, lines ~226-231; fix upstream in lib-foundation, then subtree-pull)
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/2026-11-01-hub-secrets-manifest-omits-slack-role-map.md` (same migration, Keychain items); `docs/bugs/2026-11-01-acg-up-on-dev-node-restarts-retired-local-hub.md`

## Observed failure

Job `87c78389` (2026-11-01 16:10Z, M5):

```
INFO: [acg] Deriving public key from /Users/cliang/.ssh/k3d-manager-key.pem
/Users/cliang/.ssh/k3d-manager-key.pem: No such file or directory
ERROR: failed to execute ssh-keygen -y -f /Users/cliang/.ssh/k3d-manager-key.pem: 255
```

The M4 has the key (created 2026-03-20). The M5 has none.

## Root cause

`acg_provision` assumes `~/.ssh/k3d-manager-key.pem` exists and derives the public key from it. Nothing creates the
key: not machine-setup, and not acg-up. The key was made once by hand on the M4. Each sandbox is a new AWS account
and acg-up imports the local public key every run, so the key never needs to leave its machine.

A second gap is on the same lines: `aws ec2 import-key-pair ... >/dev/null 2>&1` under `--soft` hides every failure.
If a key pair named `k3d-manager-key` already exists in the sandbox with another public key, the import fails without
a message, and the instances get a key this node cannot use.

## Fix

1. One key per node, never copied. `make machine-setup ROLE=hub` creates `~/.ssh/k3d-manager-key.pem` when it is
   missing (`ssh-keygen -t ed25519 -N "" -C "k3d-manager@$(hostname -s)"`, mode 600) and its `.pub`, and leaves an
   existing key unchanged. `--check` reports `ec2 ssh key: present|missing`. It never reads or prints the key
   contents.
2. `acg_provision` (lib-foundation): if the key is missing, fail before any AWS call with a message naming the path
   and `make machine-setup ROLE=hub`. If `import-key-pair` fails because the pair already exists, compare its
   fingerprint with the local key (`aws ec2 describe-key-pairs`). On a mismatch, fail before `create-stack` and
   name both fingerprints. Any other import error is shown, not hidden.
3. Docs: `docs/howto/machine-setup.md` says the hub generates its own EC2 key, and that keys are never copied
   between nodes.

## Files

- `scripts/lib/acg/acg.sh`
- `scripts/tests/lib/acg.bats`
- `docs/issues/2026-11-01-acg-imported-key-fingerprint-formats.md`
- `CHANGE.md`

## What NOT to do

- Do not copy a private key between machines, and do not add it to the Keychain manifest.
- Do not overwrite or rotate an existing `~/.ssh/k3d-manager-key.pem`.
- Tests use a scratch HOME (asserted not to be the real one) and stub `aws`/`ssh-keygen`; the stub
  `describe-key-pairs` and `import-key-pair` duplicate error output is captured from a real read-only run (host and
  date in a comment).

## Acceptance

```yaml
must:
  - id: M1
    req: for an imported ssh-ed25519 public key, _acg_imported_key_fingerprint strips the leading "SHA256:" prefix from ssh-keygen -E sha256 -lf output and returns the 43-character base64 SHA-256 digest
  - id: M2
    req: when import-key-pair returns InvalidKeyPair.Duplicate for an Ed25519 key and describe-key-pairs returns the real AWS EC2 KeyFingerprint format (bare 43-character base64 SHA-256 digest with trailing "=" and no "SHA256:" prefix, as captured on m5-air on 2026-11-03: "DWj8LMmMqaZ9O3vJ8oG6xflnl5I/W5HmeoHVYWcR83A="), _acg_import_key succeeds (returns 0) and acg_provision proceeds to cloudformation deploy (paired positive control for N1)
  - id: M3
    req: when import-key-pair returns InvalidKeyPair.Duplicate for an RSA key and describe-key-pairs returns the matching PKCS8 DER MD5 colon-hex fingerprint, _acg_import_key succeeds (returns 0)
must_not:
  - id: N1
    req: when describe-key-pairs returns the real AWS EC2 unprefixed base64 SHA-256 fingerprint with trailing "=" for a matching Ed25519 key, _acg_import_key never fails with "Key fingerprint mismatch"
  - id: N2
    req: when describe-key-pairs returns a mismatched fingerprint or trailing non-padding characters (e.g. "=junk"), _acg_import_key exits non-zero with "Key fingerprint mismatch" before cloudformation deploy
  - id: N3
    req: no private key material appears in any output or log
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    intent: >-
      Isolated BATS tests in scripts/tests/lib/acg.bats prove N1 fails (red) on pre-fix fix/acg-key-fingerprint (eb2a136, where _acg_imported_key_fingerprint kept the SHA256: prefix while real AWS returns bare base64 with trailing "=") and M1-M3 + N1-N3 pass (green) on fixed code.
    what: env -i HOME="$HOME" PATH="$PATH" bats scripts/tests/lib/acg.bats
```

## Rules

- Touch only the files listed under `## Files` inside this `lib-foundation` worktree (`scripts/lib/acg/acg.sh`, `scripts/tests/lib/acg.bats`, `docs/issues/2026-11-01-acg-imported-key-fingerprint-formats.md`, `CHANGE.md`). Do not touch `memory-bank/`.
- Do not run `git add`, `git commit`, or `git push`. Leave changes in the working tree.
- Do not unset or override task-provided `K3DM_*` and `TMPDIR` environment variables.
- Run and paste the output of:
  - `bats scripts/tests/lib/acg.bats`
  - `shellcheck -x -S warning scripts/lib/acg/acg.sh`
  - `git --no-pager diff --check`

## Recurrence: an empty `.pub` from the failed run poisons the next one (job `e7a0ecfb`, 2026-11-01)

After the operator created the key, job `e7a0ecfb` reached `create-stack`, which then failed: every instance got
`The key pair 'k3d-manager-key' does not exist`, and the stack went to `ROLLBACK_COMPLETE`. The first failed run
(`87c78389`) ran `ssh-keygen -y -f <missing pem> > k3d-manager-key.pub`. The redirect created a 0-byte `.pub`
before `ssh-keygen` failed. On the next run the `.pub` existed, so derivation was skipped. The import of empty key
material then failed with its error hidden. A dry-run import of the real key succeeds (`DryRunOperation`).

Added to the fix: `acg_provision` derives the `.pub` into a temp file and moves it into place only on success. It
treats an empty `.pub` as missing. It confirms the key pair exists (`describe-key-pairs`) before `create-stack`.

## Recurrence: live M5 Ed25519 duplicate-key fingerprint format has no `SHA256:` prefix (2026-11-03)

On `2026-11-03` during live `make up CLUSTER_PROVIDER=k3s-aws` verification on `m5-air`, the second run (reusing the `CREATE_COMPLETE` CloudFormation stack) failed in `_acg_import_key` with:

```text
aws: [ERROR]: An error occurred (InvalidKeyPair.Duplicate) when calling the ImportKeyPair operation: The keypair already exists
aws command failed (254): aws ec2 import-key-pair --region us-west-2 --key-name k3d-manager-key --public-key-material fileb:///Users/cliang/.ssh/k3d-manager-key.pub
ERROR: [acg] Key fingerprint mismatch: local 83:66:fc:52:97:a2:55:42:54:27:8a:47:de:1d:f9:1f, AWS DWj8LMmMqaZ9O3vJ8oG6xflnl5I/W5HmeoHVYWcR83A=
```

This live capture establishes two facts:
1. `k3d-manager-v1.43.14` still had the `bb7f1f28` subtree (which used `ssh-keygen -E md5 -lf` -> `83:66:fc:...`).
2. Even on `lib-foundation` branch `fix/acg-key-fingerprint` (`eb2a136`), `_acg_imported_key_fingerprint` returned `awk '{print $2}'` from `ssh-keygen -E sha256 -lf`, which includes the `SHA256:` prefix (`SHA256:DWj8LMmMqaZ9O3vJ8oG6xflnl5I/W5HmeoHVYWcR83A`), and `_acg_import_key` only stripped `=` when `_remote` matched `SHA256:*`. However, real AWS EC2 `describe-key-pairs --query 'KeyPairs[0].KeyFingerprint' --output text` returns **bare Base64 SHA-256 with `=` padding and NO `SHA256:` prefix** (`DWj8LMmMqaZ9O3vJ8oG6xflnl5I/W5HmeoHVYWcR83A=`).

**Required fix in `lib-foundation` (`fix/acg-key-fingerprint`):**
1. In `scripts/lib/acg/acg.sh`:
   - In `_acg_imported_key_fingerprint()`, strip `^SHA256:` for `ssh-ed25519`:
     `printf '%s\n' "${_fingerprint}" | awk '{sub(/^SHA256:/, "", $2); print $2}'`
   - In `_acg_import_key()`, under `*InvalidKeyPair.Duplicate*`, normalize `_remote` before comparing with `_local`:
     - Strip an optional `SHA256:` prefix: `_remote="${_remote#SHA256:}"`
     - When `_local` is a 43-char Base64 SHA-256 digest (`[[ "${_local}" =~ ^[A-Za-z0-9+/]{43}$ ]]`), strip at most one trailing `=` padding character (`_remote="${_remote%=}"`) so real AWS output (`DWj8LMmMqaZ9O3vJ8oG6xflnl5I/W5HmeoHVYWcR83A=`), unpadded Base64 (`DWj8LMmMqaZ9O3vJ8oG6xflnl5I/W5HmeoHVYWcR83A`), and `SHA256:`-prefixed stubs all match `_local`, while double `==` or `=junk` or wrong digests still fail closed (`Key fingerprint mismatch`).
2. In `scripts/tests/lib/acg.bats`:
   - In `_acg_real_duplicate_key` for `ed25519`, set `ACG_REMOTE_FP` to the real AWS EC2 format: bare Base64 SHA-256 with trailing `=` and **no** `SHA256:` prefix (`"$("$real_ssh" -E sha256 -lf "${_ACG_KEY_PEM%.pem}.pub" | awk '{sub(/^SHA256:/, "", $2); print $2"="}')"`, noting the `m5-air` `2026-11-03` live capture in a comment).
   - Test that `_acg_import_key` succeeds on the real unprefixed `...=` format, on unprefixed unpadded `...`, and on `SHA256:...=`, and fails closed on `...=junk` and mismatched digests.
3. In `docs/issues/2026-11-01-acg-imported-key-fingerprint-formats.md`:
   - Record the `2026-11-03` `m5-air` live AWS EC2 capture (`DWj8LMmMqaZ9O3vJ8oG6xflnl5I/W5HmeoHVYWcR83A=`, unprefixed Base64 SHA-256 with trailing `=`).
