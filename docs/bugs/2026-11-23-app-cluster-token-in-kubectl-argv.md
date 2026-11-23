# Bug: app-cluster bearer token passed in kubectl argv by the CVE scan and verifier

**Status:** OPEN — spec rev 1 (Fable review pending)
**Priority:** P2
**Introduced by:** pre-existing in `cve-remediation-verify.sh:9-11` (not in the v1.45.0 diff); `app-cve-scan.sh:149-160` unknown (file rewritten in plan 2e)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-23 (Fable spec review)
**Triage:** patch → v1.45.1 (operator, 2026-11-23: "distribute tasks across flash and luna")
**Branch:** k3d-manager-v1.45.1
**Intent approved:** pending
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unavailable: cluster context missing); grep of docs/bugs for the key terms found no match
**Detected by:** v1.45.0 red-team gate, 2026-11-22, on `7dfb7238` — see [docs/issues/2026-11-23-v1.45.0-red-team.md](../issues/2026-11-23-v1.45.0-red-team.md)
**Severity:** breaks the repository rule "no tokens in arguments"; visible in the process list inside the job pod or on its node.
**Findings:** Astra 5 (Medium), Fable 11 (Low). Claude: confirmed, P2.

## What is wrong

`scripts/etc/argocd/platform-ops/app-cve-scan.sh:149-160` (`_app_kubectl`) and `cve-remediation-verify.sh:9-11` (`_app`) run
`kubectl --server ... --token "$TOKEN"`. Both also honour `--insecure-skip-tls-verify=true` when the cluster secret says so.

## Fix direction

Write a 0600 kubeconfig in the job's tmpfs and pass `--kubeconfig`; refuse the insecure branch outside dev.

## Fix (spec rev 1, Claude, 2026-11-23)

Both scripts stop passing the token, server and TLS options as kubectl arguments. After reading the cluster secret,
each writes a kubeconfig into a private temp directory (`umask 077; mktemp -d`, file mode 0600) and every app-cluster
call becomes `"$KUBECTL" --kubeconfig "$file" "$@"`.

1. **`app-cve-scan.sh`**: `_load_app_cluster_access` writes the kubeconfig after it parses `server`, `bearerToken`,
   `caData` and `insecure`. The cluster entry carries `server`, then either `insecure-skip-tls-verify: true` (when the
   secret says `insecure: true`, as today), or `certificate-authority-data: <caData as in the secret>`, or neither. The
   user entry carries `token`. `_app_kubectl` becomes the one `--kubeconfig` call. The CA temp file is no longer needed
   (the base64 `caData` goes into the kubeconfig as is). `_cleanup` removes the temp directory. Clear
   `_APP_CLUSTER_TOKEN` once the file is written.
2. **`cve-remediation-verify.sh`**: the same, with `_load_access` and `_app`, plus an `EXIT INT TERM` trap that removes
   the directory. Today the script has no trap and leaves its CA temp file behind.
3. **How the file is written:** a heredoc or the shell's builtin `printf` only. Never an external command (`/usr/bin/printf`,
   `echo` via `env`, `tee`) that takes the token as an argument. Values are written double-quoted. The scripts run under
   `/bin/sh` in `docker.io/alpine/k8s:1.33.13` (busybox ash: `printf` is a builtin).
4. **Unchanged:** the insecure-TLS behaviour (it moves into the kubeconfig and keeps working as today). Refusing it
   outside dev is the bug doc's second fix direction, but the live `cluster-ubuntu-hostinger` secret may set
   `insecure: true`, so refusing it could stop the scan. That decision is held as an open question, not in this fix.

## External behaviour

- kubectl reads a bearer token from a kubeconfig user `token` field and sends it as `Authorization: Bearer`, with nothing
  token-related in its own argv. Claude, m4-air.local, 2026-11-23, kubectl client v1.37.2: a 0600 kubeconfig with
  `token: DUMMYPROBETOKEN` and `insecure-skip-tls-verify: true` against `https://127.0.0.1:1`, run with
  `kubectl --kubeconfig <f> get ns -v=8`, logged `Authorization: Bearer <masked>` on each attempt. The kubeconfig `token`,
  `certificate-authority-data` and `insecure-skip-tls-verify` fields are stable Config v1 fields, also read by the job's
  kubectl 1.33.13. The worker's offline tests stub kubectl, so this does not run in CI.

## Contract readers

| Where | Reads | Change |
|---|---|---|
| `scripts/etc/argocd/platform-ops/app-cve-scan.sh:149-161` `_app_kubectl` | server, token, CA file, insecure | single `--kubeconfig` call |
| `app-cve-scan.sh:259,267` | `_app_kubectl` | none (same call shape) |
| `app-cve-scan.sh:51-57` `_cleanup` | `_APP_CLUSTER_CA_FILE` | removes the kubeconfig dir instead |
| `app-cve-scan.sh:97-118` `_load_app_cluster_access` | the cluster secret | writes the kubeconfig |
| `scripts/etc/argocd/platform-ops/cve-remediation-verify.sh:8-12` `_app`, `:13-18` `_load_access` | same | same; adds a trap |
| `cve-remediation-verify.sh:59,61` | `_app` | none |
| `scripts/tests/plugins/app_cve_scan.bats:357-378` kubectl stub | skips `--server/--token/--certificate-authority/--insecure-skip-tls-verify=true` | also skips `--kubeconfig <f>`; records the kubeconfig's existence and mode |
| `scripts/tests/plugins/cve_remediation_verify.bats:3` | sources the script up to `_load_access` | unchanged; new tests drive `_load_access` with a stubbed `_hub` |
| `scripts/etc/argocd/platform-ops/app-cve-scan-cronjob.yaml:72,212` | image `alpine/k8s:1.33.13` (kubectl, busybox sh) | none |

Not readers: `ARGOCD_APP_CLUSTER_TOKEN` in `scripts/plugins/argocd.sh`, `cluster-secret.yaml.tmpl`, `bin/cluster-up` and
`bin/cluster-preflight` write the secret these scripts read. Its format (`bearerToken`, `tlsClientConfig.caData`,
`insecure`) does not change.

## Acceptance

```yaml
must:
  M1: every app-cluster kubectl call from app-cve-scan.sh and cve-remediation-verify.sh passes --kubeconfig <file> and nothing else for server, token or TLS
  M2: the kubeconfig file is mode 0600, inside a directory created with mktemp -d under umask 077, and holds the secret's server, token, and either insecure-skip-tls-verify true or certificate-authority-data, matching what the secret says
  M3: the kubeconfig directory is gone after each script exits, on success and on failure (EXIT trap in both scripts)
must_not:
  N1: the bearer token appears in any kubectl argv either script produces, for the insecure, CA and plain secret shapes
  N2: the token is passed as an argument to any external command while the kubeconfig is written (heredoc or builtin printf only)
  N3: existing behaviour changes: every existing app_cve_scan*.bats and cve_remediation_verify.bats test passes, with only the kubectl stub's flag skipping extended
evidence:
  - {id: E1, proves: [M1, N1], kind: offline, intent: "You will see tests run the CVE scan and the verifier against a fake kubectl that logs every call, for a secret with a CA, one marked insecure and a plain one, and find --kubeconfig in every app-cluster call and the token string in none.", command: "bats scripts/tests/plugins/app_cve_scan.bats scripts/tests/plugins/cve_remediation_verify.bats", red: "today's tree: the token appears after --token in the log, so the new N1 checks fail"}
  - {id: E2, proves: [M2], kind: offline, intent: "You will see a test stop the fake kubectl mid-run, read the kubeconfig it was given, and find mode 600, the secret's server and token, and the right TLS line for each secret shape.", command: "same run", red: "write the file without umask 077 or with insecure always true: the mode or shape check fails"}
  - {id: E3, proves: [M3], kind: offline, intent: "You will see the kubeconfig directory checked after a run that succeeds and after one where the fake kubectl fails, and it is gone both times.", command: "same run", red: "drop the trap in cve-remediation-verify.sh: the directory survives and the check fails"}
  - {id: E4, proves: [N2], kind: offline, intent: "You will see a check that the lines writing the kubeconfig use a heredoc or the builtin printf, and that no external printf, echo or tee takes the token.", command: "grep -n -E '(/usr/bin/printf|command printf|env .*printf|tee ).*TOKEN' scripts/etc/argocd/platform-ops/app-cve-scan.sh scripts/etc/argocd/platform-ops/cve-remediation-verify.sh returns nothing; shellcheck -s sh on both files clean", red: "write the file with /usr/bin/printf: the grep matches"}
  - {id: E5, proves: [N3], kind: offline, intent: "You will see the whole existing CVE-scan and verifier suites pass, with only the fake kubectl's flag-skipping changed.", command: "same bats run; git diff of the two .bats files shows only the stub's case line and new tests", red: "n/a (regression guard)"}
  - {id: E6, proves: [M1, N1], kind: live, intent: "You will see Claude, after a hub promote, read the next app-cve-scan job's log on the hub (read-only) and find it listing VulnerabilityReports from the app cluster as before.", command: "kubectl --context k3d-k3d-cluster -n platform-ops logs job/<latest app-cve-scan> | tail (on m5-air)", red: "n/a (live)"}
interface:
  - "app-cve-scan.sh: _app_kubectl <kubectl args> unchanged; _load_app_cluster_access unchanged signature"
  - "cve-remediation-verify.sh: _app <kubectl args> unchanged; _load_access unchanged"
```

## Files

| File | Change |
|---|---|
| `scripts/etc/argocd/platform-ops/app-cve-scan.sh` | kubeconfig in `_load_app_cluster_access`, `_app_kubectl`, `_cleanup` |
| `scripts/etc/argocd/platform-ops/cve-remediation-verify.sh` | kubeconfig in `_load_access`, `_app`, new trap |
| `scripts/tests/plugins/app_cve_scan.bats` | stub skips `--kubeconfig`; new E1-E3 tests |
| `scripts/tests/plugins/cve_remediation_verify.bats` | new E1-E3 tests |

## Routing

Luna: 2 script files of shell logic plus 2 test files. Not Flash (logic and tests).

## Worker definition of done

- Change only the files in the table. Offline only: stub kubectl on PATH; no cluster, no network, no Keychain.
- Show the new N1 tests red on today's tree, then green. Mutation: put `--token` back in each of the three branches in
  turn and show a test goes red.
- `shellcheck -s sh` on both scripts; the full `bats` run of the two suites with rc and counts.
- Leave changes uncommitted; no push; E6 belongs to Claude; do not touch `docs/bugs/`.

## Open question (operator)

Should the insecure-TLS branch be refused outside dev (the bug doc's second fix direction)? First check the live
`cluster-ubuntu-hostinger` secret's `insecure` value (read-only, presence and value of that one field only).

