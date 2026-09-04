# Promoter cosign-verify gate — refuse to promote unsigned candidates

**Date:** 2026-08-31
**Branch:** `k3d-manager-v1.27.0`
**Milestone:** v1.27.0 Image-signing — CVE-loop closure (Stage D deferral #1)
**Plan:** `docs/plans/v1.27.0-image-signing-cve-loop-closure.md` (Part 4 — "Verify at promotion")

## Problem

Kyverno `verify-first-party-images` is **Enforce** live on hostinger — an unsigned
first-party image is rejected at admission. But the **git-persisted CVE promoter**
(`scripts/etc/argocd/platform-ops/app-cve-scan.sh`, Hub CronJob `app-cve-scan`) still
selects and pins a "clean" `sha-*` candidate digest into the ArgoCD Application **without
checking the signature**. If a candidate is unsigned (legacy image, a build where CI signing
failed — cf. the Stage C RC1/RC2 unsigned-post-merge incident), the promoter happily pins it,
then Argo tries to deploy it and **Kyverno blocks the pod** — a promotion that dead-ends at
admission with no signal at the promotion step. The loop is not closed at the promotion latch:
"signed by our key" is not yet a precondition for **promotion**, only for **admission**.

## Fix (this slice — signature-only, Hub promoter)

Make `cosign verify --key <our pub>` a hard precondition inside the promoter, on the exact
candidate digest, **before** the `kubectl patch application`. An unverifiable candidate is not
a promotable candidate: skip it, notify, move on (fail-closed). Mirror Kyverno's verify stance
exactly (key-based, `--insecure-ignore-tlog=true`, matching the ClusterPolicy's
`rekor.ignoreTlog: true`) so the promoter and the admission gate agree on what "signed" means.

Attestation verify (`verify-attestation --type vuln`) is **deferred** — it depends on CI
`cosign attest` (cross-repo, separate slice). Signature-only closes the immediate gap.

## Targets (k3d-manager only — no cross-repo)

1. `scripts/etc/argocd/platform-ops/app-cve-scan.sh` — add cosign install + verify + gate.
2. `scripts/etc/argocd/platform-ops/app-cve-scan-cronjob.yaml` — env + mount the pub key.
3. `scripts/etc/argocd/platform-ops/cosign-pub-externalsecret.yaml` — **new**; ESO projects
   `cosign.pub` from Hub Vault `cosign/signing` into `platform-ops/cosign-public-key`.
4. `scripts/plugins/argocd.sh` — apply the new ExternalSecret in the platform-ops deploy path.
5. `scripts/tests/plugins/app_cve_scan.bats` — cosign stub + two gate tests.

## Design

### app-cve-scan.sh (POSIX `/bin/sh`, `set -eu` — no bashisms)

New config (top, with the other `${VAR:-default}` block):

```sh
COSIGN_VERIFY="${COSIGN_VERIFY:-0}"
COSIGN_VERSION="${COSIGN_VERSION:-v2.4.1}"
COSIGN_PUBLIC_KEY_FILE="${COSIGN_PUBLIC_KEY_FILE:-/cosign/cosign.pub}"
COSIGN_VERIFY_FLAGS="${COSIGN_VERIFY_FLAGS:---insecure-ignore-tlog=true}"
_COSIGN_BIN="${COSIGN_BIN:-}"
_COSIGN_DOCKER_CONFIG=""
```

- `COSIGN_VERIFY=0` default keeps every existing invocation (and the current BATS suite)
  unchanged; the CronJob sets it to `1`.
- `v2.4.1` matches the cosign the CI `cosign-installer@v3.7.0` signs with.
- `--insecure-ignore-tlog=true` mirrors the ClusterPolicy's `rekor.ignoreTlog: true`.

`_ensure_cosign` — same pattern as `_ensure_kubectl` (prefer `command -v cosign`, else wget the
pinned static binary to `/tmp/cosign`). Preferring PATH lets the BATS stub resolve.

`_cosign_registry_auth` — best-effort: when `GH_TOKEN` is set, write a throwaway
`DOCKER_CONFIG/config.json` with the ghcr basic-auth entry (`GH_OWNER:GH_TOKEN`, same creds as
`_ghcr_bearer_token`) so cosign's keychain can pull the private manifest/signature. No token in
argv.

`_verify_candidate_signature <repo> <digest>` — `_ensure_cosign`; require a non-empty
`COSIGN_PUBLIC_KEY_FILE` (else return 1 = fail-closed); `_cosign_registry_auth`; run
`cosign verify --key "${COSIGN_PUBLIC_KEY_FILE}" ${COSIGN_VERIFY_FLAGS} "${repo}@${digest}"`
with `DOCKER_CONFIG` exported; the cosign exit code **is** the gate.

Gate in MAIN, clean-candidate branch, immediately before `_promote_image`:

```sh
    if [ "${COSIGN_VERIFY}" = "1" ]; then
      if _verify_candidate_signature "${_repo}" "${_candidate_digest}"; then
        _log "SIGGATE ${_svc}: candidate ${_candidate_image}@${_candidate_digest} cosign-verified"
      else
        _log "SIGGATE ${_svc}: candidate ${_candidate_image}@${_candidate_digest} FAILED cosign verify — refusing to promote unsigned/unverified image"
        _notify warning \
          "App CVE Promotion Blocked (unsigned): ${_svc}" \
          "Clean candidate ${_candidate_image}@${_candidate_digest} is not verifiable by the k3d-manager cosign key; promotion refused."
        continue
      fi
    fi
    _promote_image ...
```

Fail-closed rationale: a missing key or a verify failure blocks *promotion* only. Admission is
already guarded by Kyverno Enforce, so nothing unsafe ships; auto-remediation just pauses (and
is loudly logged + notified) until the signature/ESO is healthy.

### app-cve-scan-cronjob.yaml

- env: `COSIGN_VERIFY=1`, `COSIGN_VERSION=v2.4.1`, `COSIGN_PUBLIC_KEY_FILE=/cosign/cosign.pub`.
- volumeMount `cosign-pub` → `/cosign` (readOnly).
- volume `cosign-pub` → `secret: { secretName: cosign-public-key, optional: true }`
  (`optional` so the Job still starts before ESO first-sync; empty mount → key missing →
  fail-closed skip, which is correct).

### cosign-pub-externalsecret.yaml (new)

ESO `ExternalSecret` in `platform-ops`, `vault-backend` ClusterSecretStore,
`remoteRef key: cosign/signing property: cosign.pub` → target Secret `cosign-public-key`.
Mirrors `grafana-admin-externalsecret.yaml` + `etc/signing/externalsecret-cosign-pub.yaml.tmpl`.

### argocd.sh

Add `_kubectl apply -f "${_dir}/cosign-pub-externalsecret.yaml"` right after the
`app-cve-scan-cronjob.yaml` apply (before the scan-script ConfigMap).

### app_cve_scan.bats

- Add a `cosign` stub (log args to `COSIGN_LOG`; exit `${TEST_COSIGN_EXIT:-0}`).
- New test: **signed candidate promotes** — `COSIGN_VERIFY=1`, dummy pub file,
  `TEST_COSIGN_EXIT=0` → PROMOTION patch happens, `cosign verify --key` logged.
- New test: **unsigned candidate blocked** — `COSIGN_VERIFY=1`, `TEST_COSIGN_EXIT=1` →
  NO `patch application`, `App CVE Promotion Blocked (unsigned)` notified.
- Existing promotion tests leave `COSIGN_VERIFY` unset (gate off) → stay green.

## Rules

- POSIX sh only (script runs in `aquasec/trivy` BusyBox); no bashisms.
- No secret in argv (GH_TOKEN → DOCKER_CONFIG file; key via file path).
- `shellcheck -s sh scripts/etc/argocd/platform-ops/app-cve-scan.sh` clean.
- `bats scripts/tests/plugins/app_cve_scan.bats` green (existing + 2 new).
- Pin cosign version (A08) and chart/image tags — no floating latest.

## Definition of Done

- [ ] app-cve-scan.sh: `_ensure_cosign` + `_cosign_registry_auth` + `_verify_candidate_signature` + MAIN gate.
- [ ] CronJob: cosign env + pub-key mount (optional secret).
- [ ] New ExternalSecret manifest + argocd.sh apply wired.
- [ ] BATS: cosign stub + 2 gate tests; full suite green.
- [ ] shellcheck clean.
- [ ] Commit `feat(signing): promoter cosign-verify gate — refuse unsigned CVE-promotion candidates`, push origin.
- [ ] memory-bank updated (progress.md deferral #1 done, activeContext.md).

## Deferred (follow-up slices, tracked in progress.md)

- **CI `cosign attest`** (vuln + SBOM predicates) in shopping-cart-infra reusable
  `build-push-deploy.yml` + callers — cross-repo, Codex. Then extend this gate with
  `cosign verify-attestation --type vuln`.
- **Codify app-cluster Vault seed/grant + kyverno-ns ghcr imagePullSecret ES into signing.sh**
  (hostinger hand-run steps).
