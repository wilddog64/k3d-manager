# Bug: acg-up on the new hub fails at once because no EC2 SSH key exists, and machine-setup never creates one

**Status:** OPEN
**Priority:** P2
**Severity:** medium — `/cluster-up aws` on the M5 hub fails before provisioning; workaround: create the key by hand on the M5
**Approval:** operator, 2026-11-01 ("should each node has its own ssh key intead of copying over?" — yes, one key per node; hub-migration gaps are filed as found)
**Filed:** 2026-11-01
**Detected by:** Claude, job `87c78389` on the M5
**Affected:** `bin/k3dm-machine-setup` (hub role), `scripts/lib/foundation/scripts/lib/acg/acg.sh` (`acg_provision`, lines ~226-231; fix upstream in lib-foundation, then subtree-pull)
**Branch:** `k3d-manager-v1.43.13`
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

- `bin/k3dm-machine-setup`
- `scripts/tests/bin/machine_setup.bats`
- `scripts/lib/foundation/scripts/lib/acg/acg.sh` (upstream lib-foundation first, then subtree-pull)
- lib-foundation BATS for `acg_provision`
- `docs/howto/machine-setup.md`
- `CHANGELOG.md`

## What NOT to do

- Do not copy a private key between machines, and do not add it to the Keychain manifest.
- Do not overwrite or rotate an existing `~/.ssh/k3d-manager-key.pem`.
- Tests use a scratch HOME (asserted not to be the real one) and stub `aws`/`ssh-keygen`; the stub
  `describe-key-pairs` and `import-key-pair` duplicate error output is captured from a real read-only run (host and
  date in a comment).

## Acceptance

```yaml
must:
  M1: machine-setup --role hub creates ~/.ssh/k3d-manager-key.pem (mode 600) and its .pub when missing
  M2: machine-setup --check --role hub reports the key present or missing, without key contents
  M3: acg_provision with a missing key exits non-zero before any aws call, naming the path and make machine-setup ROLE=hub
  M4: an import-key-pair duplicate whose fingerprint matches the local key proceeds to create-stack (paired positive control for N2)
must_not:
  N1: machine-setup never modifies an existing key (same bytes and mtime after a run)
  N2: an existing sandbox key pair with a different fingerprint never reaches create-stack; the error names both fingerprints
  N3: no private key material appears in any output or log
evidence:
  E1:
    proves: [M1, M2, N1, N3]
    kind: offline
    intent: You will see machine_setup.bats in a scratch HOME create the key when it is missing, leave a pre-placed key byte-identical, and print no key material (M1 red on the pre-fix script).
    what: bats scripts/tests/bin/machine_setup.bats
  E2:
    proves: [M3, M4, N2]
    kind: offline
    intent: You will see lib-foundation BATS with a stub aws log no aws call for a missing key, reach create-stack on a matching duplicate, and stop before create-stack on a mismatched one (M3/N2 red on the pre-fix acg.sh).
    what: lib-foundation bats for acg_provision
  E3:
    proves: [M1, M3]
    kind: live
    intent: You will see make machine-setup ROLE=hub on the M5 create the key, then /cluster-up aws get past "Deriving public key" and create the stack.
    what: operator on the M5; Claude reads the job output
interface:
  - make machine-setup ROLE=hub / bin/k3dm-machine-setup --role hub [--check]
  - ~/.ssh/k3d-manager-key.pem, ~/.ssh/k3d-manager-key.pub
  - acg_provision (via make up CLUSTER_PROVIDER=k3s-aws)
  - aws ec2 import-key-pair / describe-key-pairs
```
