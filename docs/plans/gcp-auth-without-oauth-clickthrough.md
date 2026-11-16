# GCP provider 1/4 — authenticate gcloud from the sandbox service account; the OAuth robot fails closed

**Status:** PLANNED — ordered backlog (unnumbered); first of the four GCP provider plans
**Approval:** operator, 2026-11-12 ("let's get GCP provider plans into roadmap")
**Intent approved:** pending
**Branch:** unassigned (release chosen at grooming)
**Dispatch precondition (live probe, operator + a GCP sandbox):** before the spec gets Acceptance, run in a fresh ACG
GCP sandbox, with the SA JSON that `providers/gcp.js` writes to `~/.local/share/k3d-manager/gcp-service-account.json`:
`CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE=<that file> gcloud compute zones list --project="$GCP_PROJECT"` and
`... gcloud compute instances list`, then `gcloud auth list` (must still show the operator's own account, unchanged).
Record host, date and `gcloud --version` here. Per the "prove external behaviour" rule this is the proof; until it
exists the SA's Compute rights are **UNCONFIRMED** (Fable review, 2026-11-12).
**Probe result (m4-air.local, 2026-11-13T00:55Z and retry 00:57Z, Google Cloud SDK 565.0.0, sandbox project
playground-s-11-bdff1cbe):** the override works (gcloud: "authenticated as cli-service-account-1@... using the credentials in
...gcp-service-account.json, specified by the [auth/credential_file_override] property"; a token was issued), and
`gcloud auth list` was identical before and after (active account unchanged). The SA has **no Compute rights**:
`compute.zones.list` and `compute.instances.list` denied, unchanged after 2 min; `projects get-iam-policy` and
`services list` also denied (Cloud Resource Manager API disabled). **Primary path fails; the fallback (step 3) is the
plan.** Side finding: `gcloud auth list` on m4-air holds five stale `cloud_user_p_*@linuxacademygclabs.com` accounts from
past robot logins; cleanup belongs in plan 4 (lifecycle). Probe lesson: check the key's `project_id` matches the
sandbox before running (a July key gave a misleading `invalid_grant: account not found`).
**cloud_user probe (operator, m4-air.local, 2026-11-13 ~01:10Z):** `gcloud compute zones list --account=cloud_user_p_e76bc7a9@linuxacademygclabs.com
--project=playground-s-11-bdff1cbe --limit 2` listed us-east1-b and us-east1-c (UP): the browser-login identity has Compute
rights. Direction (Claude, 2026-11-13): robot login per sandbox into an isolated `CLOUDSDK_CONFIG` under
`~/.local/share/k3d-manager/`, every k3s-gcp gcloud call pointed at it, removed on sandbox down; the operator's own gcloud
store is never written. Role of cloud_user (Owner or not, for an SA-grant hybrid) not yet read.
**Related:** Fable and Argon GCP reviews 2026-11-12 (synthesis in `memory-bank/activeContext.md`);
`docs/bugs/v1.1.0-recovery-phase-c-gcp-identity.md` (why global `activate-service-account` is banned)

## Goal

`make up CLUSTER_PROVIDER=k3s-gcp` authenticates gcloud without a browser. Today `gcp_login` drives
`gcloud auth login` through a Playwright robot (`scripts/lib/foundation/scripts/lib/acg/playwright/gcp_login.js`),
a single linear pass over Google's sign-in screens. A screen it misses is skipped silently, and a timeout on the
`localhost` redirect logs "assuming OAuth completed" and exits 0 while gcloud is still waiting.

## Scope

1. **Primary path (if the probe passes):** every gcloud call in `k3s-gcp.sh` and `gcp.sh` runs with
   `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE` set to the SA JSON, per process. Nothing writes to the gcloud credential
   store, and nothing runs `gcloud auth activate-service-account` or `revoke --all`.
2. **The robot fails closed (both paths):** `gcp.sh:242-244` checks `_gcp_perform_login_auth`'s rc before printing
   Authenticated; `gcp_login.js` exits non-zero when the `localhost` redirect is not reached; `gcp.sh:189` passes
   `GCP_PASSWORD` explicitly; `_browser_launch` runs before the CDP check (`gcp.sh:74-79`), as on AWS.
3. **Fallback (if the probe fails):** replace the linear pass in `gcp_login.js:88-155` with a state-polling loop over
   account chooser (`[data-email]` and "Use another account"), email, password, Workspace ToS, managed-profile notice,
   and the one- or two-step SDK consent (`Continue` then `Allow`); unknown screen → fail with a screenshot path.

## Out of scope

SSH, tunnel, cluster-up steps 5–12, lifecycle (plans 2–4).

## Files

lib-foundation first (`scripts/lib/acg/gcp.sh`, `scripts/lib/acg/playwright/gcp_login.js`, its tests), then a
subtree pull; k3d-manager `scripts/lib/providers/k3s-gcp.sh`, `scripts/tests/plugins/gcp.bats`.

## Live evidence (when specced)

A fresh sandbox `gcp_get_credentials` followed by `gcloud compute zones list --project="$GCP_PROJECT"` succeeding,
and `gcloud auth list` byte-identical before and after.
