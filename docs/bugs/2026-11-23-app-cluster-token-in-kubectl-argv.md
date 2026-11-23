# Bug: app-cluster bearer token passed in kubectl argv by the CVE scan and verifier

**Status:** OPEN — spec rev 2 (Fable rev 1: NEEDS FIXES, 2 blockers, 6 should-fix, 2 nits; all applied)
**Priority:** P2
**Introduced by:** pre-existing in `cve-remediation-verify.sh:9-11` (not in the v1.45.0 diff); `app-cve-scan.sh:149-160` unknown (file rewritten in plan 2e)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-23 (intent approval)
**Triage:** patch → v1.45.1 (operator, 2026-11-23: "distribute tasks across flash and luna")
**Branch:** k3d-manager-v1.45.1
**Intent approved:** operator, 2026-11-23
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unavailable: cluster context missing); grep of docs/bugs for the key terms found no match
**Detected by:** v1.45.0 red-team gate, 2026-11-22, on `7dfb7238` — see [docs/issues/2026-11-23-v1.45.0-red-team.md](../issues/2026-11-23-v1.45.0-red-team.md)
**Severity:** breaks the repository rule "no tokens in arguments"; visible in the process list inside the job pod or on its node.
**Findings:** Astra 5 (Medium), Fable 11 (Low). Claude: confirmed, P2.

## What is wrong

`scripts/etc/argocd/platform-ops/app-cve-scan.sh:149-160` (`_app_kubectl`) and `cve-remediation-verify.sh:9-11` (`_app`) run
`kubectl --server ... --token "$TOKEN"`. Both also honour `--insecure-skip-tls-verify=true` when the cluster secret says so.

## Fix direction

Write a 0600 kubeconfig in the job's tmpfs and pass `--kubeconfig`; refuse the insecure branch outside dev.

## Fix (spec rev 2, Claude, 2026-11-23)

Both scripts stop passing the token, server and TLS options as kubectl arguments. After reading the cluster secret,
each writes a complete kubeconfig into a private temp directory and every app-cluster call becomes
`"$KUBECTL" --kubeconfig "$file" "$@"`.

1. **Kubeconfig shape (blocker, rev 2).** The file holds exactly one cluster, one user, one context joining them, and
   `current-context` naming that context. Without `current-context`, kubectl inside a pod silently falls back to the
   in-cluster config, i.e. the **hub** API with the job's own ServiceAccount (proved below, case B). The cluster entry
   carries `server`, then either `insecure-skip-tls-verify: true` (secret says `insecure: true`), or
   `certificate-authority-data: <caData as in the secret>` (base64 as is), or neither. The user entry carries `token`.
2. **Where it is written.** The directory is `mktemp -d "${APP_KUBECONFIG_TMPDIR:-${TMPDIR:-/tmp}}/k3dm-kc.XXXXXX"`
   (`mktemp -d` creates it 0700). The file is written inside a subshell that sets `umask 077`, so the umask does not
   leak to the rest of the script (nit, rev 2), and is mode 0600. Both CronJob pods mount a memory-backed `emptyDir`
   at `/kubeconfig-tmp` (`medium: Memory`, `sizeLimit: 1Mi`) and set `APP_KUBECONFIG_TMPDIR=/kubeconfig-tmp`, so the
   token never touches the node's disk. Not at `/tmp`: the scan container uses `/tmp` as `HOME`, for
   `TRIVY_CACHE_DIR=/tmp/.cache/trivy` (the Trivy DB, hundreds of MB), for its `mktemp` work files and for
   `/tmp/cosign-verify*.txt`; a memory `/tmp` would count all of that against the 1536Mi limit. Neither pod sets
   `readOnlyRootFilesystem`; the scan pod runs as 65534 with `fsGroup: 65534`, the verifier as 1001 with no fsGroup
   (an emptyDir is world-writable, so both can create the subdirectory).
3. **How it is written.** A heredoc (to `cat` on stdin) or the shell's builtin `printf` only. Never an external
   command that takes the token as an argument. Values are written double-quoted. Before writing, each value is checked
   with a `case` pattern (a builtin): server, token and caData may hold only `[A-Za-z0-9._~+/=:-]`; on any other
   character (a quote, backslash or newline would break or inject into the YAML) the script logs that the secret is
   malformed, writes no file and returns non-zero. The scripts run under `/bin/sh` in
   `docker.io/alpine/k8s:1.33.13` (busybox ash: `printf` is a builtin, proved below).
4. **`app-cve-scan.sh`.** `_load_app_cluster_access` (:96-118) writes the kubeconfig after it parses `server`,
   `bearerToken`, `caData` and `insecure`; the CA temp file goes away. `_app_kubectl` (:149-161) becomes the one
   `--kubeconfig` call. `_cleanup` (:51-57) removes the kubeconfig directory. `_APP_CLUSTER_TOKEN` is cleared once the
   file is written. The trap at :58 becomes `trap _cleanup EXIT`, `trap '_cleanup; exit 130' INT`,
   `trap '_cleanup; exit 143' TERM` (nit, rev 2: today an INT/TERM trap that only cleans up lets `sh` carry on).
5. **`cve-remediation-verify.sh`.** The same with `_load_access` (:13-18) and `_app` (:8-12). **The trap is set
   inside `_load_access`, before `mktemp -d`** (blocker, rev 2), in the same three-trap form. A top-level trap is not
   allowed: `cve_remediation_verify.bats:3` sources the script up to the top-level `_load_access` call
   (`sed '/^_load_access$/,$d'`), so a top-level trap would replace BATS's own EXIT trap. New tests call
   `_load_access` only inside a subshell, where the trap fires when the subshell exits. Today the script has no trap and
   leaves its CA temp file behind.
6. **Unchanged: insecure TLS.** The insecure branch moves into the kubeconfig and keeps working. It is not refused:
   live tooling writes that shape for the very secret these scripts read (`bin/cluster-refresh:290-299` writes
   `cluster-${_app_context}` with `{"bearerToken":…,"tlsClientConfig":{"insecure":true}}`), so refusing it would stop
   the scan on every refreshed cluster. Rev 1's open question is closed on that basis; tightening the writer is
   separate work.

## External behaviour

All probes: Claude, m4-air.local, 2026-11-23T16:58Z, Docker 29.8.2, inside the job image itself,
`docker.io/alpine/k8s:1.33.13@sha256:e521cee1f1cb8699bc6e906b4ce6fe50e84addae97f52d5dcf05d3974002ac26`
(`kubectl version --client`: v1.33.13), `docker run --rm --network none`. Dummy values only (`DUMMYPROBETOKEN`,
`DUMMYSATOKEN`). To imitate a pod, each run set `KUBERNETES_SERVICE_HOST=10.0.0.1 KUBERNETES_SERVICE_PORT=443` and wrote a
dummy ServiceAccount token, namespace and `ca.crt` under `/var/run/secrets/kubernetes.io/serviceaccount`. The kubeconfig
server was `https://192.0.2.10:6443` with `insecure-skip-tls-verify: true`; `kubectl --kubeconfig <f> get ns -v=8`.

| Case | Kubeconfig | Request went to |
|---|---|---|
| A | complete (cluster, user, context, `current-context`), mode `-rw-------` | `https://192.0.2.10:6443/api` with `Authorization: Bearer <masked>`, nothing token-related in argv |
| A2 | same, plus `--request-timeout=2s` | `https://192.0.2.10:6443/api` |
| **B** | **same minus `current-context`** | **`https://10.0.0.1:443/api` — the in-cluster (hub) API** |
| C | `--kubeconfig=` (empty string) | `https://10.0.0.1:443/api` |
| D | no `--kubeconfig` | `https://10.0.0.1:443/api` |
| E | `--kubeconfig /nonexistent` | `error: stat /nonexistent: no such file or directory`, no request |
| F | `apiVersion`/`kind` only | `https://10.0.0.1:443/api` |

- Case B proves the rev 1 blocker: an incomplete kubeconfig quietly sends app-cluster reads to the hub. Hence M2
  requires all four entries, and E2 asserts them.
- Caveat on B: when an override flag such as `--request-timeout` is also given, kubectl 1.33.13 does not fall back to
  in-cluster and goes to `http://localhost:8080` instead (seen on the first run). Neither outcome is safe.
- Case E: a missing file fails closed. That is why `_app_kubectl` must not be reachable with an empty path; case C
  shows an empty path falls back to the hub.
- `type printf` in the image's `/bin/sh`: `printf is a shell builtin`.
- The worker's offline tests stub kubectl, so none of this runs in CI. E6 is the live check.

## Contract readers

| Where | Reads / writes | Change |
|---|---|---|
| `scripts/etc/argocd/platform-ops/app-cve-scan.sh:149-161` `_app_kubectl` | server, token, CA file, insecure | single `--kubeconfig` call |
| `app-cve-scan.sh:259,267` | `_app_kubectl` | none (same call shape) |
| `app-cve-scan.sh:51-58` `_cleanup` + trap | `_APP_CLUSTER_CA_FILE` | removes the kubeconfig dir; three-trap form |
| `app-cve-scan.sh:96-118` `_load_app_cluster_access` | the cluster secret | writes the kubeconfig |
| `scripts/etc/argocd/platform-ops/cve-remediation-verify.sh:8-12` `_app`, `:13-18` `_load_access` | same | same; trap inside `_load_access` |
| `cve-remediation-verify.sh:59,61` | `_app` | none |
| `scripts/etc/argocd/platform-ops/app-cve-scan-cronjob.yaml:71-151` (scan pod), `:211-236` (verifier pod) | image `alpine/k8s:1.33.13`, volumes | adds the `/kubeconfig-tmp` memory emptyDir and `APP_KUBECONFIG_TMPDIR` to both |
| `scripts/tests/plugins/app_cve_scan.bats:357-378` kubectl stub | skips `--server/--token/--certificate-authority/--insecure-skip-tls-verify=true` | also skips `--kubeconfig <f>`; copies the file and records its mode for E2 |
| `scripts/tests/plugins/app_cve_scan.bats:458` | the only secret fixture (insecure shape) | adds CA and plain fixtures |
| `scripts/tests/plugins/cve_remediation_verify.bats:3` | sources the script up to the top-level `_load_access` | unchanged; why the trap must be inside the function |
| `scripts/tests/plugins/app_cve_scan_pins.bats:35-37` | builds a driver from `app-cve-scan.sh` up to `# === MAIN ===` (includes the trap) | none expected; must stay green (N3) |
| **writer** `bin/cluster-refresh:290-299` | writes `cluster-${_app_context}` in `cicd` with the **insecure** shape | none; the reason insecure stays (Fix 6) |
| **writer** `scripts/plugins/hub_recovery.sh:107-124` `_hub_recovery_seed_app_cluster_reader` | writes `{server,caData,bearerToken}` to Vault `platform-ops/app-cluster-hostinger`; `app-cluster-kubeconfig-externalsecret.yaml:21` renders it as `{"bearerToken","tlsClientConfig":{"caData"}}` (the **CA** shape) | none; the CA shape the new fixture copies |
| reader `scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml:100-118` | reads the CA-shape secret (`bearerToken`, `caData`) from `/etc/app-cluster` in Python, never via kubectl argv | none; listed because it shares the secret format |

Also writers of `cluster-ubuntu-hostinger`, format unchanged: `ARGOCD_APP_CLUSTER_TOKEN` in `scripts/plugins/argocd.sh`,
`cluster-secret.yaml.tmpl`, `bin/cluster-up`, `bin/cluster-preflight`. The secret format (`bearerToken`,
`tlsClientConfig.caData`, `insecure`) does not change.

## Acceptance

```yaml
must:
  M1: every app-cluster kubectl call from app-cve-scan.sh and cve-remediation-verify.sh passes --kubeconfig <file> and nothing else for server, token or TLS
  M2: the kubeconfig holds exactly one cluster, one user, one context joining them, and current-context naming that context; the cluster carries the secret's server plus insecure-skip-tls-verify true, certificate-authority-data equal to the secret's caData, or neither, matching the secret; the user carries the secret's token
  M3: the kubeconfig file is mode 0600 inside a mode-0700 directory created by mktemp -d under APP_KUBECONFIG_TMPDIR; the umask change is confined to a subshell (the script's umask after the write equals its umask before)
  M4: the kubeconfig directory is gone after each script exits, on success, on failure and on TERM; on INT or TERM the script exits non-zero instead of carrying on
  M5: both CronJob pods mount an emptyDir with medium Memory at /kubeconfig-tmp and set APP_KUBECONFIG_TMPDIR=/kubeconfig-tmp
  M6: existing behaviour is kept: every existing app_cve_scan.bats, app_cve_scan_pins.bats and cve_remediation_verify.bats test passes, with only the kubectl stub's flag skipping and the fixture list extended
must_not:
  N1: the bearer token appears in any kubectl argv either script produces, for the insecure, CA and plain secret shapes
  N2: the token appears in the argv of any external command either script runs while loading access and writing the kubeconfig
  N3: a kubeconfig is written, or kubectl is run, when the secret's server, token or caData holds a character outside [A-Za-z0-9._~+/=:-]
evidence:
  - {id: E1, proves: [M1, N1], kind: offline, intent: "You will see tests run the CVE scan and the verifier against a fake kubectl that logs every call, for a secret with a CA, one marked insecure and a plain one, and find --kubeconfig in every app-cluster call and the token string in none.", command: "bats scripts/tests/plugins/app_cve_scan.bats scripts/tests/plugins/cve_remediation_verify.bats", red: "today's tree: the token appears after --token in the log, so the new N1 checks fail for all three shapes"}
  - {id: E2, proves: [M2], kind: offline, intent: "You will see the fake kubectl copy the kubeconfig it was handed, and a check find one cluster, one user, one context, current-context set to it, the secret's server and token, and the right TLS line for each of the three secret shapes.", command: "same run", red: "drop the current-context line, or write insecure-skip-tls-verify for the CA shape: the shape check fails"}
  - {id: E3, proves: [M3], kind: offline, intent: "You will see the file's mode read as 600 and its directory's as 700 with find -perm (works on macOS and Linux), and the script's umask compared before and after the write.", command: "same run", red: "write the file without umask 077, or set umask 077 outside a subshell: the mode or umask check fails"}
  - {id: E4, proves: [M4], kind: offline, intent: "You will see the kubeconfig directory checked after a run that succeeds, one where the fake kubectl fails, and one where the fake kubectl sends the script TERM; it is gone every time and the TERM run exits non-zero.", command: "same run", red: "drop the trap in cve-remediation-verify.sh: the directory survives; make the TERM trap only clean up: the run continues and exits 0"}
  - {id: E5, proves: [N2], kind: offline, intent: "You will see the tests put logging wrappers in front of every external command the scripts call (base64, sed, mktemp, cat, rm, head, tr, grep and the rest found by the worker), record every argument list, and find the token in none of them.", command: "same run, with the wrapper directory first on PATH", red: "write the kubeconfig with /usr/bin/printf or pass the token to sed on the command line: the wrapper log contains the token"}
  - {id: E6, proves: [N3], kind: offline, intent: "You will see a secret whose token contains a double quote and one whose server contains a newline each make the loader log a malformed-secret error, return non-zero, leave no kubeconfig and make no app-cluster kubectl call.", command: "same run", red: "today's tree has no check: kubectl is called with the bad value"}
  - {id: E7, proves: [M5], kind: offline, intent: "You will see a check read both CronJob pod specs and find the memory emptyDir at /kubeconfig-tmp and the APP_KUBECONFIG_TMPDIR variable in each container.", command: "yq checks on scripts/etc/argocd/platform-ops/app-cve-scan-cronjob.yaml in the bats suite; make validate-manifests", red: "today's manifest has neither"}
  - {id: E8, proves: [M6], kind: offline, intent: "You will see the whole existing CVE-scan, pin and verifier suites pass, with only the fake kubectl's flag skipping and the fixtures extended.", command: "bats scripts/tests/plugins/app_cve_scan.bats scripts/tests/plugins/app_cve_scan_pins.bats scripts/tests/plugins/cve_remediation_verify.bats; git diff of the .bats files shows only the stub's case line, fixtures and new tests", red: "regression guard: break _app_kubectl's argument passing and the existing report tests fail"}
  - {id: E9, proves: [M1, M2, N1], kind: live, intent: "You will see Claude, after a hub promote, read the next app-cve-scan job's log and one cve-remediation-verify job's log on the hub (read-only), find the scan listing VulnerabilityReports from the app cluster as before, and find the app cluster's server (not the hub's) in a verify job's kubectl output.", command: "on m5-air: kubectl --context k3d-k3d-cluster -n platform-ops logs job/<latest app-cve-scan> | tail; same for job/<latest cve-remediation-verify>", red: "n/a (live)"}
interface:
  - "app-cve-scan.sh: _app_kubectl <kubectl args> unchanged; _load_app_cluster_access unchanged signature"
  - "cve-remediation-verify.sh: _app <kubectl args> unchanged; _load_access unchanged signature (now also installs the trap)"
  - "new env var APP_KUBECONFIG_TMPDIR (both scripts), default ${TMPDIR:-/tmp}"
```

## Files

| File | Change |
|---|---|
| `scripts/etc/argocd/platform-ops/app-cve-scan.sh` | kubeconfig in `_load_app_cluster_access`, `_app_kubectl`, `_cleanup`; value check; three-trap form |
| `scripts/etc/argocd/platform-ops/cve-remediation-verify.sh` | kubeconfig in `_load_access` (with the trap), `_app`; value check |
| `scripts/etc/argocd/platform-ops/app-cve-scan-cronjob.yaml` | `/kubeconfig-tmp` memory emptyDir (`sizeLimit: 1Mi`) and `APP_KUBECONFIG_TMPDIR` in both pods |
| `scripts/tests/plugins/app_cve_scan.bats` | stub skips `--kubeconfig` and captures the file; CA and plain fixtures; argv wrappers; E1-E7 tests |
| `scripts/tests/plugins/cve_remediation_verify.bats` | E1-E6 tests, calling `_load_access` in a subshell only |

## Routing

Luna: 2 script files of shell logic, 1 manifest, 2 test files. Not Flash (logic and tests).

## Worker definition of done

- Change only the files in the table. Offline only: stub kubectl on PATH; no cluster, no network, no Keychain.
- Every file the tests write lives under `$BATS_TEST_TMPDIR` (set `APP_KUBECONFIG_TMPDIR` there); assert that first.
- Show the new N1, N2 and N3 tests red on today's tree, then green. Mutations: put `--token` back in each of the three
  branches in turn; drop `current-context`; move the verifier's trap to top level (the BATS run must break or the test
  must catch it); show a test goes red each time.
- Mode checks use `find <path> -prune -perm 600` (and `700` for the directory), not `stat`, which differs between macOS
  and Linux.
- `shellcheck -s sh` on both scripts; `make validate-manifests`; the full `bats` run of the three suites with rc and
  counts.
- Leave changes uncommitted; no push; E9 belongs to Claude; do not touch `docs/bugs/`.

## Residuals

- The token still lives in the scripts' shell memory and, briefly, in the memory-backed file. Anyone who can exec into
  the job pod as its uid can read either; that is the same trust boundary as the mounted ServiceAccount token.
- Insecure TLS stays wherever `bin/cluster-refresh` writes it (Fix 6).
