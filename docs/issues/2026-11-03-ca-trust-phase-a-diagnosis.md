# Phase A diagnosis: ACG CA trust stall

**Result:** Inconclusive for the real incident; containment may proceed after operator review. Job `c38c3855` last logged the Vault CA System Keychain trust message, then timed out at 3,300 seconds. The screenshot's password-prompt explanation was a hypothesis. Existing read-only evidence, including the 2026-11-02 sudo policy and unified-log checks, is in `docs/issues/2026-11-02-acg-up-job-c38c3855.md`; it does not identify the blocked process. The failed run occurred before the operator's later M5 pull. The later checked-in revision `8d9f5f0f` still shows the same trust message followed by `_run_command --interactive-sudo --soft`, but is not proof of the exact revision deployed during the failed job.

The current checked-in webhook spawns `make up` with stdout and stderr redirected to an output file and waits on the spawned job PID. The checked-in command runner chooses `sudo -n` if either stdin or stdout is not a TTY. That describes the inspected code, not proof of the old job's environment or process state. The pipe fixture below illustrates a possible problem in a pipe-based intermediary; it does not show that the webhook itself waited on a pipe.

## Isolated diagnostic reproduction

On M4, ran `/private/tmp/k3dm-phase-a-diagnose.py` with the checked-in `_run_command` implementation and fake `sudo` and `security` programs in a private scratch directory. It inspected only its own fixture process IDs, then killed the controlled processes. No real sudo, security, Keychain, AWS or cluster operation was invoked. Complete terminal output:

```text
case=sudo_stall caller=running stdout=open markers=sudo sudo_args=-n /private/tmp/k3dm-phase-a-i79qep98/bin/security add-trusted-cert
  sudo: 34897 34894 S    /bin/sleep
case=security_stall caller=running stdout=open markers=sudo,security sudo_args=-n /private/tmp/k3dm-phase-a-i79qep98/bin/security add-trusted-cert
  sudo: 35020 35017 S    /bin/bash
  security: 35021 35020 S    /bin/sleep
case=pipe_stall caller=exited(0) stdout=open markers=sudo,security,pipe sudo_args=-n /private/tmp/k3dm-phase-a-i79qep98/bin/security add-trusted-cert
  sudo: not-running
  security: not-running
  pipe: 35141     1 S    /bin/sleep
all diagnostic scenarios behaved as designed; fake commands only
```

| Observation | Interpretation |
| --- | --- |
| Fake sudo blocked before starting fake security | The process tree can distinguish a runner/authorization-side stall from an operation that has begun. |
| Fake security started and did not return | The tree can distinguish an executing operation that has stalled. This does not identify whether real macOS security or its service is responsible. |
| Both fake commands exited, but a descendant retained stdout | A pipe-based reader can remain open after its caller exits. The current webhook writes to a file and waits on a PID, so its own hang requires separate evidence. |
| All isolated scenarios passed; no live recurrence | Actual root cause remains unresolved; Phase B containment can proceed without claiming one. |

## Follow-up evidence for a later normal live run

If the stall recurs, capture a timestamped process tree with parent PID, process group, session, command, state, elapsed time and TTY for the webhook job and its descendants; capture the running revision, job environment and stdout/stderr destination without recording credentials. Record whether sudo and security started and exited, and obtain relevant sudo/macOS authorization logs. Capture before timeout destroys the processes. Live reproduction and any AWS stack inspection are deferred to the operator's normal sandbox session; stack status is currently unknown because the earlier read-only query returned `InvalidClientTokenId`.
