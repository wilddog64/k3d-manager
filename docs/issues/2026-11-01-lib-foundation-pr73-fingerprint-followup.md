# lib-foundation PR #73 fingerprint follow-up

PR #73 merged as `bb7f1f28`. Copilot identified a duplicate-key fingerprint issue; a follow-up is pushed on lib-foundation branch `fix/acg-key-fingerprint` (`bac3238`, `f79f45c`, notes `eb2a136`), with no PR created. The default machine-setup key is Ed25519; AWS documents SHA-256 for imported Ed25519 keys, while the merged code used MD5. The AWS user guide documents DER/MD5 for imported RSA keys, but its API reference describes RFC 4716. No live AWS check was run; a read-only comparison with the operator's sandbox remains required.

Focused real-key tests against the pre-fix merge produced:

```text
1..2
not ok 1 acg provisioning accepts matching imported Ed25519 fingerprint and rejects mismatch
# (in test file /private/tmp/k3dm-lib-key-before/scripts/tests/lib/acg.bats, line 642)
#   `[ "$status" -eq 0 ]' failed
not ok 2 acg provisioning accepts matching imported RSA fingerprint and rejects mismatch
# (in test file /private/tmp/k3dm-lib-key-before/scripts/tests/lib/acg.bats, line 652)
#   `[ "$status" -eq 0 ]' failed
```

The clean-environment system/core/agent-rigor/ACG BATS run passed 154/154; after adding optional SHA-256 padding handling, the final ACG run passed 37/37. ShellCheck and staged `_agent_audit` passed. Full local logs: `/private/tmp/k3dm-lib-key-bats.log`, `/private/tmp/k3dm-lib-key-acg-final.log`.

PR #74 conflicted after #73 merged:

```text
Auto-merging CHANGE.md
CONFLICT (content): Merge conflict in CHANGE.md
Automatic merge failed; fix conflicts and then commit the result.
```

A non-force merge `25678b7` retained both changelog entries and was pushed to `feat/install-macmon`; clean-environment BATS passed 157/157, ShellCheck passed, and GitHub CI was pending at the time of this record. The staged audit initially reported a pre-existing AWK parser false positive:

```text
WARN: Agent audit: scripts/lib/acg/acg.sh exceeds if-count threshold in: emit_output:10
```

The precise legacy entry was allowlisted with a follow-up issue in lib-foundation, keeping the threshold at 8; the staged audit then passed. PR #74 does not contain the fingerprint fix. GitHub CI and Copilot review of the updated PR remain to be checked.
