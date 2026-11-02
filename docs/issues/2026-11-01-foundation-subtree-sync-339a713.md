# lib-foundation subtree sync at 339a713

PR #74 merged as `339a713391998703875e7634c91edb1c70a843e4` (https://github.com/wilddog64/lib-foundation/pull/74); upstream local `main` was fast-forwarded to it. This is a main snapshot, not a v0.5.5 tag. At sync, the imported-key fingerprint follow-up `fix/acg-key-fingerprint` and planned `brace-expansion` update were not merged upstream. No ACG sandbox or live infrastructure was touched.

The initial subtree pull exited 1:

```text
From /Users/cliang/src/gitrepo/personal/lib-foundation
 * branch              339a713391998703875e7634c91edb1c70a843e4 -> FETCH_HEAD
Auto-merging scripts/lib/foundation/memory-bank/activeContext.md
CONFLICT (content): Merge conflict in scripts/lib/foundation/memory-bank/activeContext.md
Auto-merging scripts/lib/foundation/memory-bank/progress.md
CONFLICT (content): Merge conflict in scripts/lib/foundation/memory-bank/progress.md
Auto-merging scripts/lib/foundation/scripts/lib/acg/acg.sh
Auto-merging scripts/lib/foundation/scripts/tests/lib/acg.bats
Automatic merge failed; fix conflicts and then commit the result.
```

The conflicts were resolved to the newer upstream records. A staged tree comparison initially reported 173 differences because the diagnostic mistakenly compared Git's literal `blob` field against hashes. After correcting the parser, actual output was:

```text
staged files 173 upstream files 173 differences 0
```

The initial staged audit failed with the existing embedded-AWK false positive; its exact output, root cause, narrow path-specific allowlist and follow-up are in `2026-11-01-foundation-subtree-audit-awk.md`. The staged audit passed after the documented exception.

Verification: clean-environment BATS through the tripwire returned 179/179, with no live command reached; full output is `/private/tmp/k3dm-foundation-sync-bats.log`. ACG Jest returned:

```text
Test Suites: 8 passed, 8 total
Tests:       53 passed, 53 total
Snapshots:   0 total
```

`shellcheck -S warning` on the changed upstream `system.sh` and `acg.sh` and `git diff --cached --check` both exited 0 with no output. Follow-up: merge and verify the separate fingerprint fix, land the upstream brace-expansion update, release/tag the intended v0.5.5, then sync that release; the operator's next normal ACG session can exercise duplicate-key behavior. The macmon fleet collector and machine-setup integration are not implemented by this subtree sync.
