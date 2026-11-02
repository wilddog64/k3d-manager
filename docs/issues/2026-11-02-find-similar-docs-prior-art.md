# Vector search for cluster-up CA trust prior art

On 2026-11-02, `make find-similar-docs` on M5 returned relevant historical CA-trust plans and bugs, and a timeout query returned the orphaned CloudFormation stack bug. The search results informed the dispatch scope; three targeted queries do not establish whether vector search is better than alternatives.

On M4, three local searches returned exit 0 but printed the following diagnostic and returned no retrieval results:

```text
find-similar-docs: retrieval unavailable — no embeddings credential. $K3DM_EMBEDDINGS_API_KEY is unset or empty; k3dm-embeddings-api-key: rc 44 — security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain.; gemini-cli-api-key: rc 44 — security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain.; hub Vault: cannot read vault-root: Unable to connect to the server: dial tcp 127.0.0.1:55730: connect: operation not permitted
find-similar-docs: falling back to the exact-slug glob is still correct.
```

An attempt to repeat the successful M5 queries from the restricted environment failed for each query with:

```text
ssh: Could not resolve hostname m5-air.local: nodename nor servname provided, or not known
```

M4 lacked the embedding credentials available to this process and the sandbox prevented the attempted local Vault connection; the later restricted SSH environment could not resolve M5. Follow up by restoring an appropriate credential source and testing retrieval against a representative set of known documents and a keyword-search baseline. A zero exit status alone does not prove vector retrieval took place.

The restricted sandbox also produced a misleading initial dispatch status:

```text
task: 2026-11-02-acg-up-stalls-at-system-keychain-trust
state: terminated unexpectedly (see /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.14/2026-11-02-acg-up-stalls-at-system-keychain-trust.run/supervisor.log)
repo: k3d-manager
scope: in-scope
```

The sandbox denied `ps` with `zsh:1: operation not permitted: ps`. Checking outside the sandbox returned:

```text
task: 2026-11-02-acg-up-stalls-at-system-keychain-trust
state: running
repo: k3d-manager
scope: in-scope
```

The process supervisor was also present. Use an environment permitted to inspect the worker process when checking dispatch status.

Luna's first run exited successfully, but reported these broader-suite results:

```text
- `make test`: exit 2 — 1,979 cases: 1,958 passed, 20 skipped, 1 failed. Failure: `smoke test ESO wiring samples app and hub through helper`. The tripwire blocked 553 host-tool calls; none reached a real binary.
- `make test-pytest`: exit 1 — 1,783 tests: 1,775 passed, 4 skipped, 4 failed. Failures were dashboard query, dispatch metrics, and two OrbStack metrics tests; their Docker/promtool calls were blocked by the tripwire.
```

These are the worker's reported results; independently diagnose the failures before claiming broad verification. Review also found missing explicit tests of interactive and non-Darwin paths and elapsed timeout. The worker was resumed to address those gaps.

The continuation reported 75 focused BATS cases passed and added those tests. Its audit was run while the proposed changes were unstaged. It also identified that its process tree fixture runs under the test user's ownership and cannot prove cleanup of a privileged `security` descendant. The production runner may invoke `sudo -n /usr/bin/security`; the unprivileged process-group timeout must not be assumed to kill a root-owned descendant. Luna was resumed again to investigate without live privileged tests. Independent verification and staged audit remain pending.

The latest Luna continuation exited successfully but explicitly reported the fix blocked. Its scratch-only detached-child regression reproduced a delayed side effect:

```text
1..76
not ok 6 headless Vault CA timeout prevents a detached descendant's delayed side effect
# continued
# delayed scratch effect observed: True
# AssertionError: detached child survived timeout and produced a delayed effect
```

The worker reported 75 passed, 1 failed, 0 skipped for the focused suite. Its proposed design requires investigation of a narrowly authorized privileged supervisor; whether it can guarantee termination and prevent further macOS authorization or Keychain service work remains unproven. Do not land the patch or record a verification pass until the acceptance criteria are met.
