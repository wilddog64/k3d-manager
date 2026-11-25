# Bug: first web-console install prints "Unable to load host key" twice

**Status:** OPEN — captured 2026-11-21 during the priv_open E4 live check
**Priority:** P3 (cosmetic: the install succeeds, but the two lines look like a failure to the operator)
**Triage:** backlog — pull into a release that already touches `bin/k3dm-web-console-sshd` (operator, 2026-11-25); Argon blind classification, Claude verified
**Introduced by:** unknown (web-console part A, v1.45.0)
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Cosmetic stderr noise on first `install-web-console-sshd` run where `sshd -t`/`-T` prints two harmless "Unable to load host key" warnings before succeeding.)
**Waiting on:** operator decision
**Prior art:** exact-slug glob none; grep `Unable to load host key` in docs/bugs and docs/issues none; `make find-similar-docs` not run (vector store unavailable)

## Symptom

m4-air, 2026-11-21 03:17Z, main checkout at 9f637a48: on a first install (no `/etc/k3dm-web-console/ssh_host_ed25519_key` yet),
`make install-web-console-sshd CA_FILE=<throwaway CA>` prints, after the CA fingerprint:

    web-console-sshd: Unable to load host key: /etc/k3dm-web-console/ssh_host_ed25519_key
    web-console-sshd: Unable to load host key: /etc/k3dm-web-console/ssh_host_ed25519_key

The install then completes, and `make web-console-sshd-check` passes C1-C7 and C10.

## Cause (suspected, from the code)

`_wc_validate` (`bin/k3dm-web-console-sshd:514-524`) runs `sshd -t` and then `sshd -T`, each with `-f <staged sshd_config>
-h <staged host key>`. The staged config contains `HostKey /etc/k3dm-web-console/ssh_host_ed25519_key` (`:30`). On a first
install that path does not exist yet (the new key is in the stage, `:465-469`), so each sshd run warns once about the
configured path, loads the `-h` key, and exits 0. `_wc_sshd_diagnostics` passes the warning through to stderr.

## Fix direction (not decided)

Either filter this exact warning in `_wc_sshd_diagnostics` when the host key is the staged one, or validate with a staged
config whose `HostKey` names the staged key. Must not hide other sshd validation diagnostics.
