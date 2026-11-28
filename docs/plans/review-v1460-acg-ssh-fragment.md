# Review: ACG ssh config fragment — lib-foundation v0.5.12 + k3d-manager v1.46.0 (blind spec review)

**Filed:** 2026-11-27
**Repo / branch:** `k3d-manager` / `k3d-manager-v1.46.0` (lib-foundation code is vendored at `scripts/lib/foundation/`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Neon (agy, `gemini-4-neon-high`), role review; Fable reviews the same text separately

## Task

Review two specs together: [`v1.46.0-acg-ssh-config-fragment.md`](v1.46.0-acg-ssh-config-fragment.md) (k3d-manager)
and the lib-foundation spec at `/Users/cliang/src/gitrepo/personal/lib-foundation/docs/plans/v0.5.12-acg-ssh-sandbox-fragment.md`
(read it at that absolute path; if your sandbox cannot read it, say so and review the k3d-manager spec plus the
vendored `scripts/lib/foundation/scripts/lib/acg/acg.sh`). Do not edit any file. No network; never read Keychain values;
never print whole dotfiles (grep `^Include|^Host` only); do not run any sandbox, ssh or make lifecycle target.

Answer:

- Does every writer of ACG/GCP/Azure Host entries move to the fragment, and every reader of those aliases (`ssh ubuntu`,
  `ubuntu-<n>`, `ubuntu-tunnel`, scp, tunnels, `bin/cluster-up`, plugins) still resolve them through the Include line?
- Is `~/.ssh/k3dm-sandbox.conf` (not `config.d/`) the right default given `~/.ssh/config` and `config.d` are symlinks
  into a dotfiles repo? File and directory modes; atomic writes that never replace a symlink.
- Missing Include line: warn vs fail before cluster steps — which is safer given provisioning breaks after the VM exists?
- Teardown removes only the fragment's own entries; never touches `~/.ssh/config`.
- Tests: scratch HOME guards, red-on-current for the `mv` over a symlink, the 8-`if` agent-audit limit for the subtree
  pull. Can each `must_not` fail as stated? Every cited file:line correct? Anything missing from Files / Contract readers?

## Files

| File | Change |
|---|---|
| `docs/plans/v1.46.0-acg-ssh-config-fragment.md` | read only (start here) |
| `scripts/lib/foundation/scripts/lib/acg/acg.sh` | read only |
| `scripts/lib/providers/k3s-gcp.sh` | read only |
| `scripts/lib/providers/k3s-az.sh` | read only |

## What NOT to Do

- Do not edit, create, stage or commit any file. Do not contact any host.

## Output

Findings most severe first, each tagged BLOCKER / MAJOR / MINOR with file:line evidence and a concrete fix, then a
verdict for each spec: READY, NEEDS FIXES, or REWRITE.

## Acceptance

```yaml
must:
  - id: M1
    text: every finding cites file:line and a concrete fix; the review ends with a verdict per spec
must_not:
  - id: N1
    text: the reviewer changes any file or makes a network call
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: git status --short in the review worktree is empty; report has findings and verdicts
    intent: A second model checks the ACG ssh-config fix before Luna builds it, so sandboxes stop editing your dotfiles without breaking ssh to the sandbox.
interface: none
```

**Intent approved:** operator, 2026-11-27
**Approval words and scope:** "can you start first group - 5 P2s (review by Fable/Neon)"
