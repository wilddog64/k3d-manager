# Bug: ask Bash shell strings bypass filesystem scope checks

**Filed:** 2026-10-08
**Status:** LIVE-VERIFIED 2026-10-08 — FIXED in branch `b2c45ae3`; top-level `ask claude: which shell are you in` answered "bash" in thread (operator screenshot)
**Severity:** HIGH (authenticated AI path; file confidentiality)
**Branch:** k3d-manager-v1.42.0
**Reviewed revision:** 6e54ca66bddf47973eff57216d290b5df821b529
**Component:** bin/k3dm-ask-bash; scripts/lib/webhook/agent.py
**Evidence:** [Offline security review](../issues/2026-10-08-webhook-cloud-bridge-security-review.md)

## Problem

The wrapper checks only argv elements beginning with /, then executes /bin/bash "$@".
The normal Bash-tool invocation uses -c followed by one shell string, such as
"cat /absolute/path". That argv element begins with cat, so the absolute file inside
it is never checked. A plain cat does not match the command denylist. Relative paths,
tilde expansion and shell-expanded paths likewise are not confined by this absolute-argv loop.

The allowed path test also uses a lexical prefix without requiring a directory boundary.
Canonicalization falls back to the original string when realpath -m is unavailable.
These additional source concerns were not separately reproduced on macOS.

## Reproduction and actual result

An exact copy of the reviewed wrapper was run in this cloud Linux workspace with /bin/bash,
-c, and cat of a newly created non-sensitive canary under /workspace/scratch/f76985e49dec.
That path is outside the wrapper's default repository and diagnosis allowlists.

```text
Sandbox out-of-scope synthetic canary read: exit 0 output HARMLESS_CANARY
```

Temporary wrapper/canary files were deleted by TemporaryDirectory cleanup. No real credential
was read, no network egress was attempted, and no command ran on the operator laptop.
The argv scope defect is source-level; macOS/deployed agent end-to-end reach remains unverified.

## Impact and limits

A tool-enabled AI influenced by a signed-in reader's question or malicious content it reads
may access files readable by its OS account outside the promised scope. Sensitive material
could then appear in the model response or output; actual credential access/exfiltration is
not demonstrated. The wrapper is injected through PATH for Claude, not an OS filesystem
sandbox. Prompt instructions and regex jailbreak filters do not enforce file permissions.
Codex's local CLI sandbox settings were not verified in this review.

The earlier hardening did block many interpreters, network clients and make in read-only
mode. Those controls are present and should remain; they do not fix this path-check seam.

## Required fix and acceptance

- Enforce a filesystem boundary outside the model and shell string, preferably with a
  dedicated least-privilege account/container and minimal mounted inputs/credentials.
- Replace arbitrary shell evaluation with structured, vetted diagnostic tools where practical.
  Do not rely on more regexes to parse a general shell.
- Deny external canary reads through -c, relative paths, tilde, substitutions, symlinks and
  sibling-directory prefixes; prove allowed repository diagnostics still work.
- Cover the real agent tool invocation path in addition to standalone wrapper tests.
- Restrict environment/credential inheritance and output disclosure; preserve role-gated fixes
  through narrowly scoped tools rather than broad host privileges.

## Prior art

[September security audit](../issues/2026-09-07-webhook-server-security-audit.md), F2, and
[Phase 1 sandbox hardening plan](../plans/v1.32.0-ask-bash-sandbox-hardening.md).
This is a concrete surviving scope bypass after Phase 1, not a claim that its fixes vanished.

## Fix

Commit `b2c45ae3c2e8a96c383b943bab242e8a3f0e9d59` adds shell-string scope checks with
canonical directory-boundary matching, fail-closed path handling, a Darwin `sandbox-exec`
read boundary, and `$SHELL` injection for the agent subprocess.

Status: FIXED in branch; live verification pending.
