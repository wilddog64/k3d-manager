# Bug: app-cluster bearer token passed in kubectl argv by the CVE scan and verifier

**Status:** OPEN — captured 2026-11-23
**Priority:** P2
**Introduced by:** pre-existing in `cve-remediation-verify.sh:9-11` (not in the v1.45.0 diff); `app-cve-scan.sh:149-160` unknown (file rewritten in plan 2e)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unavailable: cluster context missing); grep of docs/bugs for the key terms found no match
**Detected by:** v1.45.0 red-team gate, 2026-11-22, on `7dfb7238` — see [docs/issues/2026-11-23-v1.45.0-red-team.md](../issues/2026-11-23-v1.45.0-red-team.md)
**Severity:** breaks the repository rule "no tokens in arguments"; visible in the process list inside the job pod or on its node.
**Findings:** Astra 5 (Medium), Fable 11 (Low). Claude: confirmed, P2.

## What is wrong

`scripts/etc/argocd/platform-ops/app-cve-scan.sh:149-160` (`_app_kubectl`) and `cve-remediation-verify.sh:9-11` (`_app`) run
`kubectl --server ... --token "$TOKEN"`. Both also honour `--insecure-skip-tls-verify=true` when the cluster secret says so.

## Fix direction

Write a 0600 kubeconfig in the job's tmpfs and pass `--kubeconfig`; refuse the insecure branch outside dev.
