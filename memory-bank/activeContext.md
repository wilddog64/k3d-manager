# 2026-09-26 — vectordb seed verified independently; ApplicationSets reapplied

Codex `10dcd995` + `869accfd` on `origin/k3d-manager-v1.39.0`. Verified by Claude on a
quiescent tree, NOT taken from the report: scope is exactly the six spec'd files (133
insertions), bats 16/16, shellcheck at the 7-line/SC2317 baseline, and a credential sweep
found zero 20+ char literals in added lines — every `password` occurrence is a field name,
a doc sentence, or the in-pod generator.

All six new gates were mutation-proved one at a time with a byte-equality restore between
each. Gates 12 (call site), 14 (argv), 15 (urandom) each go red uniquely for their own
mutation; none was incapable of failing.

**Process failure worth remembering: I verified a tree while Codex was still writing it.**
The background task reported "completed, exit code 0" but `codex exec` (PID 45118) was
still alive and editing. My sed mutation tests raced its edits, so results were incoherent
— gate 14 red under a mutation that could not affect it, a regex returning rc=1 standing
alone while bats called it green, and three different versions of gate 14 across three
reads. I also asserted a defect ("Codex added the comment but not the call") from a
truncated diff render; grep showed the call was present all along. Rule: confirm the writer
has exited (`pgrep -x codex`, check the PID) before verifying, and grep the file before
claiming a missing line.

ApplicationSets reapplied by the operator: 13/13 (was 12 — `vectordb.yaml` is now in the
set), all Applications on `k3d-manager-v1.39.0`. The three stale v1.37.0 pins
(`acg-kube-prometheus-stack`, `acg-trivy-operator`, `loki`) are cleared.

`hub-vectordb` still `OutOfSync / Healthy` with only the ExternalSecret out of sync, even
though `ServerSideDiff=true` is now present on the live Application (confirmed by reading
the annotation back). The residual diff is pure CRD defaulting — `conversionStrategy`,
`decodingStrategy`, `metadataPolicy`, `deletionPolicy: Retain`, `template.engineVersion: v2`,
`mergePolicy: Replace`, `metadata: {}` — none of which is in git. ServerSideDiff should
absorb exactly this, so the annotation alone was necessary but not sufficient: the
controller still needs to re-diff under SSA and take field ownership. A hard refresh is
the next step and is the operator's to run. My earlier "missing annotation" diagnosis was
therefore incomplete, not wrong.

# 2026-09-26 — vectordb is UP; policy overwrite proven safe by diff

The ESO grant is live and `vectordb` runs. Sequence: operator overwrote the Vault policy
`eso-ldap-directory` with the 5-prefix HCL the repo's builder emits; the ExternalSecret flipped
`SecretSyncedError` -> `SecretSynced` at 06:27:04 (~6 min, one ESO retry cycle); kubelet then
created the container and `vectordb-0` reached `Running 1/1`; StatefulSet 1/1.

No role rewrite was needed — the role already carries `eso-ldap-directory` in `token_policies`
by name, and Vault evaluates the policy body per request. So a policy overwrite takes effect on
the next ESO attempt with no restart and no force-sync annotation (which self-heal would revert).

HOW THE OVERWRITE WAS DE-RISKED, and the general method. Claude cannot read a live Vault policy
(that needs the root token), so it could not rule out that an overwrite would revoke a prefix
merged in out of band — a real risk, since a role rewrite dropping a grant is already a filed
bug. Resolution was not to guess and not to reach for the additive path by default: the operator
ran `vault policy read eso-ldap-directory`, and the output was diffed against the generated HCL.
`diff` returned empty on the first 16 lines, proving the change strictly additive (4 new
`vectordb` lines, nothing else touched). Only then was the overwrite recommended. The additive
`eso-vectordb` policy stays the fallback for when that diff is NOT clean — it cannot revoke, but
it leaves a second policy `deploy_ldap` does not know about.

REMAINING, and it is the committed-but-inert trap again: `hub-vectordb` is `OutOfSync / Healthy`.
PVC, Service and StatefulSet are all Synced; only the ExternalSecret is OutOfSync, because the
live Application carries no `argocd.argoproj.io/compare-options` annotation. `d44ef5cd` added it
to the ApplicationSet template, but the sets have not been reapplied, so nothing in the cluster
reads it. Same class as the `vars.sh` inertness above and the values-branch pin.

CORRECTION — the ArgoCD namespace on this hub is `cicd`, not `argocd` (`ARGOCD_NAMESPACE:-cicd`,
`argocd.sh:1270`). An earlier read reported "No resources found in argocd namespace" for all
three contexts; that namespace does not exist, so the output proved nothing. `kubectl` prints
"No resources found in X namespace" for a missing namespace on a plural/multi-resource get and
only errors with NotFound on a named get — so the empty reading looked like a valid answer.
Never read an empty kubectl listing as evidence without confirming the namespace exists.

# 2026-09-26 — vectordb blocker was the ESO Vault policy, not the missing path

The Vault path `secret/vectordb/postgres` is now written (operator, version 1, 13:03Z,
`username: postgres`, password generated inside the vault pod so it never reached the host,
argv or shell history). The pod did NOT come up, and the reason was already true before the
write: the ESO role is denied that path.

Proven from the ESO controller log:
`Code: 403 ... permission denied` on `GET /v1/secret/data/vectordb/postgres`, repeating every
~7 minutes, including before the write.

`LDAP_VAULT_POLICY_PREFIX` (`scripts/etc/ldap/vars.sh:79`) listed
`ldap,keycloak,observability,platform-ops` — no `vectordb`. `VAULT_ESO_APPS_PREFIXES`
(`vault.sh:2130`) does not cover it either. Fixed in `04fafc55` by adding `vectordb`, with a
mutation-checked gate tying the grant to the manifest. Third occurrence of the class first filed
for keycloak in v1.4.5; recorded on that doc.

CORRECTION recorded against my own earlier report: the `SecretSyncedError` was reported as "the
Vault path does not exist yet" and the write as the single remaining blocker. Both wrong. The
ExternalSecret condition message `could not get secret data from provider` is identical for an
absent path and a denied one, and it is the only thing `kubectl get externalsecret` shows.

LESSON — when a secret will not sync, read the ESO controller log, never the ExternalSecret
condition: `kubectl -n secrets logs deploy/external-secrets --tail=300 | grep <name>`.
403 = policy prefix missing (this bug). 404 = path genuinely absent. The condition cannot
distinguish them.

STILL OPEN — the live grant is unchanged. `vars.sh` is inert until
`_vault_configure_secret_reader_role` runs again (via `deploy_ldap`, `ldap.sh:1136`), the same
inertness as the ApplicationSet values pin. Claude cannot verify the live policy's current
contents, because that needs the Vault root token, which Claude does not read — so whether the
policy can be safely overwritten has to be decided from an operator-run
`vault policy read eso-ldap-directory`. Generated the exact 5-prefix HCL the repo's builder
would emit, in the session scratchpad, for that comparison.

Also open, unchanged: the `ServerSideDiff` annotation (`d44ef5cd`) needs an ApplicationSet
reapply before it reaches the live Application.

# 2026-09-26 — WS1 live: vectordb deployed, one blocker left (Vault path)

`deploy_argocd_bootstrap --skip-applicationsets` (operator-run) applied the updated `platform`
AppProject: destinations 42 -> 43, `vectordb` permitted. The `InvalidSpecError` on `hub-vectordb`
was a cached condition and cleared on its own after ~85s, at 22:56:05 — it was not a second
failure. The app then auto-synced and every manifest landed: StatefulSet `vectordb` (0/1),
Service `vectordb` (ClusterIP 5432), PVC `vectordb-data` (Bound, 10Gi, `local-path`),
ExternalSecret `vectordb-postgres`.

Two states remain, and only the first is a blocker:

1. `pod/vectordb-0` is `CreateContainerConfigError` and `vectordb-postgres` is
   `SecretSyncedError` ("could not get secret data from provider"). This is the expected
   state: the Vault path `vectordb/postgres` does not exist yet. Writing it (`username`,
   `password`) is the operator's step — Claude must not create, generate, echo or log that
   value.
2. `hub-vectordb` was perpetually `OutOfSync` on the ExternalSecret alone. Root-caused and
   fixed in `d44ef5cd`: the Application template was missing
   `argocd.argoproj.io/compare-options: ServerSideDiff=true`. Recurrence of the bug already
   filed 2026-09-13 for `platform-ops`; recorded on that existing doc, not a new one.
   **The fix is inert until the ApplicationSets are reapplied** — the live ApplicationSet still
   carries the old template.

LESSON — check `docs/bugs/` for the symptom before diagnosing it. This exact failure was
already filed and fixed for `platform-ops` on 2026-09-13, with the annotation named as the fix.
Several rounds of live diffing, field-ownership comparison and one refuted experiment
(`afed4ec9`, reverted) went into re-deriving it. The dedup check that the docs conventions
require before *filing* would have found it just as well when run before *investigating*.

LESSON — `kubectl get -o json` strips `managedFields` by default (kubectl >= 1.21). An empty
`managedFields` is not an anomaly; it needs `--show-managed-fields`.

LESSON — latent exposure: `observability.yaml` and `data-git.yaml` also lack the annotation.
Neither shows the symptom today because their ExternalSecrets are on `ubuntu-hostinger`, but any
ESO resource added to them will drift identically. Three sets have now needed this annotation
one at a time; making it part of the ApplicationSet template convention is the durable fix.

# 2026-09-26 — WS1 pgvector hub platform component implemented

Implemented WS1 from `docs/plans/v1.39.0-vector-store-platform-and-retrieval.md` on
`k3d-manager-v1.39.0` in commit `5cf1700d` (PR not created by instruction). Added a hub-scoped
plain-manifest ApplicationSet and single-instance pgvector StatefulSet, Service, local-path-default
PVC, and ESO ExternalSecret in namespace `vectordb`. The image is pinned to `pg17`; credentials are
secretKeyRef-only from `vault-backend` / `vectordb/postgres`; no RBAC objects or credential values
were added. No cluster, Vault, Helm, kubectl, or deployment command was run. Focused BATS is 6/6,
PyYAML parses all five YAML files, `make check-doc-links` is green, shellcheck and `_agent_audit`
are clean. Mutation checks for all six tests went red on the intended broken assertion and were
restored. Push remains the final handoff step.

# 2026-09-26 — ArgoCD values-branch gate fix dispatched to Codex

Implemented M1–M4 from `docs/bugs/2026-09-26-check-values-branch-false-clean-under-dry-run.md` on
`k3d-manager-v1.39.0`: detector outcomes are distinct and fail closed, dry-run confirmation is
skipped, and the gate checks all k3d-manager manifest references while excluding/counting `HEAD`.
Focused BATS is green at 11/11; `argocd.bats` and final shellcheck are pending the final gate run.
Mutation checks for all six new tests were red when their covered change was reverted and were
restored. Commit SHA: `b1f90fce`; no PR created.

# Active Context — k3d-manager

## 2026-09-26 — ApplicationSets reapplied, values pin now v1.39.0 (Claude + operator)

**The required per-release ApplicationSet reapply is DONE.** The operator ran it directly after
the `!` relay proved to be executing nothing (three invocations, zero side effects — a `>`
redirect target was never even created, which is how we knew the command was not running rather
than failing).

**First attempt applied to the dead ACG sandbox.** `deploy_argocd_applicationsets` takes no
context flag and inherits whatever `kubectl` points at; the current context was the stale
`ubuntu-k3s`, i.e. the expired sandbox at 44.250.167.86. Every set failed at kubectl's *openapi
validation* step (before any write, so nothing was mutated) at ~90s per set. Aborted, switched
to `k3d-k3d-cluster`, re-ran clean. **Lesson: check `kubectl config current-context` before any
release step that does not take an explicit context.** The stale `ubuntu-k3s` context is still
present and is now overdue for deletion — it has cost ~90s per query for weeks and has now cost
a release step.

Result on the hub (`k3d-k3d-cluster`, ns `cicd`): **12/12 ApplicationSets deployed**, both ACG
variants included (`grafana-dashboards-acg`, `observability-acg`). All **24** k3d-manager sources
moved off `k3d-manager-v1.37.0` to `k3d-manager-v1.39.0` — the 6 with `ref: values` and the 18
with no `ref`, which the gate never inspects but which are templated from the same
`${K3D_MANAGER_BRANCH}`. The 2 remaining at `HEAD` are the rollout demo and are intended.
`istio-ambient` resolved the k3s CNI dirs correctly (`/var/lib/rancher/k3s/...`), so the open
`_argocd_appset_live_overrides` istio-cni bug did **not** fire — no sixth observation.

**The values-branch gate confirmed clean, and this one is trustworthy** — it printed
`checked 6 values references`. Note the first check, run seconds after the apply, still showed 3
of 6 stale (`acg-kube-prometheus-stack`, `acg-trivy-operator`, `loki`): the sets are updated
synchronously but the child Applications are regenerated on the controller's own loop. **A
partial split immediately after a reapply is reconcile lag, not failure** — re-check before
escalating.

Correction to the record: an earlier note in this file claimed the pre-denial dump showed 26
Applications and that no `identity` app existed. Both wrong — `apps.json` had **38**, including
`shopping-cart-identity`. The miscount was mine; nothing changed in-cluster.

## 2026-09-26 — identity sync NOT attempted: deterministic failure, already filed (Claude)

The second authorized item (sync `shopping-cart-identity`) was **deliberately not run.** It fails
deterministically and a sync is not the remedy. `syncOptions: ["CreateNamespace=true",
"Replace=true"]` makes ArgoCD `kubectl replace` the bound `postgres-keycloak-pvc`, whose spec is
immutable except `resources.requests`; the git manifest legitimately omits `volumeName` and
`storageClassName`, so the replacement blanks them and the API server rejects it. Retry limit 5,
exhausted, `operationState.phase: Failed` — which also blocks self-heal. Held back with it: 3
ExternalSecrets `OutOfSync` and `Job/keycloak-realm-reconcile` never created.

Already filed as `docs/bugs/2026-09-23-argocd-identity-replace-true-cannot-update-bound-pvc.md`
(the dedup check caught it — no second file created). Appended a 2026-09-26 update that
**disproves that doc's own open question**: the `keycloak-realm-reconcile` failure is *not*
caused by the sync failure. Its pods die on `awk: command not found` — the `ubi9-micro` image has
no `awk`. **Two independent fixes are required**, and the PVC one must land first or the awk fix
cannot be observed, because the Job is currently never created at all.

## 2026-09-26 — both live release items blocked by the classifier (Claude) — SUPERSEDED, see above

The operator gave the go for the ApplicationSet reapply and the `shopping-cart-identity` sync.
**Neither could be done: the auto-mode classifier denied both, and per standing rule denials
are not worked around.** `deploy_argocd_applicationsets --confirm` was refused as
`Protected-Scope IaC Apply`; a *read-only* `kubectl get application` was then refused with no
explanation, so there is no live cluster access in this session at all. Both need the operator
running them via `!`.

**v1.38.0 config is inert in-cluster as of now.** 24 k3d-manager sources on the hub are pinned
at `k3d-manager-v1.37.0`. The pin to use is `k3d-manager-v1.39.0` — the current release branch,
cut from the v1.38.0 merge commit, so it already contains every v1.38.0 change; pinning to
`v1.38.0` would freeze the sets to a branch that stops receiving commits and would need redoing
at once.

**The release step's own gate cannot be trusted under `--dry-run`.** It reported "All
Applications reference values branch k3d-manager-v1.39.0" while none did — an unparseable-input
exit is indistinguishable from no-drift because only stdout is consulted. Filed in
`docs/bugs/2026-09-26-check-values-branch-false-clean-under-dry-run.md`. It was caught only
because the live pins had been measured *before* the dry run, so the claim contradicted a
number already in hand. **Measure the baseline before running a release step**, or a false
clean reads as a successful no-op.

## 2026-09-26 — v1.38.0 shipped; protection restored; v1.39.0 open (Claude)

`/post-merge` ran in the main session rather than the Haiku subagent the skill prescribes:
two of its steps are not mechanical — publishing a tag and a GitHub release is outward-facing,
and the release-scope split is the operator's decision — and `enforce_admins` follows the
`/create-pr` precedent of Claude running protection changes directly.

**PR #132 merged `6f0fb4af`. `enforce_admins` is back ON, verified `enabled=true`.** The
bodyless POST is the only form that works; `-f enabled=true` returns HTTP 422. Tag `v1.38.0`
and the GitHub release are published and the release is marked latest.

Full protection on `main` now: `required_approving_review_count=1`, `enforce_admins=true`,
`required_status_checks.checks=[]`. **CI is not a merge gate on this repo** — worth remembering
before treating a green run as something that had to pass.

**A commit pushed after the PR went merge-ready missed the squash.** `875f97da` (queueing the
cloud-bridge architecture doc) is not in `main`; it is on `k3d-manager-v1.39.0` as `ed697ef3`
via cherry-pick. Once a PR is merge-ready the merge can land at any moment, so a further push
to that branch is a push into a closing window — put it on the next branch instead.

**Standing-doc audit found one real gap.** `.github/copilot-instructions.md` was already
current: all four v1.38.0 rules (header-may-only-narrow, cloud-requests-is-untrusted, the
allowlist-is-the-boundary, branch-scoped-workflows) landed inside the release. But
`memory-bank/projectbrief.md` still described scope as if no remote read surface existed, three
releases after the Slack `/k3dm` command and now the bridge — added. `docs/api/functions.md`
needs nothing: it documents plugin shell functions and v1.38.0 added Python bins only.

**Branch cleanup was not run.** It is due every 5 releases and v1.35.0 was the last multiple,
so v1.40.0 is next.

**Open for the operator: the v1.39.0 scope split.** v1.38.0 has 5 plan docs, exactly at the
cap, and four of them shipped as specs only — public-endpoint blackbox probes, the Hermes
app-health delta sensor, the Slack smoke target, and the vector-store prior art. v1.39.0
already has 2 of its own (`slack-corpus-qa`, `test-suite-metrics-and-staleness`), so carrying
all four forward makes 6. The cap exists to force the split, not to be rounded up.

## 2026-09-25 — PR #132 is open and mergeable by admin bypass (Claude)

`/create-pr` ran to completion. Pre-flight 0-2, 7 and 8 were run in the main session because
they can end in "ask the user"; 3-6 went to a Haiku subagent, which returned before CI
finished and had its CHANGELOG promotion, release rows and PR body verified independently
rather than trusted.

**Two things worth carrying forward from this run.**

*An automated reviewer can be right about the defect and wrong about the fix.* Copilot's
`mktemp -u` finding was a genuine symlink race, and its proposed remedy — create the file by
dropping `-u` — would have made `make init-cloud-requests` die at rc 128, because git refuses a
zero-byte index. That was caught only by actually running the suggestion in a scratch repo
before applying it. **Do not apply a review suggestion without executing it**, especially in a
target that runs once on a fresh setup where nobody is watching.

*A flagged occurrence is a sample, not a count.* Copilot flagged one `https://127.0.0.1:7443`;
grepping the class found three, two of them in the spec. One of those was wrong for a second,
different reason: a cloudflared ingress `service:` addresses the local origin, and Cloudflare
terminates TLS at its edge, so it would have been `http://` even had the push path been built.

**stage2 is skipped, and that is by design** — `ci.yml:145-152` gates it on the
`ci:cluster-tests` label. Asking for the job list rather than the run conclusion is what made
that visible; it is not a hidden gap, but the cluster tier genuinely did not run on this PR.

**`enforce_admins` is OFF on `main` right now.** If the merge is deferred rather than done, it
must be restored in the same turn with a **bodyless** POST — `-f enabled=true` returns HTTP 422.

## 2026-09-25 — the hostinger smoke FAIL, deep-dived (Claude)

`make test` on `k3d-manager-v1.38.0`: **1129 ok, 0 not ok, exit 0**. The last v1.38.0 gate.

The 17:04 Slack cluster-status FAIL (13 ok / 3 warn / 5 fail) was traced, not dismissed:

- **Frontend SSO + ArgoCD SSO "credentials rejected"** — root cause found. The hub's
  `keycloak-realm-reconcile` Job has been **Failed for 5 days**, 0/1 completions, two Error
  pods. Its log ends:
  `Creating browser-with-conditional-otp flow... / environment: line 104: awk: command not found`
  That is exactly the ubi9-micro no-`awk` bug fixed by shopping-cart-infra PR #100 (`64c11783`).
  The fix is on `main`; the cluster still runs the old manifest because the hub ArgoCD app
  **`shopping-cart-identity` is `OutOfSync`**. Syncing it is the pending post-merge verification.
  Realm users were never seeded, which is why both SSO logins are rejected.
- **Frontend 404 + Product images 404** — the known undecided frontend routing fix.
- **Hub ESO 1/7 not synced: cosign-public-key** — known, Vault path still unchecked.
- **Prometheus 401 warn** — expected; the authenticated `Prometheus login` line is 200.
- **k3dm-smoke-user credentials unavailable** (2 warns) — known; the Frontend API smoke is
  skipped and proves nothing.

Also observed: `istio-cni-ubuntu-hostinger` is `Progressing` — a **fifth** live observation of
the stale istio-cni dirs bug. `ubuntu-k3s-data-layer` is OutOfSync/Progressing because the
ubuntu-k3s context points at the dead ACG sandbox (44.250.167.86, i/o timeout). That stale
context should be deleted to fail fast.

**Navigation note for future sessions: ArgoCD runs in the `cicd` namespace, not `argocd`.**
There is no `argocd` namespace on either cluster. `kubectl -n argocd get applications` returns
"No resources found in argocd namespace" rather than an error, which reads exactly like
"ArgoCD has no apps" and nearly produced a false finding this session. The hub (k3d) owns all
Applications, including every `ubuntu-hostinger-*` one; hostinger's own `cicd` has zero.

## 2026-09-25 — P7: the offline test suites are reader targets (Claude)

`test-pytest` and `test-python-unit` are now `min_role: reader` in `MAKE_TARGETS` (the Slack
`/k3dm` allowlist) and exposed through the cloud bridge as `make-test-pytest` and
`make-test-python-unit`. Both take no arguments, so nothing untrusted reaches argv.

Found and fixed first, because it would have shipped broken: the webhook LaunchAgent's PATH is
`/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`, and under that PATH there is no `pytest`
binary and `python3 -m pytest` fails — pytest lives only in `~/.pyenv/shims`. `make test-pytest`
would have exited 2 on every Slack and bridge invocation while passing locally and in CI.
`test-pytest` now resolves an interpreter in order (`$PYTEST`, `pytest` on PATH,
`python3 -m pytest`, `$HOME/.pyenv/shims/python3 -m pytest`), verified under the exact webhook
PATH with `env -i`. The service PATH was deliberately NOT changed — pyenv-shims-first would
reorder `python3` for every other make target the webhook runs.

`make test` and `make test-bin` are deliberately NOT exposed: both run BATS, the
`scripts/tests/` live-mutation sweep is unfinished, and `deploy_app_cluster_confirm.bats` test 3
provisioned live EC2 until `1cbdab25`. Exposing them is the operator's call.

Gates: `make test-pytest` 215 passed; `make test-python-unit` rc=0; the exposure drift guard
mutation-tested red by removing `make-test-pytest` from the bridge, then green.

Operator ran `make restart-webhook` at 18:09 on 2026-09-25. Fresh PID 54949 bound to
127.0.0.1:7443; `make_targets.py` mtime 18:03:09 predates the restart, so the new allowlist is
loaded. Unauthenticated GET `/api/v1/health` and POST `/api/v1/make` both return 401, so the
listener and the role gate are live on both routes.

Operator closed both open questions with authenticated probes at 18:12:

- `GET /api/v1/health` returns **200**. This is the first time the handler has actually run
  since `f6d60b00`; the earlier `000` dropped-connection regression from the missing
  `return _smoke_test_services` is confirmed dead.
- `POST /api/v1/make {"target":"help"}` with the reader credential lists eight reader targets,
  including `test-pytest` and `test-python-unit`. The Slack `/k3dm` path for P7 is live.

**P7 verified end to end from Slack.** `/k3dm test-pytest` returned "make test-pytest
succeeded", 215 passed in 32.22s, and its first output line is
`[make] /Users/cliang/.pyenv/shims/python3 -m pytest (pytest suites)`.

That line is the whole point: under launchd's real environment the **fourth** fallback branch
fired. `$PYTEST` was unset, no `pytest` binary was on PATH, `python3 -m pytest` failed, and
`$HOME/.pyenv/shims/python3` resolved. Without that fallback the target would have exited 2 on
every Slack and bridge invocation while passing locally and in CI. The `env -i` simulation
predicted this correctly, but the Slack run is the actual proof.

The Slack output also lists `scripts/tests/bin/test_cloud_bridge.py` among the collected
suites, which is the direct confirmation that the vacuous-run bug (`a7d513f3`) is closed: that
file executed nowhere at all before today.

## 2026-09-26 — P6 reader-tier make targets through the cloud bridge

Implemented only P6 on `k3d-manager-v1.38.0`: the bridge now exposes six flat `make-*` actions
for the reader-tier targets, with `make-fix-status` accepting only the required `NS` argument.
The validator's logic is unchanged except for the four-tuple unpack, and make bodies are built as
the existing `/api/v1/make` contract expects. Added four drift guards and the six required logic
checks, including the exact body bytes; no network or live webhook was used. Docs and CHANGELOG
were updated. Gates: bridge pytest 23 passed, webhook policy pytest 22 passed, AST parse passed,
and `make check-doc-links` reported 1784 files OK. Mutation checks were red for each removed
validator guard and restored. Commit: `2db1a172` (amended once to record the final SHA).

## 2026-09-25 — Frontend 404 root-caused; blackbox spec filed; Keycloak awk fix verified

**`frontend.3ai-talk.org` 404 — the tunnel points at the wrong cluster.** The tunnel and its config
are healthy. `~/.cloudflared/config.yml` maps the host to `127.0.0.1:8000`, which OrbStack publishes
into the **k3d hub** cluster's Istio ingress — `curl -D -` on `:8000` answers `server: istio-envoy`,
404, content-length 0. The hub's gateway has VirtualServices for only `grafana` and `prometheus`, and
`shopping-cart-apps` on the hub is **empty**. The healthy frontend is on hostinger, where it is
ClusterIP-only with no Ingress and no NodePort, unlike `order-service` and `product-catalog` which
both have NodePorts. `grafana`/`prometheus` work through the same `:8000` precisely because the hub
does have their routes; `argocd`/`keycloak` work because they are port-forwards on `:8080`/`:8880`.
Second, independent fault: `com.k3d-manager.frontend-port-forward` targets context `ubuntu-k3s` (ACG,
not hostinger) on port 3000, which no tunnel rule references, and answers `000` on both `127.0.0.1`
and `[::1]` despite launchd reporting it up with last exit status 1. Filed
`docs/bugs/2026-09-25-frontend-public-url-routes-to-wrong-cluster.md`. The fix is an architecture
choice (NodePort on hostinger vs a hub VirtualService proxying to it) and is **not** decided.

**Why no SMS.** Delivery was never the problem — `severity = critical` already routes to
`sms-critical`. Nothing produces a signal: `make status` writes no metrics (no Pushgateway writer
anywhere in `scripts/` or `bin/`), there is **no blackbox exporter anywhere in the repo**, and
`ServiceDown` keys on `kube_pod_status_ready == 0`, which is correctly silent when the pod is healthy
and only the public path is broken. Spec filed:
`docs/plans/v1.39.0-public-endpoint-blackbox-probes.md` — two probe modules (a 302 from Keycloak and
a 401 from the auth-gated hosts are *healthy*, so a single naive `valid_status_codes` would be
wrong), an explicit `User-Agent` because Cloudflare 1010-blocks a default one, and three rules:
`PublicEndpointDown`, `CloudflareTunnelDown`, and `PublicEndpointProbeAbsent` so a dead probe is not
mistaken for silence. **This is the 5th v1.38.0 plan doc — the release is at the max-5 cap.**

**Keycloak `awk` fix (Codex, verified).** `e0815211` on
`origin/fix/keycloak-reconcile-awk-free` in `shopping-cart-infra`, parented on `origin/main`, exactly
3 files. Verified independently rather than trusted: `awk` 11 → 0, YAML parses, `bash -n` passes, and
shellcheck is clean on both sides. Two process notes — (1) Codex pushed correctly but left the local
repo with the branch ref still at `origin/main` and the changes uncommitted, so a local
`git rev-parse origin/<branch>` looked like a fabricated SHA until the ref was fetched; it was real.
Synced with `git reset --mixed FETCH_HEAD` (content was byte-identical, so nothing could be lost).
(2) **My spec's shellcheck gate was vacuous** — it extracted `command[3]`, which is the literal `-c`,
so both before and after "counts" were one `SC2215` on a 1-line file. Codex reported that honestly.
The script is `command[4]`; re-run properly it is clean. Behavioural equivalence was then proven
directly: 13 comparisons of each new bash helper against its `awk` oracle on realistic quoted-CSV
input all matched, with 2 negative controls failing as required to show the harness can detect a
difference.

## 2026-09-26 — PR #100 merged, hub SSO fix is on main (Claude)

`shopping-cart-infra` PR #100 merged as `64c11783` — the awk-free Keycloak reconcile hook plus the
four `return 0` lines that Copilot's false positive led to. `enforce_admins` was disabled for the
merge and has been **restored** (bodyless POST, read back `{"enabled": true}`). Local `main` synced.
No tag: the CHANGELOG still has only `[Unreleased]`, and the release version is the operator's call —
last tag is `v0.5.0` (2026-05-19), so roughly four months of work is unreleased.

Still owed on this: the ArgoCD sync that makes the fix take effect, then confirm
`keycloak-realm-reconcile` reaches `Completed` and re-run the cluster smoke for frontend and ArgoCD
SSO. That is a live mutation and waits for the go.

## 2026-09-26 — Hub SSO outage root-caused to the awk-free fix that was never PR'd (Claude)

A cloud session ran the bridge's `cluster-status` and reported 13 ok / 3 warn / 5 fail. Three of
the five failures — frontend SSO rejecting all three Vault `keycloak/users`, ArgoCD SSO rejected —
trace to one cause. `keycloak-realm-reconcile` has two pods in `Error` for 4d23h on the **k3d hub**
(not hostinger; there is no Keycloak and no `identity` namespace on hostinger at all, which is why
a hostinger-scoped smoke report shows hub SSO failures). The log ends:

    Realm shopping-cart exists; applying partial import
    browser-with-conditional-otp flow already exists; reconciling it
    environment: line 104: awk: command not found

The fix has existed since 2026-09-25 as `shopping-cart-infra` `e081521` on
`fix/keycloak-reconcile-awk-free`, pushed to origin, with **no PR ever opened**. Worse, the
browser-flow repair that fixes this exact SSO symptom is already **on main** — the hook crashes
before reaching it, so a merged fix has never once executed. The outage is an unmerged PR, not
missing work.

Pre-PR gates run 2026-09-26, all green: `bash -n` clean on the extracted container script;
`shellcheck -s bash` clean; no residual `awk`/`jq`/`python3`; external binaries reduced to
`cat grep head printf sed`, all present in ubi9-micro; interpreter confirmed `/bin/bash -euo
pipefail -c` so the bashisms in the rewrite are safe. Behaviour equivalence vs the replaced awk
proven 10/10 on representative `kcadm --format csv` input including the real flow display names.
Non-ASCII diverges in the rewrite's favour: old awk aborted `towc: multibyte conversion failure`
and returned empty, new bash percent-encodes correctly under `LC_ALL=C`.

Two gates cannot run pre-merge and the PR body says so: CI is `pull_request`-only in that repo, and
the live smoke is impossible because this is an ArgoCD `PostSync` hook that runs only on sync. PR
body drafted, **not created** — awaiting the owner's go. No manual Job cleanup will be needed:
`hook-delete-policy: BeforeHookCreation` removes the failed pods on the next sync, which closes the
older "operator may need to delete the Failed keycloak-realm-reconcile Job" follow-up.

Still open from the same report and NOT part of this: `cosign-public-key` ExternalSecret in
`platform-ops` is `SecretSyncedError` / `could not get secret data from provider` (Vault path, hub,
unrelated); frontend + product-image 404s (the open architecture call); `k3dm-smoke-user`
credentials unavailable so the Frontend API smoke is **skipped** — excluded from the 13/3/5 tally
and therefore proving nothing.

## 2026-09-25 — Third instance of the bare-branch fetch defect, in the poll path (Claude)

The operator asked whether a **cloud** Claude session could test the bridge. Checking instead of
answering found the answer was no. `bin/k3dm-cloud-request --wait` read
`origin/cloud-requests:responses/<id>.json` but refreshed with `git fetch origin cloud-requests` —
a bare branch name, writing only `FETCH_HEAD`. Reproduced against a real
`git clone --depth 1 --branch main`: `remote.origin.fetch` is
`+refs/heads/main:refs/remotes/origin/main`, so `refs/remotes/origin/cloud-requests` is **never
created**, every poll raises `invalid object name`, and `--wait` exits 5 after the full timeout
with the response sitting on the branch. A full clone hides it entirely, because `git clone` writes
every remote-tracking ref up front — which is why two live round trips from this laptop passed.

That is the shape a cloud session runs in, i.e. the only environment the helper exists for. The
poll now fetches an explicit `+refs/heads/cloud-requests:refs/remotes/origin/cloud-requests` and
reads from that ref; proven on the same shallow clone, which then returned `status: ok http: 200`.
Regression test added (13 total), mutation-checked: the pre-fix module has no `FETCH_REFSPEC`.

Standing lesson: this is the **third** distinct occurrence of the same root cause in one feature.
Both ends now name refs explicitly, and the how-to says not to "simplify" it back.

Follow-up the same day: the cloud session asked for a `.claude/settings.json` permission grant to
run the helper. `.claude/` was in `.gitignore`, so committing that file would have been accepted and
tracked **nothing** — git cannot re-include a file whose parent directory is excluded. Changed the
pattern to `.claude/*` plus `!.claude/settings.json`, verified with `check-ignore` that the 103KB
`settings.local.json` and `projects/`/`worktrees/` stay ignored.

That grant still did not unblock the cloud session, and the reason is worth keeping: its checkout
had no `bin/k3dm-cloud-request` at all. `git ls-tree` on `v1.36.0`, `v1.37.0` and `origin/main`
returns nothing for the helper, the bridge or the how-to — the whole feature was added in
`dc53987c`, which lives only on `k3d-manager-v1.38.0`, while `origin/main` is still `925c43e7`
(v1.37.0). The missing settings file is the symptom an agent notices first, so the failure reads as
a permissions problem when it is a missing file. The how-to now opens the short version with an
`ls bin/k3dm-cloud-request` check and says to start the session against the branch carrying the
bridge rather than patch permissions. No `claude/*` branch exists on origin, so a cloud session's
branch is container-local; and it loads permission rules at clone time, so a mid-session checkout
would not pick the grant up either.

**Closed 2026-09-26 — the cloud half is proven.** With the session on `k3d-manager-v1.38.0` and
**auto mode off**, a real cloud session filed two requests that completed end to end:
`20260926T000251Z-cluster-status` (http 202, job `eb0df4ec`) and `20260926T000330Z-job-status`
(http 200, `running`). Verified from this laptop rather than taken on report: the request commits
`45e4365c`/`7885e7b2` are authored `Claude <noreply@anthropic.com>`, distinct from the `t <t@t>`
author on my own earlier test `c03e45f9`, so they did not originate here. Branch tip `7885e7b2`.

The blocker was never the allowlist. With auto mode on, a safety classifier refuses the helper as a
"Containment Escape", and a `settings.json` `allow` rule cannot override a classifier — independent
layers, so no repo change would have cleared it. Auto mode off degrades it to an approval prompt the
operator accepts. My prediction that a classifier would refuse outright rather than prompt was
wrong, and the correction matters: the feature is operator-overridable, not structurally undeliverable
inside a cloud sandbox. Recorded in the how-to's short version.

## 2026-09-25 — Cloud bridge bootstrapped and proven end to end (Claude)

The operator gave the go, so `origin/cloud-requests` now exists and the bridge is live.

Three new make targets: `init-cloud-requests` (seeds the branch as an **orphan** commit through
git plumbing — `hash-object`/`update-index` on a throwaway `GIT_INDEX_FILE`/`write-tree`/
`commit-tree` — so it never touches the worktree, moves `HEAD`, or triggers a pre-commit hook; it
is idempotent and skips when the remote ref exists), `install-cloud-bridge` (renders the plist,
`plutil -lint`s it, and bootstraps the `gui/` agent; refuses unless the reader Keychain item and
the remote branch are both present), and `uninstall-cloud-bridge` (the documented revocation
lever).

The branch is an orphan on purpose: it carries only `ledger/processed.txt`, shares no history with
any release branch, and holds no repo code that a compromised cloud session could modify into
something executable. Seeded at `67dc3468`, parents `[]`.

Two blocking bugs, both the same root cause — **`git fetch origin cloud-requests` with a bare
branch name makes git ignore the configured refspec and write only `FETCH_HEAD`**, so nothing
maintains `refs/heads/cloud-requests`:
- bridge: in the bare clone the branch ref stayed at the seed while `parent` came from
  `FETCH_HEAD`, so `_write_commit`'s `update-ref <new> <old>` failed its old-value check every
  tick (`is at 67dc3468 but expected 0188d59b`, four identical log lines). It failed *before* the
  push, so the webhook was never called and no ledger entry was written — the request was retried
  intact, not half-executed. Fixed by fetching an explicit
  `+refs/heads/cloud-requests:refs/heads/cloud-requests`.
- `bin/k3dm-cloud-request`: `update-ref refs/heads/cloud-requests <commit> <remote parent>` in a
  clone with no such local ref → `unable to resolve reference`. That is exactly the state the
  how-to's own `git fetch origin cloud-requests` leaves a cloud session in, so the documented
  flow could never have worked. The local `update-ref` was pointless (the push carries an explicit
  lease) and is gone. Its no-remote-branch case also leased against the empty *tree* SHA, which no
  ref can equal; now the empty string, which git defines as "must not exist".

Plist template: `KeepAlive` replaces `StartInterval 60` — `main()` is a persistent daemon with its
own 60s loop, so the one-shot idiom delayed crash recovery by up to a minute.

End-to-end proof on the live path, not a mock: `cluster-status` → `http_status 202`,
`body.job_id 4c645143`, ledger appended, response committed and pushed; then
`job-status --arg job_id=4c645143` → `http_status 200` with the full status text and secrets
`***REDACTED***`, helper exit 0. Branch is now `67dc3468` (seed) → `0188d59b` (request) →
`f52041d8` (response). Agent `runs = 1`, `never exited`, log empty. The bare clone over SSH from a
`gui/` agent worked, which answers the open SSH-agent question.

Gates: `pytest` cloud_bridge + webhook_policy + webhook_make_targets + test_smoke_logins → 64
passed, 121 subtests; `bats scripts/tests/lib/webhook.bats` → 64 ok; AST parse both bins;
forbidden-pattern grep empty; `make check-doc-links` 1782 OK. The new refspec test was
mutation-checked against the pre-fix source (`assert ':' in 'cloud-requests'` failed).

## 2026-09-25 — P2/P5 cloud session bridge implemented

Implemented Part 2 of `v1.38.0-cloud-session-endpoint-access.md` on
`k3d-manager-v1.38.0`: `bin/k3dm-cloud-bridge` is a 60-second bare-clone poller using the
reader credential and plain loopback HTTP, with fixed four-action validation, replay ledger,
bounded processing, and Git plumbing commits; `bin/k3dm-cloud-request` files and optionally polls
requests using the fixed CLI contract. Added the launchd template, nine pure validator tests, the
three Copilot invariants, and the Unreleased Added entry. The README how-to link was already
present and was not changed; the contract/spec were not changed.

P4 verification counted exactly two workflow files across both `.yml` and `.yaml`: `ci.yml` is
pull-request-only for `main`, and `deploy-worker.yml` is push-scoped to `main` plus
`workers/slack-relay/**`; neither includes `cloud-requests`.

Verification before commit: `pytest scripts/tests/bin/cloud_bridge.py` 9 passed;
`pytest scripts/tests/bin/webhook_policy.py` 22 passed; both Python files AST-parsed; the
placeholder-substituted plist passed `plutil -lint`; `make check-doc-links` reported 1782 files;
`_agent_audit` passed. The forbidden-string and plain-loopback grep gates were empty. Commit and
push are blocked in this managed workspace: Git cannot create `.git/index.lock` or insert staged
objects (`Operation not permitted`), including when given an alternate index under `/private/tmp`.

## 2026-09-25 — Part 2 cloud bridge verified, with one structural fix (Claude)

Codex delivered P2/P5 but could not commit (the usual `.git` write denial), leaving all 8 files
staged. **Claude then committed them by accident** under a memory-bank message — `git add
memory-bank/progress.md && git commit` sweeps the whole index. Unpushed, so `git reset --mixed
f6d60b00` recovered it with the worktree intact. Second occurrence of that exact failure; the
memory rule now names the mechanism and prescribes `git diff --cached --stat`.

Verified: no forbidden patterns (no `git checkout`/`switch`, no `--no-verify`, no `--insecure`/
`verify=False`, no `https://`/`SSLContext`, no `shell=True`/`eval`), no token printing, no
`TOKEN_FILE` fallback, AST parses, plist lints, doc links OK, pytest 63 + 121 subtests, bats 64/64.
Validator is genuinely tight: exactly six fields, exact arg-key match, size cap applied *before*
JSON decode, id consumed before validation so an expired request cannot be retried.

**One structural weakness fixed.** The per-value check was `if key == "job_id"`, correct only
because `job_id` is currently the sole parameter — declaring a second would have sent its value
into the request path with **no validation at all**. The allowlist now binds each parameter to a
compiled pattern, so a parameter cannot be declared without one. Two tests added, both
mutation-checked. This is the third instance this session of the same class: correctness that holds
only by coincidence of the current table (dead `min_role`, the ungated `health?` form, this).

Also corrected in my own handoff before dispatch: it told Codex the webhook was HTTPS with a
self-signed cert. It is a bare `ThreadingHTTPServer` on loopback with no `wrap_socket`
(`bin/k3dm-webhook:2238`), and `bin/k3dm-hermes:123` calls it as `http://`. And a claim I made that
is *not* quite right: `_spawn_capture_text` does NOT keep argv a literal list when `cwd` is set —
it builds `/bin/bash -c "cd … && …"`. It is `shlex.quote`d and the only request-derived value
reaching git is the `ID_RE`-validated `request_id`, so it is safe, but the safety rests on quoting
plus validation, not on the absence of a shell.

Moved the three new Copilot rules out of `## Architecture` into `## Review Focus` where review
rules belong, and expanded them to six covering the role ceiling, `min_role` actually being read,
untrusted branch bytes, the allowlist as boundary, workflow scoping, and token placement.

## 2026-09-25 — S3 gate was unreachable for the health query form (Claude follow-up)

Verified `8b706882` independently: SHA on origin, 4-file scope, bare pytest and
`bats scripts/tests/lib/webhook.bats` 64/64 re-run by Claude, including test 62 — the
`_request_role({}) == "admin"` contract that `token_role=None` had to preserve.

One gap found. The new gate is guarded by `get_route is not None`, and `get_route` resolves by
exact dict lookup plus a `/api/v1/status/` prefix. `/api/v1/health?...` matches neither, so
`get_route` stayed `None`, the gate was skipped, and the `startswith("/api/v1/health?")` branch
served the request anyway — one of the two health branches ungated, which is the exact defect S3
exists to close. No privilege was reachable today (health's `min_role` is already `reader`), but it
reinstated the unenforced coincidence: raise health's `min_role` and the query form bypasses it.

Fixed by resolving the health route for the query form before the gate, plus
`test_get_role_gate_covers_health_query_string_form`. Mutation-checked: without the guard the test
fails, and the pre-patch response was `200`, confirming the bypass was real rather than theoretical.

Also corrected `docs/howto/cloud-session-requests.md`, which claimed reader-token rotation needs
`make restart-webhook`. It does not — `_auth()` reads the Keychain per request. The doc now also
names the service/account, the no-TTY empty-write trap, and why `bin/k3dm-webhook-setup` must not
be reused (it puts the value in argv and pushes it to a GitHub secret).

## 2026-09-25 — webhook credential-bound roles COMPLETE (`8b706882`)

Implemented only v1.38.0 spec sections S1, S2, S3, and S6 on `k3d-manager-v1.38.0`.
`auth.py` now resolves admin/reader bearer credentials, `policy.py` treats the credential role as
the ceiling, POST and make-target authorization receive that ceiling, and `do_GET` enforces route
`min_role` before the existing health branches. Added the eight requested policy tests, including a
copied above-reader GET route. No `bin/` files were created; P1/P2/P4/P5/S7 and workflow/docs
changes were not implemented.

Remote commit: `8b706882` on `origin/k3d-manager-v1.38.0`.
Gates: bare pytest 36 passed plus 121 subtests; `bats scripts/tests/lib/webhook.bats` 64/64;
AST parse passed; staged `_agent_audit` passed. Shellcheck was not run because all touched files
are Python. Mutation check against the original policy produced the two required failures for S6
items 3 and 4, then the edited policy was restored and its working hash differed from HEAD.

## 2026-09-25 — cloud-session access: PULL chosen; a live privilege-escalation gap found

Spec `docs/plans/v1.38.0-cloud-session-endpoint-access.md` (#4 of 5 for v1.38.0). Operator decided
**pull**, not exposing the endpoint. The push path (cloudflared ingress + Cloudflare Access
application + service token + cloud env vars) is recorded in the spec as not-chosen, to be revisited
only if a session needs live state at sub-60s latency.

**Audit finding F4, promoted — not a new discovery.** The 2026-09-07 audit
(`docs/issues/2026-09-07-webhook-server-security-audit.md` F4) already recorded that
`X-K3DM-Role` is client-asserted, rated LOW *because of* the single-admin-token invariant, with
"revisit if role-scoped tokens are added." Adding a reader token is exactly that condition, so
F4 becomes blocking: its own text says "a low-tier token could send `X-K3DM-Role: admin` and
escalate." A bearer-token holder is `admin` today and the role is self-asserted by the caller. `scripts/lib/webhook/policy.py:108`:

```python
def _request_role(headers):
    raw = headers.get("X-K3DM-Role")
    if raw is None:
        return _ROLE_DEFAULT  # direct token = admin credential
```

`_ROLE_DEFAULT = "admin"` (line 30). `bin/k3dm-webhook:1713` `_auth()` compares the bearer and
returns a bool — no identity travels forward, so nothing binds a role to a credential. Omitting
`X-K3DM-Role` (or sending `admin`) reaches `cluster-up`, `cluster-down`, `cluster-resume`,
`cleanup-stale-sandbox`, `argocd-upgrade`. `_normalize_actor_role`'s fail-closed-to-reader does NOT
cover it: it normalizes an already-resolved string, and the direct-token path never routes through a
resolver that could return an unknown value. `_effective_make_role` also short-circuits when the
header is absent.

This exists **independently of any cloud access** — it is not introduced by this work, and it is why
the earlier claim had to be retracted that a cloud token could simply be "registered as reader". That
is not configuration; S1/S2 of the spec is the code change. Fix shape: a second reader-scoped token
(`k3dm-webhook-token-reader`, env `K3DM_WEBHOOK_TOKEN_READER`, no `TOKEN_FILE` fallback) plus
`_request_role(headers, token_role)` treating the credential's role as a **ceiling the header can
only narrow**. `token_role=None` keeps today's behavior byte-identical.

**Invariant for copilot-instructions.md:** a request header may only ever narrow a role; the
credential sets the maximum. Any code letting a header raise a role is a privilege-escalation bug.

Pull design: branch `cloud-requests` (never merged) carrying `requests/`, `responses/`,
`ledger/processed.txt`; new `bin/k3dm-cloud-bridge` on a 60s launchd tick reads blobs from the
**fetched ref** (never `git checkout` — it runs unattended against the operator's tree), validates
in a fixed order, and calls `127.0.0.1:7443` with the reader token. Allowlist is reader-only:
`health`, `cluster-status`, `hostinger-status`, `job-status`. `/api/v1/ask` and `/api/v1/analyze`
are excluded despite being `min_role: reader` — they invoke an AI and the request file is authored
from GitHub content, which is the injection source `_INJECTION_RE` exists for.

Nothing implemented. Not approved: bootstrapping the `cloud-bridge` launchd agent, creating the
`cloud-requests` branch.

## 2026-09-25 — deploy_app_cluster_confirm test isolated from live infrastructure (`1cbdab25`)

Fixed `scripts/tests/core/deploy_app_cluster_confirm.bats` per Part A of the bug spec:
setup now hard-fails `ssh`/`scp`, stubs `kubectl`, test 3 uses a STUB_DIR-scoped kubeconfig,
and asserts provisioning output is absent. The focused suite passes 3/3; mutation removal
of the production SSH-key guard made test 3 fail, and the production file was restored clean.
Shellcheck is clean excluding the pre-existing dynamic-source SC1091.
Claude verified independently: origin tip `1cbdab25`, one file in `--stat`, BATS 3/3 on a
re-run, zero forbidden strings, `~/.kube/config` mtime unchanged at `Sep 25 11:46:45`, and
`shopping_cart.sh` blob `8b2d8261` identical to the one at merge commit `925c43e7` — so the
mutation-check restoration was byte-exact, not merely `git diff`-clean. Codex's `_agent_audit`
claim was NOT verified and has been dropped rather than recorded.
Committed and pushed to `origin/k3d-manager-v1.38.0` at
`1cbdab25bbe894d8658a82d22d5438f945f0e86d`. No production file was changed.

## 2026-09-25 — `make test` 1128/1129: the one red provisions live EC2 (`6da697a6`)

`make test` on `k3d-manager-v1.38.0` ran to completion: **1128 ok / 1 not ok of 1129**, exit 2.
The single failure is `not ok 3 deploy_app_cluster --confirm reaches the confirmed path
(Finding 2b)` at `scripts/tests/core/deploy_app_cluster_confirm.bats` line 41 — deterministic,
reproduced standalone, not a flake.

**The failure is the lesser finding.** The test stubs only `k3sup`, so with the ACG `k3s-aws`
sandbox reachable `deploy_app_cluster` takes its live path: it merged the `ubuntu-k3s` context
into `~/.kube/config` and installed socat + a vault-bridge systemd unit on EC2 server
`44.250.167.86`, then returned **0** instead of the asserted 1. That ran three times today —
the operator's `make test` plus two diagnosis reproductions — before the behavior was
understood. Mutations were idempotent (the context pre-existed), by luck not design.
`~/.kube/config` mtime `Sep 25 11:46:45 2026`.

Root cause `scripts/plugins/shopping_cart.sh:1375-1400`: the `[[ -f "${ssh_key}" ]]` guard is
nested **inside** `if (( _server_ready == 0 ))`, but the function SSHes after that block
regardless. A guard inside an early-exit branch is not a guard. The nonexistent
`-i /nonexistent/k3d-manager-key.pem` did not stop it either — `ssh` falls back to
ssh-agent/default identities and only warns `Identity file ... not accessible`, so a bogus key
path cannot be used to force an SSH failure in a test.

**Not a v1.37.0 regression.** `git blame` → `1bbe54393` (2026-08-21) for both the `_server_ready`
probe and the guard; the test file last changed in `62c9ff27` (v1.27.0). It is green in CI only
because no cluster answers there. CLAUDE.md declares `scripts/tests/` "pure logic only — no
cluster mocks" — this file violates that and writes to a remote host.

Spec filed: `docs/bugs/2026-09-25-deploy-app-cluster-confirm-bats-mutates-live-cluster.md`
(dedup clean — the four similar `*confirm*` docs are all about the dispatcher stripping
`--confirm`). Part A (stub the reachability probe, plus `ssh`/`scp` hard-fail stubs) is required
and self-contained. **Part B — relocating the key guard in `shopping_cart.sh` — is unapproved:**
it changes behavior on the already-Ready path, so it waits on the owner. Neither part is
implemented.

Not yet swept: the rest of `scripts/tests/` for the same class of reachability-dependent live
mutation. This file was found by a failure, not by a search.

## 2026-09-25 — CodeQL alert 25 resolved by renaming, not dismissing (`1d31d9e7`)

The last red check on PR #131. `py/clear-text-logging-sensitive-data` (high) at
`bin/k3dm-hermes:451` — a `print(json.dumps(...))` **the PR never touched**. `git diff
origin/main...HEAD -- bin/k3dm-hermes` confirms it: the PR added a new taint *source* that
reaches an existing *sink*.

The source is the new `alert_delivery` sensor's dict key `config_secret`. CodeQL classifies
any `secret`-shaped **identifier** as sensitive data — no value flow is involved. Path:

```
sensors.py  item.get('config_secret')  ->  blackout  ->  data  ->  record()
            ->  records  ->  print(json.dumps({"records": records, ...}))   # :451
```

The value is the *name* of the Secret in the Alertmanager CR's `spec.configSecret`;
`bin/k3dm-alert-delivery-status:36` only does `kubectl get secret "$name" >/dev/null` — an
existence check. Contents are never read. Live probe confirms:
`"config_ref": "alertmanager-smtp-secret"`.

**Owner chose rename over a fifth dismissal.** `config_secret` -> `config_ref`,
`config_secret_missing` -> `config_ref_missing`. Rationale worth keeping: a name-based
heuristic re-fires on *every* future `*_secret` field that carries a reference, so removing the
trigger word removes the class where a suppression hides one instance — and the field was
misleading anyway. Blast radius was only three files with zero consumers on `main`, because the
field ships in this same PR. The operator-facing message still reads `configSecret <name>
absent` (string *contents* are not a CodeQL source, only identifiers are), and the reasoning is
now in the `alert_delivery` docstring so nobody tidies the name back.

**Checked the two adjacent taint paths into the same `print` at the same time**, so clearing one
did not leave a real one: `approvals` filters relay items through three anchored regexes and
keeps only `action_id`/`outcome` (a token cannot match `^r[0-9]+-[0-9a-f]{8}$`); `pages` is built
from `alert.get('number')` only. Both clean.

Generalisable: **CodeQL's Python sensitive-data rules key on identifiers, not values.** A field
holding a *reference* to a secret must not be named like the secret, or it silently converts any
downstream log line into a high-severity alert.

## 2026-09-25 — Copilot PR #131: two v1.37.0 gates could not fail

Both findings accepted, neither a false positive, and both inside the milestone's *own* new
tests — the release whose theme is "gates that prove their claim". Fixed in `c914ef8d`,
documented in `docs/issues/2026-09-25-copilot-pr131-review-findings.md`, both threads resolved.

1. `hostinger_pushgateway_port_forward.bats:19` asserted a disappearance with
   `! rg -n --pcre2 ...`. `!` inverts **any** non-zero exit, so `rg` absent (127) or built
   without PCRE2 (2) passed exactly like "no matches" (1). `rg` is a Homebrew package and the
   CI workflow never installs it, so both vacuous rows were reachable. Now `grep -nE` with
   `[ "${status}" -eq 1 ]` — grep reserves 2 for any error, so this is *stricter* than the
   original, not merely portable. The PCRE2 negative lookahead has no ERE form; it became a
   consuming `([^[:alnum:]_-]|$)` alternation, where the `|$` arm replaces the free
   end-of-line match.

2. `e2e_observability.bats:225,230` (the two new Alertmanager route tests) took a hard PyYAML
   dependency. `argocd.bats:389` already guards `import yaml` behind `command -v` — the repo's
   own evidence it cannot be assumed — while `yq` is invoked **unguarded** by four suites
   (`prometheus_port_split`, `signing`, `grafana_dashboard_appsets`,
   `alertmanager_config_secret`). Moved to `yq`. Beyond Copilot's suggestion: a `select` that
   matches nothing exits 0 with empty output, so `[ -n "${output}" ]` is required or deleting
   the warning route outright passes; and `-gt` against an empty string is a bash *syntax
   error*, not a failure, so both route indices are range-checked first.

**Generalisable rules** (the reusable part):
- Never assert a disappearance with `! <tool>`. Invert on an exact status so a missing tool or
  unreadable file fails. `grep`'s 1-vs-2 split exists for this.
- A test may depend only on tooling something else in the suite already depends on *unguarded*.
  An existing guard elsewhere is the signal not to take a hard dependency.
- A `select`/filter query needs a non-empty assertion, or deleting the subject passes.

All three rewritten assertions mutation-tested against the live tree (append
`# svc/pushgateway`; repoint the warning receiver at `'null'`; swap the warning route ahead of
the allowlist) — each failed the intended test, then both suites restored 20/20.

## 2026-09-25 — MinIO repoint DONE and verified on origin (`e9d545d`), unmerged

`shopping-cart-infra` branch `fix/minio-bitnamilegacy-registry`, commit `e9d545d`, confirmed on
origin via `gh api` (local HEAD == `origin/fix/...`). **No PR opened** — `gh pr list` empty.

Codex's **first** dispatch was blocked by the known sandbox limit: `git fetch` failed with
`cannot open '.git/FETCH_HEAD': Operation not permitted`. It stopped before editing anything rather
than working around it, which was correct. Workaround applied: Claude created the branch from
`origin/main` and did the commit/push; Codex was re-dispatched with **all git writes removed from
its scope**, doing edits plus seven read-only gates. Worth reusing — see
[[reference_codex_exec_cannot_commit_git_lock]].

Independently verified, not taken on trust: YAML parses; `grep -rn 'quay.io/minio' data-layer/`
prints NONE; `console-address` gone; all three images on bitnamilegacy; `mountPath`
`/bitnami/minio/data`; `fsGroup`/`runAsUser` both 1001; `secret.yaml`, `service.yaml` and
`image-upload-configmap.yaml` all UNCHANGED; scope on origin is exactly 5 files. Diff read in full
— matches the spec with no creep. Note `git diff --stat` did **not** list the new bug doc because
it was untracked; `git status --short` was needed to see it.

**Not yet proven at runtime.** Nothing has pulled the Bitnami image on a cluster. Residual risks to
watch on the next `make up`:

- Bitnami's `run.sh` reads `MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD` — present, but it also enforces
  minimum lengths; if the seeded credential is short the container will refuse to start.
- The existing sandbox PVC was created under UID 1000. It is empty (MinIO never started), so the
  UID move to 1001 is safe *here*; on any cluster where MinIO did run, pre-existing files owned by
  1000 would not be writable by 1001 and the volume would need chown or recreation.
- `bitnamilegacy` is a sunset repo. Follow-up (owner's call): mirror both pinned images into
  `ghcr.io/wilddog64/`, which *is* possible since bitnamilegacy is public, so a third upstream gate
  cannot break provisioning. Needs a GHCR push credential.

Merge is the owner's call; PR gates have not been run.

## 2026-09-25 — tunnel cleanup fixed; MinIO registry spec dispatched to Codex

**Cloudflare tunnel (fixed, `e1811e67`).** `_acg_up_cleanup` in `bin/cluster-up` ran an
unconditional `launchctl bootout` of `com.k3d-manager.cloudflare-tunnel` on any non-zero exit, but
`cluster-up` does not install or bootstrap that tunnel until ~line 1809 — far past Step 10b, where
all three observed failures happened. It was destroying a permanent service it had never created:
the plist lives in `~/Library/LaunchAgents` with `RunAtLoad` + `KeepAlive=true` and serves the hub's
public ingress independently of any sandbox. Now gated on `_ACG_TUNNEL_PLIST_CREATED`, set only
where the run installs the plist and none existed before, so "clean up what you created" survives.
Four BATS cases; mutation-proven (restoring the unconditional bootout fails three of four).
`bin/cluster-refresh` was checked and is fine — its bootout is half of a bootout+bootstrap restart.
Resolution appended to `docs/issues/2026-09-25-cloudflare-tunnel-killed-by-make-up-cleanup-no-alert.md`.

**MinIO: my earlier GHCR-mirror recommendation was wrong and is withdrawn.** Mirroring requires
pulling the source, and there are no credentials for it. Probed every alternative:
`ghcr.io/minio/minio` 403, `docker.io/minio/minio` does not exist, quay gated at the repository
level (`latest` and a 2022 tag both 401). The only public source carrying the *same* upstream
releases is Bitnami's sunset repo:

| replacement (200 anonymously) | replaces | same release |
|---|---|---|
| `docker.io/bitnamilegacy/minio:2024.11.7-debian-12-r1` | `quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z` | yes |
| `docker.io/bitnamilegacy/minio-client:2024.11.5-debian-12-r1` | `quay.io/minio/mc:RELEASE.2024-11-05T11-29-45Z` | yes |

It is a **port, not a tag swap** — verified from the image configs: `User` 1000 -> 1001, an
entrypoint that runs its own `run.sh` (so the existing `args: [server, /data, --console-address,
":9001"]` must be deleted or the container fails), data dir `/data` -> `/bitnami/minio/data`, and
`mc` at `/opt/bitnami/minio-client/bin/mc` not `/usr/bin/mc`. `secret.yaml` needs no change: it
already exposes `MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD`, exactly what Bitnami reads.

Spec at `docs/bugs/2026-09-25-minio-quay-registry-gated.md` (`071acd24`), dispatched via
`codex exec` into `shopping-cart-infra` on branch `fix/minio-bitnamilegacy-registry` from
`origin/main`. Codex session `01a0d93a-484a-71f0-b523-cf42e823ae55`, log at
`scratchpad/codex-minio.log`. **Unverified — do not trust the completion report.** On return:
confirm the SHA is on `origin/fix/minio-bitnamilegacy-registry`, the diff touches only the three
YAMLs plus CHANGELOG and the bug doc, `grep -rn 'quay.io/minio' data-layer/` prints NONE, and no PR
was opened.

Follow-up once green, owner's call: `bitnamilegacy` is itself sunset, so mirror both pinned images
into `ghcr.io/wilddog64/` — which *is* possible since bitnamilegacy is public — needs a GHCR push
credential.

## 2026-09-25 — data-layer sync wait now fails fast on a blocked image pull

Implements the second finding from the quay/MinIO failure below. `bin/cluster-up` gained two
helpers before `login_prompt=0`:

- `_acg_image_pull_blocked <ns> <ctx>` — prints one `pod/<name> <container> <reason>: <message>`
  line per container waiting on `ImagePullBackOff`, `ErrImagePull`, `InvalidImageName`,
  `ErrInvalidImageName` or `RegistryUnavailable`, init containers included; rc 0 when any found.
- `_acg_data_layer_abort_on_image_pull` — three-strike gate (20s of grace) so an in-progress pull
  is not mistaken for a permanent failure, then WARNs the detail and returns 0 to abort.

Wired into **both** data-layer sync waits (pre- and post-force-sync). `CreateContainerConfigError`
and `CrashLoopBackOff` are deliberately NOT fatal — they can clear once ESO populates a Secret.

Verified against the live broken sandbox, not just stubs: poll 1 and 2 logged `not settled (n/3)`,
poll 3 aborted naming `pod/minio-0 minio ImagePullBackOff`. Controls (`kube-system`, a
nonexistent namespace) correctly returned not-blocked. Six new BATS tests in
`scripts/tests/bin/cluster_up.bats`, 18/18 green, `bash -n` and shellcheck clean.
Mutation-proven twice: dropping `ImagePullBackOff` from the reason list fails tests 13 and 16;
removing either loop call-site fails test 18.

**Two bugs found in my own helper while testing it live** — both worth remembering:

1. `print(f"... {cs.get(\"name\", \"?\")} ...")` is a `SyntaxError` even on Python 3.13
   (PEP 701 allows nested quotes but not backslash escapes inside an f-string expression). With
   `2>/dev/null` on the python and `|| return 1` after it, this produced a **silent false
   negative** — the probe reported "not blocked" against a cluster that was visibly blocked, which
   is exactly the failure mode the helper exists to prevent. Fixed by binding the name to a local
   first; python stderr is no longer suppressed, only kubectl's.
2. A column-0 `}` inside embedded python (the closing brace of a multi-line `set` literal) breaks
   any `sed -n '/^function f/,/^}$/p'` extraction, which is how the BATS tests source these
   helpers out of a non-sourceable script. Flattened the literal to a parenthesised tuple.

Committed on `k3d-manager-v1.37.0`.

## 2026-09-25 — `make up` failed at data-layer: quay.io/minio is no longer anonymously pullable

`make up CLUSTER_PROVIDER=k3s-aws` got all the way to the data-layer wait and then failed
(exit 2) with `data-layer ArgoCD Application did not reach Synced after force-sync + 180s retry`.
The SSM path was never touched this run (autoselect chose SSH, stack reused), so this is unrelated
to the SSM work.

**Real cause: `minio-0` is in `ImagePullBackOff`.** 6 of 7 StatefulSets in
`shopping-cart-data` are healthy (`postgresql-orders/payment/products`, `rabbitmq`, `redis-cart`,
`redis-orders-cache`); only `minio` is stuck:

```
Failed to pull image "quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z":
  unexpected status from HEAD request to
  https://quay.io/v2/minio/minio/manifests/RELEASE.2024-11-07T00-52-20Z: 401 UNAUTHORIZED
```

The ArgoCD operation was still `phase: Running`, `waiting for healthy state of
apps/StatefulSet/minio` — so the wait loop timing out is a symptom; it was never going to converge.

**This is not a bad tag and not our network.** Anonymous pulls of the whole repo are gated now:

| probe | result |
|---|---|
| `quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z` (anon token) | 401 |
| `quay.io/minio/minio:latest` (anon token) | 401 |
| `quay.io/minio/mc:latest` (anon token) | 401 |
| `quay.io/prometheus/busybox:latest` (control, anon token) | **200** |
| `quay.io/api/v1/repository/minio/minio` | 401 `Requires authentication` |
| Docker Hub `minio/minio` | `object not found` — never published there |

The control proves quay.io and egress are fine. `minio/minio` AND `minio/mc` both require auth as
of now; the May 2026 bug doc `2026-05-23-minio-mc-image-tag-not-found.md` explicitly recorded that
`minio/minio:RELEASE.2024-11-07T00-52-20Z` "does exist and pulls successfully" at the time, so the
gate is new. The hub never cached it (`no minio on hub`), which is why a fresh sandbox is the first
place this surfaced.

**Fix belongs in `shopping-cart-infra`, not here** — `data-layer/minio/statefulset.yaml:35` plus
`bucket-init-job.yaml:28` and `image-upload-job.yaml:28` (both `quay.io/minio/mc`, equally gated,
not yet reached). Per repo discipline that is spec + Codex on a feature branch, and needs the
owner's go. Options, not yet decided: mirror both images into GHCR under `wilddog64/`, add a pull
secret for a MinIO account, or move off MinIO for the sandbox data layer.

**Third Cloudflare tunnel kill.** The failure-cleanup path unloaded
`com.k3d-manager.cloudflare-tunnel` again — `bin/public-endpoint-probe --json` returned
`edge-down`, all 7 hosts 530. Restored with `launchctl bootstrap gui/$(id -u)`; re-probe shows
6/7 healthy (`frontend` 404 is expected, the app never deployed). Incident follow-up #2 is now
**reproduced three times** and should stop being a follow-up.

**Second finding, already known and now costly:** the data-layer wait loop cannot distinguish
"not yet Synced" from "will never sync". A plain `ImagePullBackOff` on one pod was reported as
8 minutes of `data-layer not yet Synced — waiting...` followed by a force-sync retry that could
not possibly help. The loop should surface non-Ready pod reasons (`ImagePullBackOff`,
`CreateContainerConfigError`, `CrashLoopBackOff`) and fail fast on them.

## 2026-09-25 — SSM->SSH fallback was dead code: `_err` exits, so every fallback branch was unreachable

Follow-up to the SSM backoff root cause below. The provider already intends to degrade to SSH —
`scripts/lib/providers/k3s-aws.sh:127` says "fall back to SSH; provisioning fails only if both
transports fail" — and there are three correctly written fallback sites:

| site | intent |
|---|---|
| `k3s-aws.sh:138` | `wait_ssm_registered` fails -> `falling back to SSH tunnel` |
| `k3s-aws.sh:156` | `SSM bootstrap failed — falling back to SSH provisioning` |
| `k3s-aws.sh:161` | retry `deploy_app_cluster` with `K3S_AWS_SSM_ENABLED=false` |

**None could ever run.** `_err` (`scripts/lib/system.sh:1731`) is fatal:

```bash
function _err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
```

Both registration waits ended in `_err`, so the process exited at the timeout; the `return 1` on
the following line and every caller's fallback were unreachable. The failed `acg-recover` log
proves it — line 65 `Provisioning app cluster via SSM (SSH fallback armed)`, line 67
`ERROR: [ssm] Instance i-04f4f6420ae76148c did not become Online after 300s`, line 68
`WARN: [acg-up] failed (exit 1)`. No fallback WARN in between.

**The BATS suite was green over the bug.** `scripts/tests/lib/k3s_aws_provider.bats:333` stubbed
`_provider_k3s_aws_wait_ssm_registered() { return 1; }` — a stub that *returns* where the real
function *exits*. The test asserted the fallback message and passed, because the stub behaved the
way the code was meant to rather than the way it did. That test could not fail.

Fix: `_err` -> `_warn` in `ssm_wait` (`scripts/plugins/ssm.sh:72`) and
`_provider_k3s_aws_wait_ssm_registered` (`scripts/lib/providers/k3s-aws.sh:88`). Three new tests
drive the **real** functions (stubbing only `aws`/`_run_command`/`sleep`) and were mutation-proven:
all three fail against the pre-fix source, all pass after. 26/26 green across both suites,
shellcheck clean. Documented in `docs/howto/acg.md` under a new "SSM vs SSH transport" section.

Two notes for later:

- A repo-wide sweep found ~200 other `_err` followed by an unreachable `return` across
  `scripts/plugins/` and `scripts/lib/`. Almost all are genuinely fatal so the dead `return` is
  harmless idiom — but any future "degrade instead of abort" path must use `_warn`, not `_err`,
  or it will be dead on arrival. Not fixed: out of scope, would be a mass refactor.
- The SSM path is unreachable in the default profile anyway: `k3s-aws.sh:104` forces
  `K3S_AWS_SSM_ENABLED=false` whenever `HUB_VAULT_USE_BRIDGE=1` (the default), because the Vault
  bridge needs a reverse tunnel. That is why this survived so long, and why today's `make up`
  bypassed SSM entirely. Still unfixed: the two-pass `EnableSsm=false` -> `true` deploy. The
  fallback is the safety net, not the fix.

## 2026-09-25 — v1.37.0 live smoke gate: 2 FAIL, both stale local defaults, no PR regression

`make smoke` (the canonical pre-PR live smoke gate; Claude runs it, never Gemini) reported
`0 passed, 2 failed`. Both were traced to stale assumptions in the gate itself, not to anything
this release changed.

**cluster-health** — `bin/smoke-test-cluster-health:27` defaults
`APP_CONTEXT="${APP_CONTEXT:-${INFRA_CONTEXT}}"` with the comment *"the hub is its own app
cluster"*. That premise is exactly what v1.37.0 deregistered. The hub's `shopping-cart-*`
namespaces are now empty by design, so the gate asserted 5 pods on `k3d-k3d-cluster` and found 0
while ArgoCD correctly reported all five apps `Synced`. Re-run pinned to the real app cluster:

    APP_CONTEXT=ubuntu-k3s bin/smoke-test-cluster-health   ->   9 passed, 0 failed

**webhook** — `GET /api/v1/health` with no query string calls `_smoke_test_services()` with no
arguments: the full sweep (endpoints x `_SMOKE_RETRIES=3` x 8s timeout + `_SMOKE_RETRY_SLEEP=10`,
then serial Vault/ESO/Kubernetes/login stages). `bin/smoke-test-webhook` caps it at
`--max-time 90`, so on a box where the `.local` endpoints are unreachable it cannot finish.
The code's own comment concedes the sweep "can legitimately take longer than a CLI status probe
should wait". **Identical on `origin/main`** (`_smoke_test_services()` bare, `quick` already
present) and `bin/smoke-test-webhook` is untouched since v1.16.0 (`4c5d3556`) -- so this is
pre-existing, NOT a decomposition regression. The bounded variant proves the module split:

    GET /api/v1/health?quick=1              ->  HTTP 200 in 0.43s
    GET /api/v1/health?quick=1&provider=...  ->  HTTP 200 in 0.26s

All 10 `scripts/lib/webhook/*.py` modules import cleanly; `bin/k3dm-webhook` compiles.
The `000000` in the failure line is a gate bug of its own: curl's `-w '%{http_code}'` prints
`000` and the `|| echo "000"` appends a second, masking the real error.

**The running webhook is pre-decomposition code.** PID 43834 started Thu Sep 24 08:52:55; every
decomposed module was written after it (agent 12:37, policy 13:52, status 14:59, lifecycle 15:21,
proc 18:32, make_targets 19:20). `make restart-webhook` is needed to exercise the split at
runtime -- a live host mutation, so it waits for the owner.

**PR runtime surface verified.** The Alertmanager warning-route fix is live and byte-identical to
the template on BOTH clusters -- route `[3] severity = warning -> platform-warning` sits after
`[2]` the named allowlist, which is the ordering the BATS gate asserts. The new
`bin/k3dm-alert-delivery-status` reads the operator-**generated** secret
(`alertmanager.yaml.gz`), so its `child_routes: 5` on the hub vs 4 in the user-supplied secret is
correct -- the generated config is a superset. Root receiver is still `null` on both clusters
(the known `CloudflareTunnelDown` -> `sms-critical` follow-up), but warning alerts are now
delivered via route [3] rather than silently dropped.

**Four findings the gate surfaced that are NOT v1.37.0 regressions:**

| finding | evidence |
|---|---|
| Prometheus probe unreachable by design | `smoke.py:525` probes app-cluster `localhost:19190`; no launchd agent forwards it. The hub agent forwards `19091:9090` per `com.k3d-manager.prometheus-port-forward.plist.tmpl:13`, and `19091/-/ready` returns 200. Main's own comment documents the two-port scheme, so this is a missing app-cluster PF, not a typo. `loadtest.sh:123` shares the 19190 assumption. |
| Keycloak probe targets a path that does not exist | probes `http://keycloak.shopping-cart.local/health/live` -> `127.0.0.1:80` (`/etc/hosts:13`); nothing listens on :80. Keycloak actually runs in namespace **`identity`** on the hub, not `keycloak`. |
| `keycloak-realm-reconcile` failing for 4 days | two pods in `Error` in `identity`; log ends `environment: line 104: awk: command not found`. The realm partial-import never completes. |
| MinIO still pulling the auth-gated quay image | `minio-0` `ImagePullBackOff` on `quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z`. The bitnamilegacy repoint is not in effect on `ubuntu-k3s`; the pending runtime proof is still unmet. |

**Gate/Slack gap (owner asked to close it next release):** `make smoke` exists
(`Makefile:797` -> `smoke_run`, `SMOKE_ONLY=offline|cluster`) but is **absent from
`MAKE_TARGETS`** in `scripts/lib/webhook/make_targets.py`, so there is no `/k3dm smoke`. Proposed
for v1.38.0: add `"smoke": {"min_role": "reader", "optional": ("SMOKE_ONLY",), "timeout": 900}`
plus a `SMOKE_ONLY` pattern `offline|cluster`, and fix the two stale gate defaults above so the
Slack surface cannot report a red that is really a local-default artifact.

## 2026-09-25 — four smoke findings filed as specs; implementation held for v1.38.0

Owner decision: commit the specs on `k3d-manager-v1.37.0` rather than hold them in scratchpad, so
they reach the v1.38.0 branch through the merge instead of needing a manual move. Only the **specs**
are on this branch — every fix they describe is v1.38.0 work and none of it is implemented here, so
the docs commit cannot affect v1.37.0's behaviour.

| spec | path |
|---|---|
| smoke cluster-health app context | `docs/bugs/2026-09-25-smoke-cluster-health-app-context-decoupled-from-app-prefix.md` |
| smoke webhook gate sweep + probes | `docs/bugs/2026-09-25-smoke-webhook-gate-unbounded-sweep-and-unreachable-probes.md` |
| Grafana ServiceMonitor label | `docs/bugs/2026-09-25-grafana-servicemonitor-missing-release-label.md` |
| Keycloak reconcile `awk` (work repo: shopping-cart-infra) | `docs/bugs/2026-09-25-keycloak-realm-reconcile-awk-missing-in-image.md` |
| `/k3dm smoke` exposure | `docs/plans/v1.39.0-slack-smoke-target.md` — 3 of max 5 for v1.38.0 |

`scratchpad/` and the stray 0-byte `.pub` are now in `.gitignore`. `scratchpad/` holds ~40 MB of
agent logs and had been untracked-but-ignorable only by luck; one `git add .` would have committed
all of it.

**v1.38.0 plan-doc count is 3, not 1** — `docs/plans/v1.40.0-hermes-app-health-delta-sensor.md` and
`docs/plans/v1.39.0-vector-store-platform-and-retrieval.md` already exist. Two slots left before the
cap forces a split.

### Correction to the 2026-09-25 smoke entry above

That entry said the cluster-health failure came from v1.37.0 "deregistering" the hub as its own app
cluster. **That was wrong.** The hub is still registered as an app cluster — it was *renamed*. Live:

| Secret | `name` | `server` | provider |
|---|---|---|---|
| `ubuntu-k3s-app-cluster` | `k3d-cluster` | `https://kubernetes.default.svc` | `k3d` (the hub) |
| `cluster-ubuntu-k3s` | `ubuntu-k3s` | `https://host.k3d.internal:6443` | `k3s-aws` |
| `cluster-ubuntu-hostinger` | `ubuntu-hostinger` | `https://2.25.146.252:6443` | `k3s-hostinger` |

The name `ubuntu-k3s` was re-pointed from the hub to the AWS cluster. All six
`ubuntu-k3s-shopping-cart-*` apps carry `destination.name: ubuntu-k3s`, so their pods live on the
remote AWS cluster while the gate's `APP_CONTEXT` defaults to the hub. The gate reads apps on one
cluster and pods on another — the exact defect
`docs/bugs/2026-09-13-smoke-test-cluster-health-pods-checked-on-wrong-cluster.md` closed, reintroduced
by a registration rename with **no code change**. Third iteration of a rotting hardcoded context
default, so the fix derives `APP_CONTEXT` from the checked Application's `destination.name`.

### Grafana ServiceMonitor — confirmed, not inferred

`kube-prometheus-stack-grafana` (hub) and `acg-kube-prometheus-stack-grafana` (hostinger) are the only
ServiceMonitors of eight on each cluster missing `release`, which
`serviceMonitorSelector: matchLabels: {release: …}` requires. Consequence measured on the hub
Prometheus: `up{job=~".*grafana.*"}` returns **0 series**, and **0 of 1740** metric names start with
`grafana_`. Grafana has never been scraped on either cluster. Cause: `grafana` is an upstream
*subchart*, so it renders its own ServiceMonitor from `grafana.serviceMonitor.labels` and does not
inherit the parent chart's `release` label; neither values file sets it.

### Keycloak realm-reconcile — 4d16h failure root-caused

`keycloak-realm-reconcile` in ns `identity` is `Failed 0/1`, two pods `Error`, `backoffLimit: 1`
exhausted. Log: `environment: line 104: awk: command not found`. The Job runs
`quay.io/keycloak/keycloak:24.0` (ubi9-micro), which has `bash`/`grep`/`sed`/`head`/`mktemp` but **no
`awk`** — the `grep -q` on the preceding line succeeds, which makes the failure look selective. The
embedded script needs `awk` in 11 places. The image cannot change (`kcadm.sh` only exists there), so
the fix rewrites the four CSV helpers plus seven inline pipelines in pure bash. `shopping-cart-identity`
is `OutOfSync` on the hub purely because this PostSync hook never completes.

Equivalence of the bash replacements was verified locally against the original `awk` for
`csv_value`, `csv_all_values`, `csv_match_count`, `csv_row_count`, `level0_rows`,
`csv_unexpected_top_names` and `urlencode_path`: **8/8 match**, with a deliberate negative control
correctly mismatching (so the comparison can fail).

### Probe targets measured

| target | result |
|---|---|
| `localhost:19090/-/ready` (hub) | `401` (basic-auth) |
| `localhost:19091/-/ready` (hub) | `200` |
| `localhost:19190/-/ready` (k3s-aws app cluster) | **unreachable** |
| `localhost:19200/-/ready` (hostinger app cluster) | **unreachable** |
| `keycloak.shopping-cart.local/realms/master` (non-hostinger branch) | **`000`** |
| `keycloak.3ai-talk.org/realms/master` (hostinger branch) | `200` |

No agent forwards the app-cluster Prometheus port, so the "Operator follow-up" item in
`docs/bugs/2026-09-14-prometheus-port-19090-hub-acg-collision.md` (`confirm lsof -iTCP:19190`) has
never been satisfied and `smoke.py:525` has failed since `31e69c56`. `keycloak.shopping-cart.local`
resolves to `127.0.0.1` via `/etc/hosts` with **nothing listening on :80**, and the hub has **no
Ingress resources at all** — Keycloak is reachable only via the `identity/keycloak` ClusterIP or
`identity/keycloak-nodeport` (:30080, also unforwarded). Each unreachable target burns
`3 x (8s timeout + 10s sleep)`, which is what pushes the sweep past the gate's own 90s cap.

### `/k3dm smoke`

`make smoke` exists (`Makefile:797`, `SMOKE_ONLY=offline|cluster`); `smoke` is absent from
`MAKE_TARGETS`, so only the Slack half is missing. Spec adds `{"min_role": "operator",
"optional": ("SMOKE_ONLY",), "timeout": 900}` plus a `SMOKE_ONLY` pattern. **Deliberately ordered
after both gate fixes** — exposing it first would post two false reds to Slack on every run.
`operator` rather than `reader` because the cluster half exercises live Vault/Keycloak/ArgoCD
credentials; a `reader`-level `SMOKE_ONLY=offline` would need per-argument role checks that
`parse_make_request` does not support.

## 2026-09-25 — SSM timeout root-caused: 28m50s agent credential backoff vs a 150s/300s wait

`ssm_wait` cannot succeed on a first-time ACG provision. The cause is a two-pass stack deploy
racing the SSM agent's credential-retry backoff, and it is deterministic, not flaky.

CloudFormation event timeline (stack `k3d-manager-cluster`):

| time (UTC) | event |
|---|---|
| 12:55:05 | stack CREATE_IN_PROGRESS — `EnableSsm` still **false** |
| 12:55:29-31 | all three instances launch with `IamInstanceProfile: AWS::NoValue` |
| 12:55:48 | ssm-agent starts, finds no EC2 role in IMDS (404), falls back to Default Host Management -> `AccessDeniedException: Systems Manager's instance management role is not configured for account` |
| 12:55:48 | `[CredentialRefresher] Sleeping for **28m50s** before retrying retrieve credentials` |
| 12:55:51 | stack CREATE_COMPLETE |
| 12:56:19 | stack UPDATE_IN_PROGRESS — `_provider_k3s_aws_enable_ssm_stack` flips `EnableSsm=true` |
| 12:56:43 | SSMInstanceRole CREATE_COMPLETE |
| 12:58:56 | SSMInstanceProfile CREATE_COMPLETE |
| 12:58:57-12:59:00 | instances UPDATE_COMPLETE — profile attached to **running** nodes |
| ~12:59-13:04 | `ssm_wait` polls 300s -> `did not become Online` -> `make up` exits 1 |
| 13:24:38 | `EC2RoleProvider Successfully connected with instance profile role credentials` — backoff expired, agent recovered unaided |
| 13:34 | all three `PingStatus: Online`, agent v3.3.4793.0 |

The profile landed at 12:58:57, **26 minutes before the agent would next look at IMDS.**
Everything else was correct and was ruled out: IGW route + `0.0.0.0/0` egress + public IPs, the
official Canonical jammy AMI with the snap agent enabled, `AmazonSSMManagedInstanceCore` attached
to `k3d-manager-cluster-ssm-role`, a valid `ec2.amazonaws.com` trust policy, IMDSv1 optional,
`NRestarts=0`. The agent was never broken — it was asleep.

`scripts/lib/providers/k3s-aws.sh:47` calls this attachment "with no interruption". That is the
false premise: no interruption is exactly why the agent keeps sleeping. Both waits are unreachable —
`_provider_k3s_aws_wait_ssm_registered` allows 150s, `ssm_wait` 300s, the agent needs ~1730s.

**A longer timeout is the wrong fix.** Either restart the agent over SSH right after the update
attaches the profile (`sudo systemctl restart snap.amazon-ssm-agent.amazon-ssm-agent.service`,
which resets the backoff and registers in seconds), or create the stack with `EnableSsm=true` in
the first pass so the profile exists at launch and the first credential fetch succeeds. The
second-run-passes behaviour is explained too: `_provider_k3s_aws_enable_ssm_stack` early-returns
when `EnableSsm` is already `true`, by which time the backoff has long expired.

Cluster left running (server 44.250.167.86, agents 16.146.71.239 / 44.247.114.156), SSM now Online,
so `make up` can be resumed rather than reprovisioned.

## 2026-09-25 — Hermes bootstrap path confirmed, plus template drift

`com.k3d-manager.hermes` is installed on disk but absent from both `launchctl list` and
`launchctl print-disabled` — enabled-but-never-bootstrapped, the identical failure mode as
`com.k3d-manager.cloudflare-tunnel`. The supported installer is **`bin/k3dm-hermes-setup`**
(delegates to `_install_hermes_agent` in the lib-foundation subtree; `--uninstall` to reverse).
Preflight is green: all four required Keychain credentials present (`k3dm-webhook-token`,
`k3dm-hermes-argocd-token`, `k3dm-hermes-gh-token`, `k3dm-slack-webhook`), both binaries
executable, `/opt/homebrew/bin/python3` resolves.

**Drift to decide before running it:** the installed plist sets
`K3DM_HERMES_AUTO_KINE_GUARD=1`, and `scripts/etc/launchd/com.k3d-manager.hermes.plist.tmpl`
does **not**. Re-rendering from the template therefore silently disables the one auto-executing
repair (`repairs.auto_remediate_kine`). Bootstrapping the existing plist as-is
(`launchctl bootstrap gui/<uid> ~/Library/LaunchAgents/com.k3d-manager.hermes.plist`) preserves it.
Either the template should carry the var or the guard was never meant to be on — owner's call.

## 2026-09-25 — acg-recover failed at SSM; tunnel killed again; CDP tab leak diagnosed

`make acg-recover` ran clean through chrome-cdp, acg-restart (CDP reused the logged-in session, no
manual login) and creds, provisioned the CloudFormation stack (server 44.250.167.86, agents
16.146.71.239 / 44.247.114.156), then **failed exit 2**: `[ssm] Instance i-04f4f6420ae76148c did not
become Online after 300s`.

**The failure cleanup killed the Cloudflare tunnel a second time** — same `cleaning up local
processes...` path as 02:44:58Z, ~3h after I restored it. Grafana was 530. Restored again
(`launchctl bootstrap`, pid 28226); grafana + argocd back to 200. This makes incident follow-up #2
(stop `cluster-up` cleanup unloading the public tunnel) a **reproduced** bug, not a hypothesis.

**CDP tab leak root cause — not a Playwright leak.**
`com.k3d-manager.chrome-cdp.plist` has `KeepAlive=true`. A relaunch into a profile/port another
Chrome already holds exits 0 immediately, so launchd respawns it, and each respawn opens one tab in
the live instance. Count grew 38 → 55 → 74 while observed. I closed 55 blank `chrome://newtab/`
targets over `/json/close`; they were replaced within minutes. **Closing tabs cannot win against the
producer** — the repair has to target the respawn loop. The plist's own comment already warns about
the port-reclaim hazard in `_cdp_stop_chrome_cdp_agent`.

**Correction to the 2026-09-25 outage entry:** "nothing watches the tunnel" was wrong at the Hermes
layer. `scripts/lib/hermes/sensors.py:107 reachability()` already shells out to
`bin/public-endpoint-probe --json` and has an explicit `edge-down` verdict. The reason it never
fired: `~/Library/LaunchAgents/com.k3d-manager.hermes.plist` exists (Sep 9) but is **not in
`launchctl list`** and not in `print-disabled` — the same enabled-but-not-bootstrapped failure as the
tunnel agent it would have reported on. The Prometheus half of that entry stands: still no blackbox
exporter and no PrometheusRule.

Hermes has no CDP/launchd sensor, and `repairs.propose()` proposes only — `auto_remediate_kine` is
the single auto-executing repair and is gated on `K3DM_HERMES_AUTO_KINE_GUARD=1`.

## 2026-09-25 — `make acg-recover` added (and a correction)

Chained the recovery into one target: `acg-recover: chrome-cdp acg-restart` + a recursive
`$(MAKE) K3DM_RESUME= --no-print-directory up`. Prerequisite ordering carries the sequence, matching
the existing `provision: ssm` precedent, which also keeps `make -n` safe to inspect.

**Correction to the previous entry:** the sequence I first gave (chrome-cdp → acg-restart →
argocd-registration) was wrong in its last step. `acg_restart` replaces the *Pluralsight sandbox
account* and its AWS credentials only — it does not provision EC2 or install k3s. At that point there
is no cluster to register. `bin/cluster-up` does both: Step 2 provisions, Step 10 registers with
ArgoCD. So the third step is `make up`, and `docs/howto/acg.md` now says so explicitly.

`K3DM_RESUME=` is forced empty deliberately: `cluster-up:201` clears `${_ACG_CHECKPOINT_DIR}` only
when `K3DM_RESUME != 1`, so an exported `K3DM_RESUME=1` would let a recovery skip "Step 2 —
Provisioning 3-node cluster" against a sandbox where nothing exists. Verified with a scratchpad probe
makefile (per [[reference_double_dollar_make_runs_help_and_emdash]], `make -n` executes `$(MAKE)`
lines, so a probe is the safe way to check): `$(MAKE)` expands to the real binary, the override wins
over an exported `K3DM_RESUME=1`, and `-n` propagates into the nested make.

## 2026-09-25 — `make acg-restart` added

`acg_restart` was the only ACG recovery function without a make target (`creds`, `chrome-cdp`,
`chrome-cdp-stop`, `provision` all had one), so the path you reach for when a sandbox has expired
was the one you had to spell out by hand. Added `acg-restart` to the Makefile (+ `.PHONY`, + `make
help`), passing `URL=` (defaults to the sandbox list page, already defined at `Makefile:14`) and
`PROVIDER=` (defaults to `aws` inside the function). Empty overrides are safe — `acg_restart` uses
`${1:-default}`/`${2:-aws}`, and `:-` catches the empty string, not just unset.

Documented in `docs/howto/acg.md` (new "4a. Recover an Expired Sandbox", between extend and
teardown) and `docs/howto/makefile.md` (Credential Extraction table + prose). `make
check-doc-links`: 1770 files OK. No BATS case — there is no existing test coverage for Makefile
targets to extend.

Still blocked: the sandbox at `34.218.59.16:6443` is down (`/readyz` times out, rc=124), and
`com.k3d-manager.chrome-cdp` is **not** in `launchctl list`, so `make acg-restart` needs
`make chrome-cdp` first. Both are operator-TTY work.

## 2026-09-25 — Cloudflare tunnel outage (restored) + the ACG sandbox is gone

Operator reported Cloudflare **1033** on `grafana.3ai-talk.org`. Cause: the third `make up`
failure at 02:44:58Z ran `cleaning up local processes...` and unloaded the
`com.k3d-manager.cloudflare-tunnel` LaunchAgent — the single ingress for all **7** public
hostnames, not just Grafana. Plist present and still *enabled*, just not bootstrapped, so
nothing retried it. Restored 12:16:51Z with `launchctl bootstrap gui/$(id -u)`; all 7 probes
now match their loopback status codes.

Also down for those 9.5h: both Alertmanager webhook receivers post to
`https://webhook.3ai-talk.org` (`k3dm-analyze`, `k3dm-cve-remediate`), so CVE auto-remediation
was dead — `notifications_failed_total{webhook,serverError}=95/142`, frozen at 95 on restore,
next remediation job 5s later.

**No alert fired because nothing watches the tunnel** — no blackbox exporter, no rule
referencing a public hostname/`probe_*`/tunnel. The text path itself is healthy
(`sms-critical` = email_configs, 19 sent / 0 failed). Note the root route receiver is `null`,
so a future rule needs an explicit route or it is silently dropped.

Filed `docs/issues/2026-09-25-cloudflare-tunnel-killed-by-make-up-cleanup-no-alert.md` with
three follow-ups, none started: add the probe + `CloudflareTunnelDown` rule; stop `cluster-up`
cleanup from unloading the public tunnel; fix the unhandled `RuntimeError` in
`bin/k3dm-webhook` `_create_cve_scan_job` on an already-existing job (raises out of `do_POST`
→ 500 → counted as serverError).

**The ACG sandbox is unreachable** — the `ubuntu-k3s` context points at `34.218.59.16:6443`
and now times out (it answered ~30m earlier). `make up` cannot be resumed and Tier 2
`make e2e-sandbox` stays blocked until the sandbox is restarted (needs the operator's TTY).

### Duplicate cluster name — FIXED and verified live
`ac3ebb82` renamed the hub self-registration to `k3d-cluster`
(`HUB_RECOVERY_HUB_CLUSTER_NAME` override); the live Secret `ubuntu-k3s-app-cluster` was
patched to match (backup: scratchpad `ubuntu-k3s-app-cluster.before.yaml`). All four AppSets
now report "All applications have been generated successfully"; the 8 previously-impossible
Applications exist (`ubuntu-k3s-data-layer`, the 6 services, `ubuntu-k3s-grafana-dashboards`),
and the hub's orphaned ESO is re-adopted by `k3d-cluster-eso`. The ACG-side apps are
`OutOfSync/Missing` only because the sandbox is unreachable.

## 2026-09-24 — ACG app tier blocked by a duplicate cluster name (owner decision needed)

`make up CLUSTER_PROVIDER=k3s-aws` failed at Step 10b/14 a third time. The label fix
`ffe954a1` landed correctly (`cluster-ubuntu-k3s` now `provider: k3s-aws`,
`shopping-cart: "true"`) but `ubuntu-k3s-data-layer` is still NotFound.

Cause: two cluster Secrets claim the name `ubuntu-k3s` — `cluster-ubuntu-k3s`
(`https://host.k3d.internal:6443`) and `ubuntu-k3s-app-cluster`
(`https://kubernetes.default.svc`, the hub registering itself, from
`hub_recovery.sh:252`, v1.33.0 `4b6ce874`). ArgoCD resolves `destination.name` globally, so
every name-keyed ApplicationSet is rejected with `ErrorOccurred` while
`ParametersGenerated` stays True: `data-git`, `services-git` (all 6 services) and
`grafana-dashboards-acg`. Sets addressing by `server` (`eso`, `platform-helm`) are fine.
`ubuntu-k3s-grafana-dashboards` was already `Unknown/Unknown` from this — it predates the
label fix.

Also found: the hub's ESO is **orphaned**. Both registrations generate the single
`ubuntu-k3s-eso` Application; the ACG one won, so its destination moved to
`host.k3d.internal` and the hub's 4d-old `external-secrets` deployments are managed by
nothing while still carrying the `ubuntu-k3s-eso` tracking id.

Filed `docs/bugs/2026-09-24-hub-self-registration-duplicate-cluster-name-blocks-name-keyed-appsets.md`
with three remedies (delete the Secret / rename it to a distinct cluster name / switch the
three sets to `server:`). All mutate a live registration Secret that four AppSets select on —
**blocked on the owner's decision**; option 2 is the only one that also re-adopts the hub's
ESO and is the only one carrying the preserveResourcesOnDeletion rename trap.

Tier 2 `make e2e-sandbox` stays blocked: Steps 10c-14 (Keycloak + LDAP identity) never ran.

## 2026-09-24 — ACG registration labels: the third instance of the same defect

`make up` cleared Step 4c after the listener fix, then failed at **Step 10b/14**: the data-layer
ArgoCD Application never Synced because it **was never generated**. `ubuntu-k3s-data-layer` does
not exist on the hub; `ubuntu-hostinger-data-layer` is Synced/Healthy beside it.

Cause: `bin/cluster-up:767` passed only `ARGOCD_APP_CLUSTER_TOKEN` to `register_app_cluster`, so
the defaults applied — `provider: unknown`, `shopping-cart: "false"`. `data-git` and
`services-git` select `shopping-cart: "true"`, so ubuntu-k3s was excluded and an ~8-minute wait
loop polled for an Application that could not appear. Steps 10c–14 (Keycloak + LDAP identity,
ClusterSecretStore, ACG observability) never ran.

**This is the same two labels as `2026-09-23-hostinger-registration-never-sets-provider-label.md`
and `2026-09-24-hostinger-registration-resets-shopping-cart-label.md`** — both fixed on the
hostinger caller only. `register_app_cluster` has two callers and its defaults are wrong for
both. Fixed by passing both labels (provider from the already-normalized `_cluster_provider`).
Gated in `cluster_up.bats` (12/12, mutation-proven). Filed
`docs/bugs/2026-09-24-cluster-up-registration-omits-provider-and-shopping-cart-labels.md`.

Three open items recorded there, none touched: (1) **two** cluster secrets exist for ubuntu-k3s —
`cluster-ubuntu-k3s` (provider `unknown`) and `ubuntu-k3s-app-cluster` (provider `k3d`) — and
`_istio_ambient_target_provider` returns whichever it hits first, so ambient CNI dirs depend on
iteration order and `k3d` would win with k3d-shaped paths on an AWS cluster; deleting a cluster
secret is load-bearing for ESO and four AppSets, so it needs the operator's call. (2) the Step 10b
error prints an empty `--context `. (3) the wait loop cannot tell "not yet Synced" from "will
never exist".

## 2026-09-24 — sandbox provisioned; cluster-up's listener guard fixed

`make up CLUSTER_PROVIDER=k3s-aws` brought the ACG sandbox up: CloudFormation stack created,
3 nodes `Ready` on v1.32.0+k3s1, `ubuntu-k3s` merged into `~/.kube/config`, `/readyz` = `ok`.
The Tier 2 kubecontext preflight added earlier today now passes.

The first attempt failed at **Step 4c/12** and so never ran Steps 5–14 (argocd-manager SA,
app-cluster registration, data layer, Keycloak + LDAP, ClusterSecretStore, ACG observability).
Cause was **not** the cluster: the ArgoCD browser HTTPS listener daemon had been running since
**Sep 4** (pid 29808, 20d elapsed) with the pre-`e259c718` wrapper text in memory, still naming
the legacy flat TLS dir (now empty). The run rewrote the wrapper with the provider-scoped path,
but the plist-unchanged `diff -q` short-circuit skipped the bootout/bootstrap, so the rewrite
never took effect and socat reported `No such file or directory` for certs that existed.

Operator ran `sudo launchctl kickstart -k system/com.k3d-manager.argocd-browser-https`
(not NOPASSWD in `/etc/sudoers.d/k3d-manager`, and needs a TTY). pid 29808 → 59280, healthz 200.
The resumed run cleared 4c and continued through Step 10b/14.

Fix in `bin/cluster-up`: hash the wrapper either side of the rewrite, and require
`_argocd_browser_wrapper_changed -eq 0` in the plist-unchanged guard. Gated by
`scripts/tests/bin/cluster_up.bats` (11/11; new test mutation-proven against
`HEAD:bin/cluster-up`). Filed
`docs/bugs/2026-09-24-argocd-browser-listener-not-restarted-on-wrapper-change.md`; corrected the
stale `OPEN — assigned to Codex` status on `2026-09-17-argocd-browser-tls-path-unification.md`,
which in fact landed in `e259c718` (v1.35.0).

Two WARNs from the resumed run still to deep-dive: `ARGOCD_APP_CLUSTER_PROVIDER unset —
registering ubuntu-k3s with provider 'unknown'` (substrate/ambient-CNI defaults fall back) and
`Could not detect host IP from host.docker.internal — CoreDNS host alias repair skipped`.

## 2026-09-24 — Tier 2 preflight gates on the sandbox kubecontext

First `make e2e-sandbox` run died three phases in on a bare kubectl
`context was not found for specified context: ubuntu-k3s`, **after** the ACG browser
extension step had already run. Tier 2 deploys *into* a cluster; it never provisioned one, and
nothing checked that the cluster existed.

Root cause is environmental, not a harness bug: `kubectl config get-contexts` holds only
`k3d-k3d-cluster` and `ubuntu-hostinger`. The one local sandbox kubeconfig,
`~/.kube/k3s-ubuntu.yaml` (Sep 4), was never merged as a context and its endpoint is dead —
probed it, `context deadline exceeded`. An ACG sandbox lasts 4h, so a 3-week-old sandbox
kubeconfig cannot be live. Unblocking Tier 2 needs `make up` on the k3s-aws default, which is
the operator's to run.

What was fixed in code: `_e2e_sandbox_preflight_cluster` now runs immediately after the
credential preflight and before the browser step, and distinguishes the two states — context
absent from the kubeconfig (never provisioned) vs context present but `/readyz` silent (left
over from an expired sandbox). Verified against the real kubeconfig: it fires with the absent
message and rc=1.

Lesson repeated a **third** time this release: `e2e.bats`'s "never invokes
register_app_cluster" test stubs private helpers from a by-name list, so the new preflight ran
real `kubectl` against the operator's clusters and the test went red. Fixed durably this time
rather than by adding one more name — `setup()` now installs a bare `kubectl` stub for the
whole suite, so any future code path that shells out to kubectl is offline by default. The
suite's one intentionally-real kubectl call uses `env kubectl`, which bypasses a shell function
and is therefore unaffected.

## 2026-09-24 — Tier 2 gets a make target and a Slack surface

Tier 1 has had `make e2e` since v1.26.0; Tier 2 (`e2e_verify_sandbox`) had no make entry point
at all and was dispatcher-only, which is why the PR #131 test-plan box reads as an ad-hoc
operator step. Added `make e2e-sandbox` (`DIGEST=` optional, passed through as the candidate
digest) next to `make e2e`, plus `.PHONY` and a `make help` line.

Also added `e2e-sandbox` to the Slack `/k3dm` allowlist as an `operator` target with an
optional `DIGEST` and a 3600s timeout — symmetric with `e2e-remote`. It deliberately does NOT
carry `confirm`, for the same reason `e2e-remote` does not.

Operational caveat worth remembering: a Slack-triggered Tier 2 run is unattended, so it can
only use an **already valid** ACG session. The preflight refuses
`K3DM_ACG_SKIP_SESSION_CHECK=1` and the interactive login needs a TTY, so a stale session
fails closed with `ACG_SESSION_EXPIRED` rather than hanging. Documented in
`docs/howto/slack-slash-commands.md`.

Gates: `make e2e-sandbox` dry-run (with and without `DIGEST`), `make help`,
`e2e_sandbox_preflight.bats` 15/15, `make test-python-unit` 7/7 suites OK,
`make check-doc-links` 1766 files OK. Both new assertions were mutation-proven — the allowlist
test raises `KeyError` with the `MAKE_TARGETS` row removed, and both Makefile greps are absent
from `HEAD:Makefile`.

## 2026-09-24 — PR #131 CI repair: two environment-dependent green tests

Both CI reds on #131 were tests that passed locally **because of the operator's environment**,
not because the code was correct. Same failure class, twice in one release:

1. `lint` / BATS — `scripts/tests/plugins/e2e.bats` stubbed `security` as a shell *function*,
   invisible to `_secret_load_data` because that loader runs `security` inside `bash -c`. On
   macOS the test therefore read the **real** `k3dm-acg-pluralsight` credential; on Linux CI
   there is no `security` binary, so the preflight refused. Fixed in `9a649af3` with a fake
   `security` executable on PATH plus a pinned `_is_mac`. Mutation-gated.
2. `lint` / pytest — `scripts/tests/hermes/test_hermes.py` stubs sensors from an explicit
   tuple, and v1.37.0's `03b875c5` added `alert_delivery` to `_run_cycle` without extending
   it (**two** stub sites, lines 56 and 98). The real sensor ran and shelled out to
   `bin/k3dm-alert-delivery-status --json` with a 60s timeout — live `kubectl` on every local
   `make test-pytest`. Locally the probe succeeded → green; on CI it raised → `unknown` → seven
   40-minute polls tripped the 30+ min unknown page → `pages == []` failed. Fixed in
   `444aea0c`. Reproduced pre-fix with `env PATH="/usr/bin:/bin"` (0.30s vs 17.82s — the
   timing gap is the tell), 189 passed post-fix.

**Standing lesson:** a stub list enumerated by name silently leaks every sensor added later.
A third sensor will escape the same way — worth a gate that derives the list from
`_run_cycle` rather than restating it.

**CodEQL alerts 23/24/26/27** (`py/path-injection` + `py/command-line-injection`, 2 critical,
at `proc.py:38` and `bin/k3dm-webhook:991`) analysed and documented in
`docs/issues/2026-09-24-codeql-pr131-spawn-injection-false-positives.md` (`d482fc47`), with an
in-code `# codeql[...]` marker at each sink and the conditions that would make them real again.
Verdict: real dataflow, not exploitable — `cmd[0]` is a literal at every call site, the `cwd`
branch pins the executable to `/bin/bash`, and request-derived argv passes anchored
metacharacter-free `fullmatch` patterns before `shlex.quote`. Surfaced by the module extraction,
not introduced by it. All four dismissed by the operator 01:37 (the classifier denied it to Claude).

**Correction — alert 25 is NOT main's 22 relocated.** Main's 22 is a different sink
(`k3dm-hermes:469`, the preflight print). 25 is genuinely new to v1.37.0: main carries the *same*
sink at `:443` unflagged, and this release's `alert_delivery` sensor added
`configSecret {config_secret}` to the printed records. `config_secret` is a Secret **name** from
`.spec.configSecret`; the probe only tests that the Secret exists (`>/dev/null`) and never reads
its contents, so CodeQL fired on the identifier *name*. Still a false positive — but a
name-based-heuristic one that will re-fire on any future `*_secret` field holding a reference
rather than a value. The earlier error came from matching on rule id + file instead of the sink.

**Alert 25 alone fails the CodeQL check** ("1 new alert including 1 high severity" after the four
were dismissed), so dismissing the injection alerts did NOT clear the gate. Open decision:
dismiss 25 as well, rename the field so the heuristic stops firing, or merge via the
`enforce_admins` window.

**The API dismissal of 23/24/26/27 is NOT done** — `gh api ... code-scanning/alerts` was denied
by the auto-mode classifier as a CI bypass. The operator must run it from their own terminal.
GitHub does not honour the in-code `codeql[...]` comments as dismissals, so the alerts stand
until that runs. `enforce_admins` still untouched.

## 2026-09-24 — v1.37.0 PR #131 opened; lib-foundation PR #56 opened

**k3d-manager PR #131** (`k3d-manager-v1.37.0` → `main`, head `4376a6ec`, 90 commits). Copilot
requested; CI was still running at handoff, so the PR gates are **not** complete and
`enforce_admins` has **not** been touched.

Release doc prep landed in `4376a6ec` after the pre-flight found four gaps — worth recording
because each was a silent omission, not a judgement call:

- CHANGELOG carried only `[Unreleased]` on a *milestone* branch. Four landed changes were
  unrecorded: the Tier 2 readability rewire, the v0.4.18 subtree pull, the `PLAYWRIGHT_AUTH_DIR`
  drift and the empty-`mktemp` derived-path fix with its `check-repo-root` gate. Added, then
  promoted to `## [1.37.0] - 2026-09-24` with `[Unreleased]` kept empty above it.
- README releases table and `docs/releases.md` had no v1.37.0 row; v1.34.0 demoted into the
  `<details>` block to hold the table at three.
- `docs/api/functions.md` was missing **both** public functions this release adds —
  `app_cve_scan_trigger` and `argocd_reconcile_app_cluster_registrations`.
- The harness guide's ACG marker table listed two `path=` values. `acg_session_check.js` emits
  **three**: `manual-login` at line 120, reachable when `K3DM_NONINTERACTIVE` is unset and stdout
  is a TTY. A reader treating the table as exhaustive would misread a real marker.

**lib-foundation PR #56** (`docs/v0.4.18-retrospective` → `main`), CI 3/3 green, three Copilot
threads fixed and resolved. Copilot found the *same* `manual-login` omission upstream, plus a
fabricated `path=pluralsight_login` in the retro — a value emitted nowhere, which a consumer
keying off it would never match. Verified against the source before accepting each finding
(`path=` is emitted only at lines 83, 98, 120). Fixes in `78eacbe2`; `CHANGE.md` entry `1077361`.

Note for anyone writing a `path=`-matching gate: **accept `auto-login` alone** when the claim is
that *unattended* login works. `manual-login` means a human signed in during the run, and
`existing-session` means none was attempted — either would make a broken auto-login look green,
which is the exact failure the `path=` suffix was added to expose.

lib-foundation `main` is **ruleset-protected** (`deletion`, `non_fast_forward`,
`copilot_code_review`) — `branches/main/protection` 404s by design, there is no `enforce_admins`
lever and no required-approvals gate, so `/create-pr` step 7 does not apply to PR #56. It applies
to PR #131 and is still pending CI.


## 2026-09-24 — Tier 2 preflight rewired to the real credential loader (v1.37.0)

Subtree pull of lib-foundation v0.4.18 landed in `7d786cd0` (squash `c027fe07`), range
`023f76e5..2f244ee4`. **The subtree prefix is `scripts/lib/foundation`, not `scripts/lib/acg`** —
the acg module is nested at `scripts/lib/foundation/scripts/lib/acg`. Verified by tree hash:
`git rev-parse HEAD:scripts/lib/foundation` == `git rev-parse origin/main^{tree}` upstream ==
`8b2f7956f7d9e4baf68f2c883c60b08191f56c0f`.

`_e2e_sandbox_preflight_auth` (`scripts/plugins/e2e.sh:294`) rewired in `a4d6ef53`. It called
`security find-generic-password` with no `-w` — an existence check that **succeeds when the login
keychain is locked and when the value was stored empty**, the two states that actually break
unattended login. It now calls `_secret_load_data` (the same loader `_cdp_ensure_acg_session`
uses), discards the value to `/dev/null`, and on success exports
`K3DM_ACG_REQUIRE_CREDENTIALS=1` so the session check fails closed rather than coasting on a
human's leftover browser session. The `K3DM_ACG_SKIP_SESSION_CHECK` guard moved above the reads,
so a refused run touches the keychain zero times.

BATS `scripts/tests/plugins/e2e_sandbox_preflight.bats`: 14 tests, mutation-gated — against the
previous implementation exactly 5 fail (locked keychain, empty value, locked-with-profile-dir, and
the two export assertions) and the 9 pre-existing-behavior tests stay green. The suite installs a
fake `security` executable on `PATH`; a shell-function stub is invisible to `_secret_load_data`
because it runs `security` inside `bash -c`.

Gates: `shellcheck -x` clean. `make test` plan `1..1119`, 1115 ok / 4 not ok / 10 skipped / no
index gaps. **The 4 reds were all in `e2e_remote.bats` and were caused by unpushed local
commits** — `e2e_runner_dispatch` verifies the SHA is on origin before reaching the stubbed
preflight. Re-ran that suite after pushing: 80/80 green. Not a regression.

Docs updated in the same commit: `docs/guides/vcluster-e2e-harness.md` gained the
existence-vs-readability table, the fail-closed gate and the full marker list.

**Doc gap found in the shipped release:** v0.4.18 documented neither
`K3DM_ACG_REQUIRE_CREDENTIALS`, the `ACG_SESSION_OK path=` suffix, nor the `ACG_CREDENTIALS*`
markers in lib-foundation `README.md` / `docs/api/acg.md`. Fixed upstream in `452d149` on
`docs/v0.4.18-retrospective` — after the tag and release were already cut, so it lands as a
follow-up. The release gate let it through.

Still open: the `_robustClick` dedup across `sandbox.js` / `acg_restart.js` (needs a live sandbox —
`sandbox.js` swallows errors with `.catch(() => {})` and `acg_restart.js` does not). The
lib-foundation `docs/v0.4.18-retrospective` branch carries two unmerged commits (`d968af5` retro,
`452d149` docs) with no PR yet.

## 2026-09-24 — upstream: lib-foundation v0.4.18 merged, tagged, released

PR #55 merged to main (`2f244ee4`); tag v0.4.18 pushed; GitHub release created at
`https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.18`. Retrospective
committed to `docs/v0.4.18-retrospective` branch at `d968af5` and pushed.

No `enforce_admins` step applied — lib-foundation `main` is ruleset-protected (`deletion`,
`non_fast_forward`, `copilot_code_review`) with no required-approvals gate; classic
protection endpoint returns 404 by design and there is no admin lever to restore.

**Still pending:** subtree pull of lib-foundation v0.4.18 into `scripts/lib/acg/`,
then rewiring the Tier 2 preflight in `scripts/plugins/e2e.sh` from Keychain-existence
check to the real loader / `K3DM_ACG_REQUIRE_CREDENTIALS`. Also deferred: `_robustClick`
dedup across `sandbox.js` and `acg_restart.js` (needs live sandbox to verify the
`catch()` behavior difference does not break the provisioning path).

## 2026-09-24 — upstream: lib-foundation v0.4.18 PR #55 opened, merge-ready

`https://github.com/wilddog64/lib-foundation/pull/55` — one PR covering both the approved
credential-test observability scope and the headless Pluralsight auto-login fix it exposed.
Head `8986227`, `mergeable_state: clean`.

Pre-PR: promoted `CHANGE.md` `[Unreleased]` to `[v0.4.18] — 2026-09-24` in `15bf3b7`, matching
the v0.4.17 convention (empty `[Unreleased]` kept above the version heading).

Gates, all measured here and not taken from any agent: `npm run check` clean; jest 7 suites /
**40** tests; `make bats` plan `1..138` with 138 ok, 0 not ok, 0 skips, no index gaps; CI green
per-job (`shellcheck`, `bats`, `acg (node)`) on head SHA `8986227`, verified from the job list
rather than the run conclusion.

Copilot posted 4 distinct findings across 5 comments, all replied to and all 5 threads resolved
(0 unresolved). Two were real and fixed in `8986227`: `_robustClick` inherited Playwright's 30s
default instead of the module's `FIELD_TIMEOUT_MS`, and the bug doc repeated its whole `Outcome`
section (lines 457-500 were a byte-exact duplicate of 381-424, confirmed with `diff`). The three
env-leakage findings on `acg_session_check.test.js` are **false positives** — that describe block
already reassigns `process.env` from a snapshot in `beforeEach` and restores the original object
in `afterAll`. Copilot's own note says it ran at Lite effort and could not complete its agentic
suite. The timeout fix was mutation-gated: reverting the wait left exactly the new test red
(1 failed / 39 passed).

No `enforce_admins` step applies — lib-foundation `main` is ruleset-protected (`deletion`,
`non_fast_forward`, `copilot_code_review`) with no required-approvals gate, so classic
protection returns 404 by design and there is no admin lever to disable.

**Awaiting the operator's merge.** Not done and deliberately not started: merge, the `v0.4.18`
tag, the GitHub release, the subtree pull into k3d-manager, and rewiring the Tier 2 preflight in
`scripts/plugins/e2e.sh` from Keychain-existence to the real loader /
`K3DM_ACG_REQUIRE_CREDENTIALS`.

## 2026-09-24 — unknown actor role authorization fix (working tree; commit pending)

Implemented the scoped policy fix from
`docs/bugs/2026-09-24-normalize-role-defaults-unknown-actor-to-admin.md`: added and exported
`_normalize_actor_role` with an unknown→reader default, used it only for the actual side of
`_role_allows` and the audit role field, and left `_normalize_role` and `strictest_role`
unchanged. Updated the two fix-mode rows, six direct policy guards, the architecture note,
changelog, and bug status. No Phase 4 work or live webhook/cluster/browser operation ran.

Focused pytest: policy 13 passed, agent 7 passed, make-targets 14 passed; webhook BATS 64/64;
bare pytest 189 passed; `make check-doc-links` 1765 files OK; `make check-repo-root` passed;
server import under `/opt/homebrew/bin/python3` printed `OK`; `_agent_audit` exit 0. `make
test-all` completed BATS plans `1..1112` and `1..132`, unittest suites `7 / 14 / 13 / 6 / 6`,
then exited 2 because Homebrew Python 3.14.7 has no pytest, as expected. M1–M5 each produced
the required red guard output and was restored with `git diff --quiet`. Commit/push pending.

## 2026-09-24 — webhook Phase 3 agent extraction

Phase 3 is implemented in the working tree on `k3d-manager-v1.37.0`: the seven agent
functions and three regex gates now live in `scripts/lib/webhook/agent.py`; the entrypoint
imports only `_call_gemini`, `_run_cluster_ask`, and `_sanitize_question`, which it still
calls. Added direct real-function security tests in `scripts/tests/bin/webhook_agent.py`.
The unknown-role matrix is intentionally pinned to the observed `True`/`True` behavior with
the existing bug-doc pointer; no policy behavior was changed. The existing webhook BATS
assertions for the moved code were repointed to the new module.

Focused pytest: 7 passed; webhook BATS: 64/64; full pytest: 189 passed; doc links: 1764
files OK; check-repo-root: 0; server import: `OK`; `_agent_audit`: 0; `bin/k3dm-webhook`
measured 3409 -> 2957 lines. `make test-all` completed the `1..1112` and `1..132` BATS
plans, with unittest suites 7 / 14 / 7 / 6 / 6 passing, then exited 2 only because Homebrew
Python 3.14.7 has no pytest. The six required mutations each turned the named guard red and
were restored. No live webhook, cluster, or AI CLI call was made.

Commit and push are blocked by the sandbox's `.git/index.lock: Operation not permitted`
wall. No lock removal, retry, `--no-verify`, force-push, or PR was attempted; the scoped
changes are staged for the operator to commit and push.

## 2026-09-24 — upstream: credential-test observability dispatched to Codex

`make credential-test` was treated as proof that ACG auto-login works, but it cannot be: the marker
`ACG_SESSION_OK` is emitted from four places — existing session, headless auto-login, manual TTY
login, and a fourth in `acg_pluralsight_login.js` — all identical. The existing-session branch
short-circuits before credentials are ever read, which is exactly why the absent Keychain item read
as "auto-login was never wired" for weeks.

Specced upstream in lib-foundation (`d695f81`, branch `feat/v0.4.18-credential-test-observability`)
because the target is the `scripts/lib/acg/` subtree and must never be edited here. Three changes:
`path=` on all four markers; an always-emitted `ACG_CREDENTIALS: username=<state> password=<state>`
on stderr using absent/empty/present only; and `K3DM_ACG_REQUIRE_CREDENTIALS=1` to fail an unusable
store even when the session is live, under its own marker rather than `ACG_SESSION_EXPIRED`.

Forcing a login while already authenticated was deliberately excluded — it invites the new-device
MFA challenge the module refuses by design. Codex is forbidden from running any browser or
`credential-test`; the operator owns the live gate. Baseline measured before dispatch: jest 7 suites
/ 28 tests green, and the bare-marker disappearance gate finds exactly 4.

Follow-on once merged upstream: subtree pull into k3d-manager, then the Tier 2 preflight can call the
real loader instead of checking Keychain existence.

## 2026-09-24 — ACG preflight: service-only Keychain check was not predictive

The Tier 2 preflight matched `security find-generic-password -s k3dm-acg-pluralsight` with
no `-a`, so **any** account under that service satisfied the gate. `_secret_load_data`
(`scripts/lib/foundation/scripts/lib/system.sh:579`) resolves to `-s <service> -a <key> -w`,
so the loader only ever reads the accounts `username` and `password`; an entry under `-a k3dm`
— the convention every other item in the repo uses — is never read. The gate would have gone
green and Tier 2 would have failed later at the session check instead of failing fast.

Found while the operator hit `User interaction is not allowed` populating the item. Claude had
handed them `-a k3dm`, which was wrong; the account name is the field name here. Fixed: the
preflight loops both accounts and names which are missing. 10/10 focused BATS, mutation-verified
(reverting to the service-only form reds exactly the three new cases), shellcheck clean, doc
links 1765 OK. The no-`-w` invariant is deliberately preserved — an empty-value check would
require the guard to handle secret material, and `acg_session_check.js:19,62,66` already treat
an empty credential as absent.

Two environment traps are now documented in `docs/guides/vcluster-e2e-harness.md`: the
GUI-session requirement behind `User interaction is not allowed` (prior art:
`docs/issues/2026-09-16-status-webhook-health-timeout.md`), and that a bare `-w` in a non-TTY
shell **silently stores an empty value and exits 0**, which is indistinguishable from an absent
item downstream. Keychain state measured 2026-09-24: all three accounts absent — the operator's
earlier attempts never landed, so there is nothing to clean up. Population remains blocked
until they are at the Mac in Terminal.app.

## 2026-09-24 — Tier 2 ACG preflight

Task 0 is resolved as **Path A**: the operator's personal ACG account has no MFA.
Task 1/3 implementation is complete in the working tree on `k3d-manager-v1.37.0`; the
preflight checks the sandbox URL, Keychain service existence without `-w`, and refuses
`K3DM_ACG_SKIP_SESSION_CHECK=1`. The existing Tier 2 guide was extended. Focused preflight
BATS is 6/6, existing E2E BATS is 49/49, shellcheck is clean before/after (0/0), and doc
links pass (1764 files). `make test-all` completed its 1..1111 BATS plan plus 132 additional
BATS cases and the Python unit suites, then exited 2 only because Homebrew Python 3.14.7 has
no pytest. The foundation subtree and live ACG/browser paths remain untouched. Git staging is
blocked by `.git/index.lock: Operation not permitted`; no commit SHA exists.

## 2026-09-24 — webhook Phase 1b implemented; commit blocked by sandbox

Implemented the Phase 1b route-table authorization change in the five requested files:
`strictest_role` defaults closed, `effective_policy` combines the table floor with dynamic
policy, POST checks and audits exactly once, and `/cluster` plus `/make` carry `dynamic`
descriptions without changing their reader floors. Focused pytest: **7 passed**; webhook BATS:
**64/64**; bare pytest: **189 passed**; `make check-doc-links`: **1762 file(s) OK**;
`_agent_audit`: **0**. M1–M6 all turned their named tests red and were restored with a clean
unstaged diff after each mutation. `make test-all` was attempted; the first run hit the
sandbox's restricted macOS `/var/folders` temp root, and the mandated import command hit the
existing `/usr/bin/python3` 3.9.6 incompatibility with `str | None`. No live webhook or cluster
operation ran. The exact implementation commit was blocked by `.git/index.lock: Operation not
permitted`; changes remain staged. Untracked `.join-failures.*`, `.pub`, and operator-owned
`scratchpad/` were left untouched.

## 2026-09-24 — webhook Phase 1 implementation blocked at git write

Implemented Phase 1 in the working tree: moved the named authz/policy functions into
`scripts/lib/webhook/policy.py`, added explicit `_POST_ROUTES`/`_GET_ROUTES` metadata,
repointed tests that imported moved names, and added route completeness/effective-policy
equality tests. The fail-open `if action_policy:` branch remains unchanged and is documented.
The four required mutations all turned their named tests red and were restored cleanly.

Measured: `bin/k3dm-webhook` 4010 lines before, 3929 after; bare pytest 189 passed;
focused BATS 64/64; Python collections 14/6/6/14 plus 2 new policy cases. `make test-all`
was rerun and reached 1105 dispatcher cases, but the pre-existing `cluster_status_summary.bats`
JSON case failed because its fixture supplies two failed services while it asserts one; the
system `python3` also lacks pytest (pyenv-shimmed `make test-python` passed 184). `make
check-doc-links` passed with 1762 files. No server, cluster, or live webhook operation ran.

No commit SHA exists: the sandbox rejects `.git/index.lock`, `.git/COMMIT_EDITMSG`, and Git
temporary tree objects with `Operation not permitted`; push is therefore blocked. User-owned
untracked `scratchpad/` was left untouched.

## 2026-09-24 — app-CVE scan trigger target

Implemented S1–S3 of `docs/plans/v1.37.0-app-cve-scan-make-target-and-k3dm.md`: the
operator-only `make app-cve-scan` trigger, enumerated `CRONJOB` Slack argument, focused
tests, and required guide/design/changelog documentation. The remediation ConfigMap selector
was measured in `scripts/etc/argocd/platform-ops/app-cve-scan.sh` as
`k3dm.k3d.io/cve-remediation-event=true`, which differs from the spec's guessed
`k3dm.k3.io/remediation=promotion_requested`; the payload file was left untouched. Focused
BATS: 6/6 and 2/2; focused pytest: 14 passed; whole pytest: 189 passed; doc links: 1762
files OK. All six mutations turned their named tests red and were restored. `make test`
completed 1105 tests but retained five unrelated pre-existing `e2e_remote.bats` failures
(688, 699, 723, 724; 724 is the chained failure; exact output is in the session log); no
live-cluster commands were run. Commit/push is blocked by `.git/index.lock: Operation not
permitted`; no commit SHA exists yet.

## 2026-09-24 — Hostinger shopping-cart label and CVE promotion guard fixed

Implemented in commit `f8a7e1189dadbd43c6c4ff9186a15e2dcbe7869c` (final commit; pushed): Hostinger registration now defaults
`ARGOCD_APP_CLUSTER_SHOPPING_CART` to `true` while preserving explicit overrides; app-cve-scan
records a failed promotion in `_rc` and continues when an ArgoCD Application is missing, without
emitting a false remediation event. Focused BATS: 9/9; full `make test`: 1096/1096; pytest:
184 passed; doc links: 1760 files OK; no live-cluster commands were run. The initial pull was
blocked by the sandbox's `.git/FETCH_HEAD` restriction. User-owned untracked `scratchpad/` was
left untouched.

## 2026-09-23 — Alert delivery and ambient CNI precedence fixes completed

Implemented and pushed the two requested bug specs on `k3d-manager-v1.37.0` as separate commits:
`03b8755caad4b698c4ecdc9bfbd53b21cbf91e1` adds the warning catch-all, missing-configSecret
delivery guard, read-only probe, Hermes sensor, tests and alert-delivery docs; `02e3fa769e002ba5757e5eb267ab02e1c7f192ad` makes target-substrate CNI dirs win over stale live
ApplicationSet values, adds the k3s generic-path refusal guard, tests and ambient guide. Both are
on origin. No PR was created, and no live-cluster commands were run.

The required pre-existing logging assertion was updated in follow-up `d2c6177fbadaf44729fcd09fc7c575c38c6f268` because the full suite still expected the intentionally removed `keeping live` wording. The corrected full suite is green.

## 2026-09-23 — Hostinger app-cluster registration: durability spec dispatched to Codex

Filed `docs/bugs/2026-09-23-hostinger-registration-does-not-survive-a-hub-rebuild.md` and
dispatched it. Two hub rebuilds (2026-09-11, 2026-09-20) dropped `cicd/cluster-ubuntu-hostinger`
because both rebuild paths — `bin/cluster-up:759` and `hub_recovery.sh:252` — register exactly one
cluster and enumerate no others, and `bin/cluster-status:233` only checked
`cluster-${APP_CONTEXT}`, so `make status` printed `Registered` while hostinger was orphaned. The
spec adds `scripts/etc/argocd/app-clusters.tsv` as the single declaration,
`argocd_reconcile_app_cluster_registrations` (additive-only, never aborts the rebuild, invokes the
dispatcher as a child process so no provider file is sourced mid-rebuild), calls from both rebuild
paths, and a `REGISTRATION GAP` line in `make status`. Three mutations are required.

Correction worth keeping: the registration-only entry point already exists as
`make refresh-registration CLUSTER_PROVIDER=k3s-hostinger` (`14f26f3d`). The reopened 2026-09-13
doc still claimed otherwise, and that stale line was repeated in session reporting. Item 1 is a
single operator command, not development work.

## 2026-09-23 — Hostinger app-cluster registration durability implemented

Implemented and pushed as `1238f994` on `k3d-manager-v1.37.0`. Added the single-row remote app-
cluster inventory, additive reconcile function, calls from both hub rebuild paths, and direct TSV
registration-gap reporting in `cluster-status`, plus focused BATS coverage and the operator guide.
The implementation invokes `refresh_registration` as a child dispatcher process and returns zero
when a remote re-registration fails, leaving the warning banner and status line as the signal.

Verification: focused suites 47/47; `make test` 1068/1068; shellcheck warning counts matched
`HEAD~` exactly (`argocd.sh` 1, `hub_recovery.sh` 0, `cluster-up` 18, `cluster-status` 0);
`make check-doc-links` 1751 files OK. M1, M2, and M3 each turned the required test red and
were restored. The initial pull was blocked by the sandbox's `.git/FETCH_HEAD` restriction; no
live cluster commands were run.

## 2026-09-23 — Alertmanager warning alerts now have an explicit delivery route

Implemented and committed as `a7135966` on `k3d-manager-v1.37.0`; status update pushed in
`683a8ac7`. Added the
`platform-warning` email receiver using `${ALERTMANAGER_GMAIL_FROM}`, appended the five-name
warning allowlist at `.route.routes[2]` after `severity = critical`, added the Alerting guide
and README/CHANGELOG entries, and added three BATS guards. Focused BATS is 7/7; `make test`
is 1061/1061; `make check-doc-links` reports 1749 files OK; shellcheck is clean; YAML parses.
Each required mutation turned its corresponding guard red and was restored byte-for-byte.
The initial `git pull origin k3d-manager-v1.37.0` was blocked because the sandbox cannot write
`.git/FETCH_HEAD`; no live cluster commands were run.

## 2026-09-23 — M2 GHCR blocker root-caused: locked keychain, not a bad token

**Status: stdin token-forwarding fix IMPLEMENTED and VERIFIED.** Spec:
`docs/bugs/2026-09-23-e2e-dispatch-forward-ghcr-token-over-stdin.md`. Codex wrote the source
and tests but hit the known `.git/index.lock` `Operation not permitted` write-wall, so Claude
committed and pushed on its behalf.

Independently verified, not taken on report: diff scope is the two scoped files only;
`shellcheck scripts/plugins/e2e_remote.sh` clean; `e2e_remote.bats` 79/79 with 0 `not ok`;
and the PIPESTATUS guard mutation-tested by Claude directly — flipping the token branch to
`PIPESTATUS[0]` makes test 27 fail (`status -eq 7` unmet), restoring `PIPESTATUS[1]` makes it
pass, and the restored file is byte-identical to pre-mutation.

**Not yet exercised against the live runner.** The fix is proven by unit test only; no
dispatch has been run, because the vCluster leak still wedges the M2.

**The finding.** The operator challenged my host attribution ("I think you are running from
m4"), which was worth making: `ssh m2jump` does resolve to `m2-air.local`, but the challenge
exposed that my probes and their console read disagreed because of **session type**, not host.
`gh` on M2 keeps its token in the macOS keyring. The operator's console session has an
unlocked login keychain and reads it fine. A non-interactive SSH session cannot unlock it and
cannot prompt, so `gh auth token` returns empty and `gh auth status` says "invalid" — the
locked-login-keychain trap, which looks exactly like a deleted token. The credential was never
broken.

**Because `e2e_runner_dispatch` runs over SSH, re-logging in on M2 can never fix this.** The
August remediation (`gh auth refresh -s read:packages` on M2) is retracted as never-viable,
not merely regressed.

**The fix.** The M4 already holds a token with `read:packages`. Forward it to the runner over
stdin at dispatch time. `shopping_cart_load_ghcr_pat_from_env` is already first in
`shopping_cart_resolve_ghcr_pat`'s chain, so `shopping_cart.sh` needs no change — the dispatch
only has to set `GHCR_PAT`. Nothing minted, nothing persisted on the runner, and the token
stays out of argv and out of the tee'd transcript.

**Rejected:** committing `hosts.yml` (publishes a plaintext credential, and holds no token
today anyway); plaintext `gh` storage on the runner (long-lived token at rest);
`security unlock-keychain` in the dispatch (needs the login password non-interactively).

**Two corrections to my own earlier reporting, recorded so they are not re-derived:**
1. My "this is not the locked-keychain trap" claim came from a test that folded stderr into
   the variable, so an error string read as a token. It is the trap.
2. `gh` being absent from `command -v` on a BatchMode shell affected only my manual probes.
   The dispatch is fine — `E2E_M2_REMOTE_PATH` (`e2e_remote.sh:31`) already prepends
   `/opt/homebrew/bin`. Not a defect; do not file it.

**Still blocking Tier 1 after this fix lands:** the leaked vCluster wedge
(`2026-09-23-e2e-failed-run-leaks-vcluster-and-wedges-all-later-runs.md`, fix options 1 and 3).
**Hermes stays booted out** until both are fixed — every dispatch currently leaks a vCluster.

## 2026-09-23 — Tier 1 e2e: wedged for 2h by a leaked vCluster; Tier 2 still blocked

**Operator asked for Tier 1 then Tier 2. Tier 1 ran twice and failed both times; Tier 2 never
started.** Neither failure was a shopping-cart regression.

**Hermes is currently BOOTED OUT — `launchctl bootstrap gui/$(id -u)
~/Library/LaunchAgents/com.k3d-manager.hermes.plist` to restore it.** Paused with the
operator's approval so its 300s loop could not race the run. **Do not restore it until the
GHCR credential is fixed** — every dispatch now leaks a vCluster, so an unattended Hermes
re-wedges the runner within minutes.

**Blocker 1 — leaked vCluster wedges everything.** A run at 09:04Z failed at
`deploying-substrate` and left `e2e-1790154235-20` Running. vCluster 0.32.1 refuses a second
vCluster in the shared `vclusters` namespace, so every later run died in ~15s. Hermes burned
~17 dispatches between 03:19 and 04:14 local. Cleared both that orphan and the one my own
rerun leaked. Filed:
`docs/bugs/2026-09-23-e2e-failed-run-leaks-vcluster-and-wedges-all-later-runs.md`.
**Confirmed the leak reproduces** — the next run leaked too, so teardown-on-failure is
required, not just cleanup.

**Blocker 2 — the runner cannot get a GHCR PAT. NOT a new bug.** This is Gap 3 of
`docs/bugs/2026-08-22-e2e-m2-runner-bootstrap-kubeconfig-and-ghcr-gaps.md` regressed; recorded
there, not as a duplicate. The Vault path hardcodes `--context k3d-k3d-cluster`
(`shopping_cart.sh:321`) and is dead off-hub by construction; the `gh` fallback now bails
because **m2jump's gh token is invalid** (`shopping_cart.sh:366`). `e2e_remote.sh:430-438`
forwards no `GHCR_PAT`, so the error message's own advice is unreachable.

**Correcting a note in this file.** The 2026-09-22 "Tier 1 credential gate cleared
(`read:packages`)" entry refers to the **M4's** gh token. The pull happens on **M2**, whose
credential is independent and is the one that matters. That entry never cleared Tier 1.

**Correcting my own claim.** I wrote that Hermes filed no bug doc. Wrong — it filed two
(`c9d5da06`, `0c405871`) and pushed them; my local check predated the fetch. The real finding:
`e2e_bugs.py:163` dedups by exact slug and is **write-once**, so failures 3–17 filed nothing
and a 17× recurrence reads as a single event.

**Tier 2 — verified blocked, not assumed.** Contexts are `k3d-k3d-cluster` and
`ubuntu-hostinger` (no ACG); keychain item `k3dm-acg-pluralsight` is **ABSENT**. Needs a
Pluralsight login at a real TTY — operator-only, Claude's shell has no TTY.

Commits: `ea6d39ca` (rebased), `84798fc0`. Both on origin.


## 2026-09-23 — EXECUTED: the hub no longer runs shopping-cart; ESO survived

`deploy_argocd_applicationsets --confirm` applied the new selectors; option **3a** taken.

**An empty or absent `shopping-cart-data` on the hub is now EXPECTED, not an incident.** Both
`shopping-cart-data` and `shopping-cart-apps` were deleted. The hub deliberately does not run the
shopping-cart data layer or payment stack; Tier 1 (vCluster) and Tier 2 (ACG) carry their own
substrate under `scripts/etc/e2e/`.

Measured: 7 shopping-cart Applications -> 0. `ubuntu-k3s-eso` and `ubuntu-k3s-grafana-dashboards`
Synced/Healthy. ESO CRDs 23 -> 23, Deployments 3 -> 3, `ClusterSecretStore/vault-backend` intact.
ExternalSecrets 22 -> 7, and every one of the 15 removed was shopping-cart-scoped; identity,
monitoring and platform-ops entries all survived with their Secrets verified present, not just their
CRs. Three CrashLoopBackOff pods gone. Every Application is now Synced/Healthy except
`shopping-cart-identity`.

`platform-ops/cosign-public-key` has no Secret, but `lastTransitionTime` == creation time
(2026-09-20T23:53:17Z, `SecretSyncedError`) — never synced, pre-existing backlog item, **not**
caused by this change.

**Corrections worth carrying forward.** The spec's "expect 21 ESO CRDs" was wrong: the Application
*lists* 21, the cluster has 23. Verifying against the Application rather than the cluster would have
raised a false alarm. And the `shopping-cart-identity` root cause is **`Replace=true`**, not the
missing `ignoreDifferences` this spec assumed — `Replace=true` replaces the whole object, so
`ignoreDifferences` alone cannot fix it.

Pre-delete state is in `scratchpad/deregister/` (registration Secret + `get all -o yaml` for both
namespaces). The registration Secret `cicd/ubuntu-k3s-app-cluster` was deliberately **left in place**
and still carries `role: app-cluster`.


## 2026-09-23 — v1.38.0 restructured: vector store as a platform component, Hermes as the consumer

Operator direction: make the deployed vector store and Hermes retrieval the headline; CLI dedup
becomes a by-product. Spec renamed to `docs/plans/v1.39.0-vector-store-platform-and-retrieval.md`.

**The driver is an agent-level defect, not a lint gap.** `scripts/lib/hermes/e2e_bugs.py:163` decides
new-vs-recurrence with `bug_dir.glob(f"*-{group['slug']}.md")` — an unattended agent whose recall over
its own 495-file corpus is an exact string match. A shifted slug makes Hermes file a duplicate bug
doc and keep doing so every run; `created`/`reopened`/`ongoing` and the Slack outcome all inherit it.

Five workstreams: WS1 pgvector as an ArgoCD-managed, ESO/Vault-credentialed, hub-scoped platform
component in its own namespace (explicitly **not** behind the `role: app-cluster` selector); WS2 a
stdlib indexer using a hosted embeddings API over `urllib` — `bin/k3dm-hermes` already imports
`urllib.request`, so this matches the existing idiom and needs no ML wheels on Python 3.14.7; WS3 the
shared retrieval library plus the advisory CLI; WS4 Hermes consumption; WS5 evaluation.

**WS4 is strictly additive and that is load-bearing.** Hermes' filing decision stays on the exact
glob this release; retrieval only appends a `## Possible prior art` section to newly filed docs. An
unproven retriever allowed to suppress a filing turns a false positive into a silently unfiled
defect — invisible failure. Gating needs its own spec, version, and measured precision floor.

WS5 keeps a stdlib TF-IDF scorer as the **control** and measures recall@5 for both, per directory,
against ≥25 hand-mined positive pairs and ≥25 hard negatives. If embeddings do not beat lexical, that
is a finding to state, not skip — the deployed store would then rest on the platform-component
argument alone, which is honest but must be said out loud.

Noted in Risks: if scope grows, split WS1 (platform component) from WS2–WS5 (retrieval) rather than
breaching the 5-plan-doc cap. `local-path` is `reclaimPolicy: Delete`, so the index is a rebuildable
cache and the guide must say so.


## 2026-09-23 — semantic doc dedup specced for v1.38.0 (the one real agentic-tooling gap)

Reviewed k3d-manager against a set of agentic-AI capability outcomes. Five of six are already
covered — Hermes Phase 1 is the autonomous agent (memory-bank + 165 memory files + k3dm-mcp tools),
the Claude/Codex/Gemini/Copilot split with its Haiku→Sonnet→Haiku quota routing is the multi-agent
workflow, external API integration is saturated, and `scripts/tests/fixtures/e2e-corpus/corpus.jsonl`
+ `scripts/tests/hermes/test_e2e_corpus.py` is a genuine labelled eval set.

**The gap is retrieval: zero embeddings or semantic search over documentation anywhere in the repo.**
Verified by grep — the only matches are incidental prose and `scratch/pytest-venv`. Code has
semantic search via the `code-review-graph` MCP; docs never got it. The concrete cost is the
`CLAUDE.md` dedup gate, which is exact slug matching (`ls docs/bugs/*-<slug>.md`) over 495 bug docs,
373 issue docs, 250 plans, 78 retros. Two filings of one defect with different vocabulary do not
collide.

`docs/plans/v1.39.0-vector-store-platform-and-retrieval.md` (initially written as
`v1.38.0-semantic-doc-dedup.md`, restructured on operator direction). Deliberately **two-phase**, because the repo has
**zero third-party Python runtime dependencies** (`check-doc-links.py` is stdlib-only; no
`requirements.txt` or `pyproject.toml` exists) on Python **3.14.7**, where torch-class wheels are not
assured. Phase 1 is a stdlib TF-IDF cosine scorer plus a hand-mined labelled pair set and a
recall@5 floor; Phase 2 adds hosted-API embeddings **only if that measurement justifies it**, via
`urllib` rather than local ML wheels. No vector database at either phase — brute-force cosine over
~1,360 documents is microseconds, and a flat file is the correct index at this scale.

Also noted for a future rule: today's near-miss argues that **a spec proposing a destructive action
must carry a read-only precondition task capable of falsifying its own premise**. That is what
caught the ESO cascade; review did not. Mechanically checkable across `docs/plans/`.


## 2026-09-23 — superseding plan: opt-in `k3d-manager/shopping-cart` label, ESO re-homing queued

Operator direction: take the narrow fix now, re-home ESO as its own item.

`docs/plans/v1.37.0-deregister-hub-app-cluster-shopping-cart.md` was **rewritten in place** (keeping
v1.37.0 at 4 plan docs, under the max-5 cap) around a new approach: add a second label requirement,
`k3d-manager/shopping-cart: "true"`, to the `data-git` and `services-git` cluster selectors **only**.
`eso` and `grafana-dashboards-acg` keep their current selector, so the hub keeps its ESO install and
its three ACG dashboards. Default absent = no shopping-cart, so the hub stops generating
shopping-cart Applications on the next AppSet reapply — **without touching the registration Secret
and without any deletion cascade.** `register_app_cluster` gains
`ARGOCD_APP_CLUSTER_SHOPPING_CART` (default `false`, boolean-validated).

Discriminators considered and rejected: `k3d-manager/managed: "true"` (means "metadata-complete
ephemeral registration" — `_managed` defaults to `false` and `"true"` demands provider + sandbox-id +
expires-at + release at `argocd.sh:1447-1455`; it would wrongly exclude a long-lived hostinger app
cluster); selecting on `server` (ArgoCD cluster generators match labels only); a live selector patch
(reverted by selfHeal and by the release-time reapply).

**Hub-as-app-cluster is a designed mode, not an accident.** `register_app_cluster` has an explicit
`_in_cluster` branch emitting `config: {}`, and `_argocd_set_active_app_cluster` moves
`role: app-cluster` onto whichever cluster is active. What changed is the operator's intent. Also
confirmed `_argocd_appset_live_overrides` only preserves envsubst *variables*
(`${APP_CLUSTER_NAME}`, `${AMBIENT_CNI_*}`) — not the selector — so the reapply will take effect.

Incidental finding: `scripts/etc/argocd/cluster-secret.yaml.tmpl` is **orphaned** — nothing in
`scripts/` references it, and it writes only `role: app-cluster`, so it is stale relative to the
inline heredoc in `register_app_cluster`. Noted in the spec's Risks, not touched.

**ESO re-homing queued separately** in `docs/roadmap.md` (Forward themes, unversioned). The hub's ESO
should be a hub-scoped Application like `hub-loki` / `hub-platform-ops`, not generated by an
app-cluster AppSet. Needs its own scope doc: the migration must keep the 21 CRDs *adopted* rather
than recreated, so it is not a simple retarget.

Nothing live has been mutated. Task 0 of the rewritten spec is read-only and must be re-run at
execution time — `data-git` prunes and holds the resources finalizer, so if StatefulSets or bound
PVCs have appeared in `shopping-cart-data` since 2026-09-23, execution stops.

## 2026-09-23 — ABORTED: deleting the hub app-cluster registration would destroy the hub's ESO

Task 0 of `docs/plans/v1.37.0-deregister-hub-app-cluster-shopping-cart.md` was executed
(read-only state capture). **It invalidated Task 1. Nothing was deleted.**

The spec assumed two ApplicationSets select `k3d-manager/role: app-cluster`. There are **four**:

| AppSet | Generates on the hub | `preserveResourcesOnDeletion` | Deletion finalizer |
|---|---|---|---|
| `eso` | `ubuntu-k3s-eso` — **the hub's entire External Secrets Operator** | unset (prunes) | present |
| `grafana-dashboards-acg` | `ubuntu-k3s-grafana-dashboards` — 3 `monitoring` ConfigMaps | unset (prunes) | present |
| `data-git` | `ubuntu-k3s-data-layer` | unset (prunes) | present |
| `services-git` | `ubuntu-k3s-shopping-cart-*` (6) | `true` (preserves) | absent |

`ubuntu-k3s-eso` owns 3 Deployments, 21 CRDs, 5 ClusterRoles, 2 ValidatingWebhookConfigurations
and the ServiceAccounts in `secrets`. It carries `resources-finalizer.argocd.argoproj.io`, so
deleting the registration Secret cascades: the `externalsecrets.external-secrets.io` and
`clustersecretstores.external-secrets.io` CRDs are removed, taking **all 22 ExternalSecret CRs
cluster-wide** and `ClusterSecretStore/vault-backend` with them. ESO sets `ownerReferences` on the
Secrets it creates (verified on `monitoring/grafana-admin-credentials` and
`identity/keycloak-secrets`), so garbage collection then deletes those Secrets too —
`grafana-admin-credentials`, `keycloak-secrets`, `keycloak-client-secrets`, `ldap-secrets`,
`openldap-admin`, `ghcr-pull-secret`, and every postgres / redis / rabbitmq / minio credential.
The `ubuntu-k3s-grafana-dashboards` ConfigMaps (`checkout-loadtest-dashboard`,
`k3dm-deployment-metrics`, `trivy-security-dashboard`) are **not** duplicated by
`hub-grafana-dashboards`, which carries a different four.

**So the registration is load-bearing, not merely bogus.** `ubuntu-k3s-app-cluster` is the only
Secret carrying `role: app-cluster`, and the hub's ESO install depends on it. The operator decision
("no shopping-cart on the hub") still stands, but it cannot be delivered by deleting the Secret.

**Revised approach — a code change, no live deletion.** All four AppSets live in
`scripts/etc/argocd/applicationsets/`. Narrow **only** `data-git` and `services-git` so they no
longer match the hub, leaving `eso` and `grafana-dashboards-acg` matching as they do today. The
registration Secret template is `scripts/etc/argocd/cluster-secret.yaml.tmpl`, which writes only
`role: app-cluster` — the hub Secret's extra `provider` / `managed: false` / `release: unknown`
labels come from elsewhere, so a new distinguishing label has to be added deliberately rather than
relied upon. A live `kubectl` selector patch would be reverted by selfHeal and by the
release-time AppSet reapply, so the templates are the only durable write point.

Open question for the operator: the deeper misconfiguration is that the hub's ESO is installed by an
*app-cluster* AppSet at all, instead of a hub-scoped Application like `hub-loki` /
`hub-platform-ops`. Fixing that is a larger change than v1.37.0 should absorb.

Secret backed up to `scratchpad/deregister/ubuntu-k3s-app-cluster.backup.yaml` (26 lines).

## 2026-09-23 — the hub syncs shopping-cart onto ITSELF via a self-referential app-cluster registration

`v1.36.0` tagged (`8ea1469d`) and released; `enforce_admins` restored (`enabled=true`).

**Root cause of the "data layer absence".** Secret `cicd/ubuntu-k3s-app-cluster` on the hub
registers cluster `ubuntu-k3s` at `server=https://kubernetes.default.svc` — the hub itself — with
`k3d-manager/role: app-cluster`, plus `managed: false` and `release: unknown` (values the normal
release path does not write). Both AppSets select that label:

| AppSet | Generator | `preserveResourcesOnDeletion` |
|---|---|---|
| `data-git` | `clusters` on `role: app-cluster` | unset → resources ARE pruned |
| `services-git` | `git` (`services/*`, excl. `shopping-cart-identity`) × same `clusters` | **`true`** → resources SURVIVE |

So the hub generates `ubuntu-k3s-data-layer` and `ubuntu-k3s-shopping-cart-*` against itself.

**Why nothing deployed:** `ubuntu-k3s-data-layer` fails its sync *atomically* —
`namespaces "shopping-cart-payment" not found (retried 5 times)`. `CreateNamespace=true` creates
only the **destination** namespace (`shopping-cart-data`); the app's manifests span `secrets`,
`shopping-cart-apps`, `shopping-cart-data`, `shopping-cart-payment`, and ArgoCD does not create
non-destination namespaces. One missing namespace → all 7 StatefulSets never created → empty
`shopping-cart-data` (Services only) → 3 pods CrashLooping on `postgresql-orders...: no such host`.

**`ubuntu-k3s` is a role alias, NOT a place — this name has already misled a session.** It dates
from the ACG sandbox era, and Tier 2 still self-registers the same name inside a sandbox's own
ArgoCD (`scripts/plugins/e2e.sh:122-138`), which is correct *there*. The hub Secret is a different
object in a different namespace. There is no `ubuntu-k3s` kubecontext locally — only
`k3d-k3d-cluster` and `ubuntu-hostinger`.

**Operator decision 2026-09-23: the hub should not run the shopping-cart data layer or payment at
all.** Verified first that this is safe: Tier 1 (vCluster) and Tier 2 (ACG) each carry their own
substrate under `scripts/etc/e2e/` (`postgres.yaml`, `payment.yaml`, `redis.yaml`, digest-pinned
`kustomization.yaml`), independent of `shopping-cart-infra`'s `data-layer` path. So de-registering
cannot break either tier. Spec: `docs/plans/v1.37.0-deregister-hub-app-cluster-shopping-cart.md`
(`3504d565`). **Creating the missing namespace was withdrawn** — it would have entrenched the
misconfiguration.

**Load-bearing ordering:** delete the registration Secret BEFORE the generated Applications, or both
AppSets regenerate them. And reapplying the AppSets before that deletion silently undoes it.

**`services-git` git revision is frozen at `k3d-manager-v1.36.0`** — AppSets need reapplying for hub
and ACG, then `argocd_check_values_branch`.

**Separate, unrelated:** `shopping-cart-identity` is excluded from `services-git`, has no ownerRef,
and fails because ArgoCD tries to `replace` a **bound** PVC — `postgres-keycloak-pvc ... spec is
immutable`, blanking `volumeName` and `storageClassName`. Needs `ignoreDifferences` on those two
fields + `RespectIgnoreDifferences=true`; almost certainly also why `keycloak-realm-reconcile` is
`Failed 0/1`. Needs its own `docs/bugs/` spec.

**Downgraded:** the stale `github/pat` in the Keychain seed backup is less severe than reported.
`vault_seed_hub_into_context` (`scripts/plugins/vault.sh:1063`) reads the **source Vault first** and
falls back to Keychain only when Vault is empty, then rewrites the Keychain backup from what it
read. So the stale copy self-heals on the next seed run against a healthy hub Vault; the risk window
is only "hub Vault lost AND seed runs". Minor: the key array has **14** entries but the success log
says `all 13 canonical keys`.

## 2026-09-23 — v1.36.0 milestone: PR #130 merged, v1.37.0 branch created

PR #130 (feat: v1.36.0 — Tier 2 e2e, deterministic triage, and the hub-rebuild repair list) merged to
main as **945018ee** at 2026-09-23. enforce_admins re-enabled on main. **v1.36.0 remains UNTAGGED**
pending the user's go; next branch is **k3d-manager-v1.37.0** (created from 945018ee).

## 2026-09-22 — hub apps 47h in ImagePullBackOff: stale `github/pat` in Vault, not the k8s Secret

Found by running `make smoke` as the PR #130 live-smoke gate. `cluster-health` FAILED: 4/4 pods in
`shopping-cart-apps` in `ImagePullBackOff` for **47h**, `403 Forbidden` on the GHCR manifest HEAD.

**Root cause chain (verified, not inferred):**

```
ghcr-pull-secret  ←  ExternalSecret (refreshInterval 15m, creationPolicy Owner)
                  ←  ClusterSecretStore vault-backend
                  ←  Vault  secret/data/github/pat   property "token"
```

The pull secret holds a token minted **before** `read:packages` was granted (2026-09-22 23:26).
Fixing the token was necessary but not sufficient — nothing propagated it to Vault.

**The trap, and the thing to remember:** writing the k8s Secret directly is useless.
`kubectl apply` of a fresh `.dockerconfigjson` succeeded and ESO reconciled it away within seconds —
`managedFields` showed `externalsecrets.external-secrets.io/ghcr-pull-secret` and
`kubectl-client-side-apply` at the *same* timestamp `2026-09-23T00:13:22Z`, and the secret carries
`reconcile.external-secrets.io/managed: true` plus an `ExternalSecret` ownerReference. Verified by
reading the value back as MATCH/MISMATCH against `gh auth token` — **MISMATCH**. This is the
[[reference_argocd_selfheal_reverts_out_of_band_patch]] pattern with ESO as the reconciler: always
read the value back.

**Two misdiagnoses avoided along the way:**
1. `403 Forbidden` reads exactly like a missing-scope credential, which is what
   `reference_ghcr_pull_credential_gh_auth_refresh` says it means. Here the scope was already
   correct. Proof: a direct token-exchange + manifest HEAD from the shell returned **200** for the
   exact requested tag `sha-0d8ab3ba…`, and for `sha-b84a534d…` and `latest`. The credential works;
   only the one the kubelet holds does not.
2. The requested tag looked absent from the first page of
   `user/packages/container/shopping-cart-basket/versions` (which is dominated by `.att`/`.sig`
   attestation tags). It exists — pagination, not a missing image.

**Fix is the operator's** (a Vault write needs the root token, which Claude does not read):
`scratchpad/fix-ghcr-pat-in-vault.sh` — read-modify-writes `secret/github/pat` preserving sibling
properties, force-syncs both ExternalSecrets, verifies MATCH, restarts the four deployments. Token
and PAT never in argv; prints no secret material.

**`github/pat` is one of the 14 canonical hub-seed keys** (`vault.sh:1118-1125`), so the Keychain
seed backup also holds the stale token and would restore it on a hub rebuild. Re-backup after the
Vault write.

**RESOLVED 2026-09-23 00:24 (operator ran the script).** `vault write secret/github/pat` → `http=200`,
ESO force-sync → `ghcr-pull-secret vs gh token: MATCH`, four deployments restarted. **The 403 and the
ImagePullBackOff are gone** — images now pull and `frontend` reached `1/1 Running`. The GHCR pull
credential problem is closed.

**What the fix exposed underneath (separate, pre-existing):** `basket-service`, `order-service` and
`product-catalog` now `CrashLoopBackOff` on a **missing data layer**, not on images:

```
order-service: failed to connect to postgres — lookup
postgresql-orders.shopping-cart-data.svc.cluster.local: no such host
```

`shopping-cart-data` holds the **Services** (`postgresql-orders`, `postgresql-products`,
`postgresql-payment`, `minio`, all 2d old) but **zero StatefulSets and zero pods**, so the headless
service has no endpoints and DNS does not resolve. Cause: ArgoCD app `ubuntu-k3s-data-layer` (in
namespace **`cicd`**, not `argocd`) is **OutOfSync** and has never materialised the StatefulSets.
`shopping-cart-identity` is also OutOfSync. This is the long-standing "shopping-cart-data
StatefulSets" pending item — the data layer never returned after the hub rebuild 47h ago. Not caused
by, and not fixed by, the credential work.

**Two more findings from the same smoke run:**
- `shopping-cart-payment` namespace **does not exist** on the hub (only `-apps` and `-data`, both
  47h old). So the smoke threshold `running >= 5` (`bin/smoke-test-cluster-health:86`, counting
  apps + payment) is **unsatisfiable** — apps has 4 deployments. Its
  "ghcr-pull-secret MISSING in shopping-cart-payment" and the ArgoCD `OutOfSync` for payment are
  both downstream of the absent namespace, not separate defects.
- `shopping_cart.sh:458` passes the GHCR PAT as `--docker-password=` on **argv**, same class as the
  CLAUDE.md rule against secrets in script arguments. Needs its own bug doc; not fixed (scope).

## 2026-09-22 — ACG auto-login IS wired; the gap is an unpopulated Keychain item

Spec queued: `docs/plans/v1.37.0-acg-autologin-enablement-for-tier2.md` (v1.37.0 now at 3 plan docs,
cap is 5).

**Correcting a misreading that persisted across several sessions.** Tier 2's P4 was recorded as
"Operator's action (Keychain `k3dm-acg-pluralsight`, or one manual sign-in in `pw-profile`)", which
was read as *ACG login is a manual step / the session gate is not wired*. Verified against the live
tree — it is fully wired:

```
make -C scripts/lib/foundation credential-test
  → scripts/lib/acg/bin/acg-credential-test:7-8   source cdp.sh; _browser_launch (unconditional)
     → _browser_launch          cdp.sh:132 (Chrome already up) AND :163 (fresh launch)
        → _cdp_ensure_acg_session   cdp.sh:166
           → _secret_load_data k3dm-acg-pluralsight username|password   cdp.sh:184-185
```

The auto-login landed in v1.14.0 / lib-foundation v0.4.1 (`b7c849c`) and v0.4.2 (`96bea46`, which
wired the gate into both `_browser_launch` paths) and was subtree-pulled. **It fires on every run.**

**The real gap:** `security find-generic-password -s "k3dm-acg-pluralsight"` → **ABSENT** on this
box. `cdp.sh:184-185` loads both keys with `2>/dev/null || true`, so the gate gets two empty strings
and takes its `ACG_LOGIN_NO_CREDS` branch, which surfaces to a non-TTY caller as
`ACG_SESSION_EXPIRED`. Not a code defect — an unpopulated secret plus a missing preflight that would
have named it.

**Second finding:** `e2e_verify_sandbox` (`scripts/plugins/e2e.sh:294`) sets
`_E2E_ACTIVE_PHASE="preflight"` and then checks **nothing** — its first live action is
`acg_extend_playwright "${_ACG_SANDBOX_URL:-}"` at :315. So a missing credential fails minutes later
inside Playwright (`Buttons: ["Sign in"]`) and the summary blames `extending-sandbox`. Task 1 of the
spec adds `_e2e_sandbox_preflight_auth`, which also refuses to run when
`K3DM_ACG_SKIP_SESSION_CHECK=1` (`cdp.sh:167`) — that var bypasses the session gate and would let an
acceptance run drive a signed-out browser.

**Blocking question (Task 0), operator-only:** does the ACG account carry MFA?
`docs/bugs/v1.14.0-bugfix-acg-pluralsight-autologin.md:394` — the login refuses MFA challenges **by
design**, and the MFA/company account must never be stored in that Keychain item. Path A (no MFA) =
populate the item once, P4 closes permanently, unattended for non-TTY callers. Path B (MFA) =
auto-login is impossible by design, `pw-profile` holds the only session, P4 is never "closed" only
"currently valid". Not answered yet.

**Live state observed 2026-09-22:** CDP browser running; `pw-profile/Default/Cookies` written 09:45
today, so a session may already be valid independent of the Keychain item. The stale sibling
`profile` dir (cookies last written 2026-08-20, nearly empty) is the classic false lead — the CDP
default moved `profile` → `pw-profile` so the browser stays version-locked to the pinned Playwright.
Neither dir may be deleted.

**Does NOT unblock Stripe 4/4.** P3 (`KeycloakRealmRoleConverter` absent from
`shopping-cart-payment` `origin/main`) still causes the payment→Stripe 403; a PR there is not
approved.

## 2026-09-22 — v1.36.0 smoke and hub snapshot features

Smoke feature committed as `6f1f7fd1` (`feat(smoke): add a unified make smoke target with tiered checks`).
Hub snapshot feature committed as `d53ea1ba` (`feat(hub-snapshot): capture hub state to the M2 store with retention`).
Both implementations are offline-only and leave Jenkins unwired, `make down`/`make up` unchanged,
and the Prometheus admin API disabled. Focused suites, shellcheck, and `make test` passed (`1030/1030`).
The Loki record required legacy recovery count assertions to move from seven to eight; compatibility
test commit `5eb759eb` was pushed after the two feature commits.

**Claude verification found two defects Codex's own green run did not surface** — fixed in
`5dd53be8`, both mutation-verified:

1. `K3DM_SNAPSHOT_DIR` defaulted to `~/k3dm-snapshots`. A tilde does not expand inside double
   quotes, and the value is then single-quoted for the remote shell, so the M2 would receive
   `mkdir -p '~/k3dm-snapshots'` and create a directory **literally named `~`** — snapshots
   landing in `$HOME/~/k3dm-snapshots`. Confirmed by simulation before fixing. The BATS suite
   could not catch it because the ssh stub never creates real paths; a guard asserting the
   default contains no tilde was added (14th case).
2. `hub_recovery_validate` still printed "seven logical claims" after the Loki record made it
   eight. An operator reading "seven" after restoring eight would reasonably doubt Loki was
   included. The message is now derived from the record count so it cannot drift again.

Independently re-verified, not taken from the report: SHAs present on `origin`, local HEAD ==
origin, `hub_recovery.sh` touched by exactly one insertion, node placement genuinely derived
from the PV's `nodeAffinity` (fails closed on ambiguity), and the contract test really does
iterate `_hub_recovery_records` and call `_hub_recovery_claim_tree` against the captured tree.
Suites re-run by Claude: hub_recovery 27/27, hub_snapshot 14/14, smoke 7/7, shellcheck RC=0.

**Free-space preflight REMOVED** in `d1c8b5b3` at the operator's request. It ran *after* the
full local capture, so it never delivered the "refuse before copying anything" behaviour the
spec asked for — it only guarded the M2 transfer, which `rsync` already fails on when the
destination is full. Removed rather than moved: it bought no safety the transfer did not
already provide. The insufficient-space BATS case was replaced by its **inverse** — a
successful capture must issue no remote `df`, so restoring the preflight fails the suite
(mutation-verified). Requirement 3 and case 6 struck in place in the spec with the reason;
numbering left intact. Suite stays at 14 cases.

Residual gap, accepted knowingly: on a transfer failure the remote directory is now left
un-marked rather than `.INCOMPLETE` (checksum failures still mark it). A two-line change
would close it; deferred pending the operator's word.

`make test` after the removal: **1031 ok / 0 not ok** — count reconciles exactly (one case
out, one in). First run showed 4 reds in `e2e_remote.bats`, which is the documented
**unpushed-HEAD** signature, not a regression: local HEAD was `d1c8b5b3` while origin was
still `2ee4ad86`. After pushing, `e2e_remote` is 74/74. Process note: the run was launched as
`make test > log 2>&1; echo "EXIT=$?"`, whose trailing `echo` always succeeds — the harness
reported exit 0 for a run where `make` printed `*** [test] Error 1`. `make test; echo $?` is
not a way to check an exit code.

## 2026-09-22 — Prometheus Vault entry REPAIRED (operator-run)

`secret/data/k3d-manager/prometheus-basic-auth` was **404**; it is now **200**. The operator ran
`/tmp/prom-recover.sh`; Claude did not execute it, because the script reads the Vault root token
via `kubectl` into a curl header and that read is on Claude's do-not-touch list — structured so
the token stays in the operator's shell.

Output confirmed the intended branch: `recovered the Prometheus password from the local cache;
not rotating`. **No rotation**, so existing saved Prometheus logins keep working.

Preconditions re-verified live before the run (not carried over from the earlier session):
cache at `~/.local/share/k3d-manager/prometheus-basic-auth.env` readable (143 bytes, user key
present), cached password 32 chars and not the literal `"password"` (so the recovery branch
rather than the generate branch), `htpasswd` present for the re-bcrypt, Vault health `http=200`.
Secret values were never printed — length and a sentinel comparison only.

**First run failed and the bug was Claude's:** `observability.sh:6` reads `$PLUGINS_DIR` at
source time to pull in `vault.sh`, and the staged script set neither `SCRIPT_DIR` nor
`PLUGINS_DIR` — it used a local `S="scripts"` nothing else knew about. Fixed by setting both
absolutely; verified by sourcing the full chain in a throwaway shell and confirming
`_observability_ensure_prometheus_login`, `_observability_seed_prometheus_vault_entry` and
`_vault_exec` all resolve.

**Consumers of this Vault path — nothing in-cluster:** `Makefile:542`
(`show-service-passwords`) and `observability.sh`'s own ensure/seed/rotate logic. No
ExternalSecret, no ServiceMonitor, no Prometheus scrape config. Nothing needed a restart.

**This does NOT affect Grafana.** Hub Prometheus has no basic auth and the Grafana datasource is
unauthenticated; this entry is a credential-store row for operator access and
`show-service-passwords`. The blank e2e panels remain a producer problem — see
`reference_e2e_dashboard_blank_means_empty_event_payload`.

Still open, unchanged: realm SSO rows in `show-service-passwords` will still read "not
provisioned on this cluster" because `secret/keycloak/` holds only `['admin','clients']` with no
`users/` subtree. Seeding `secret/keycloak/users/*` remains an operator decision.

## 2026-09-22 — Tier 1 e2e credential gate cleared (`read:packages` + `workflow`)

Operator ran `gh auth refresh -h github.com -s read:packages,workflow` from their own terminal
(the device flow needs a real TTY; my shell has none). Scopes are now
`admin:public_key, gist, read:org, read:packages, repo, workflow`.

Verified three ways rather than trusting the `✓ Authentication complete.` line: live
`X-Oauth-Scopes` header from `gh api -i user`; `gh api user/packages?package_type=container`
returning a count where it previously returned 403; and the keychain item's `mdat` moving from
2026-09-14 to 2026-09-22T23:26:00Z. Read access confirmed against the **private**
`shopping-cart-basket` package (`visibility: private`, versions listable) — probing the public
`shopping-cart-e2e-tests` would have answered anonymously and proven nothing.

**The first attempt silently no-opped.** The device flow was started but the browser half never
completed, and the command left no error behind, so it was indistinguishable from success by output
alone. The stale keychain `mdat` — eight days old at the time — is what proved no token had been
written, and is the check that separates "a new token arrived without the scope" from "no new token
arrived". `~/.config/gh/hosts.yml` mtime is only suggestive, since a keyring-stored token can be
replaced without touching it. Recorded in
`memory/reference_ghcr_pull_credential_gh_auth_refresh.md`.

This clears the credential gate only. The Tier 1 run itself has not been executed. Tier 2 remains
blocked on the manual ACG TTY login.

## 2026-09-22 — Realm SSO reseed spec: hub seed set APPROVED, added as requirement 4

The operator approved adding `keycloak/users/*` to the hub seed set, so it moved out of
"out of scope" and into `docs/plans/v1.37.0-realm-sso-password-reseed.md` as requirement 4.

**There is no single allowlist to edit** — the 14 keys are enumerated twice:
`scripts/plugins/vault.sh:1118-1125` (`_keys` array in `vault_seed_hub_into_context`, the side that
writes the Keychain backup) and a hand-written per-key chain in `shopping_cart.sh:696`
(`shopping_cart_seed_sandbox_vault_kv`, which `bin/cluster-up:745` runs). Changing only the latter
yields a seeder reading a key the Keychain never held: `_seed_source_data` reads a canonical
*source* Vault, and on a hub rebuild that is the Vault just destroyed, so the Keychain fallback at
`vault.sh:1135` is the only live restore path. Enumerate three literal paths — Vault KV has no glob.
`scripts/tests/plugins/vault_seed_hub.bats:58` pins the exact list and goes 14 to 17; the two howto
docs that say "14" and call `keycloak/users/*` "expected to be absent" become wrong on landing.

New risk written into the spec: these three are per-cluster random values, unlike the other 14
static shared secrets. A Keychain-restored record whose LDAP hash no longer matches makes
`make show-service-passwords` display a credential that fails to log in — worse than the blank it
replaces. The reseed's *present then re-apply, no rotation* branch is the required reconciler, so a
seeded record is never authoritative without an `ldapwhoami` check.

Auto-reseeding on `make up` remains out of scope. `make check-doc-links` 1738 OK.

## 2026-09-22 — Webhook server decomposition specced and QUEUED for v1.37.0

`docs/plans/v1.37.0-webhook-server-decomposition.md` (`1b67b2db`). **Queued, not for
implementation during v1.36.0**, which is at the five-plan-doc cap; v1.37.0 now has 1.

`bin/k3dm-webhook` is **4,009 lines / 180KB**, ~110 module-level functions, 19 routes. Measured
concern clusters: cluster lifecycle 1233, smoke-SSO client 483, ask/agent invoker 450, Slack
thread commands 362, failure analysis 153, authz/policy 149, metrics 100, redaction 50 (2980
grouped). Two do not belong in an HTTP server at all — the smoke cluster is a
browser-emulating SSO client subclassing `HTMLParser` and walking an OAuth code flow, and the
agent cluster invokes an AI agent with a mutate-the-cluster "fix mode".

**The defect is adjacency, not size.** `do_POST` spans 3515–3942 (428 lines); the role
resolution for `/api/v1/make` is at line **3642** and the handler that spawns the job at
**3880** — 238 lines apart in one method. Nothing is wrong with either block; no reviewer can
hold both in view. This is the component the operator has named as their top security worry.

Extraction is ordered by **value-if-stopped-early**, not by size: Phase 1 is `policy.py` + an
explicit route table declaring `(path, min_role, handler)` on one line each, so the security
payoff lands even if later phases never do. Then smoke.py (483, pinned by 14 pytest cases),
agent.py (450 — `_fix_mode_enabled` gates cluster mutation and has **no test today**; one must
be added with the move), lifecycle.py/status.py (1233). Recommended **against** a rewrite: the
stalled `scripts/lib/webhook/` extraction (412 lines, 5 modules) proves incremental works.

Measured baseline net that must stay green: **105 cases** — webhook.bats 64 (58 run, 6
live-gated), webhook_hub_eso.bats 4, webhook_make_targets.py 11, webhook_redaction.py 6,
webhook_request_hardening.py 6, test_smoke_logins.py 14.

**Two findings worth carrying forward.** (1) The three `webhook_*.py` files are
`unittest.TestCase`, not pytest, and run only because `make test-python-unit` loops
`scripts/tests/bin/*.py` skipping `test_*`. I initially suspected they were orphaned and was
wrong — but they are invisible to both `make test` and `make test-pytest`, so `make test`
alone cannot catch a break in any of the 37 Python cases. Use `make test-all`. (2) All four
Python suites load the entrypoint wholesale via `SourceFileLoader` and reach into private
attributes (`wh._REDACT_VALUES`, `wh._redact_secrets`), so moving a function breaks them
unless the test is repointed in the same commit. Permanent re-export shims are barred — they
keep the file long and defeat the purpose.

Also confirmed: `scripts/plugins/smoke.sh` (72 lines, v1.36.0) does **not** duplicate the
webhook's 483-line smoke client today. Converging them is explicitly out of scope.

## 2026-09-22 — Grafana "no data" triaged; smoke + hub-snapshot specs assigned to Codex

**Grafana is not broken.** Hub Prometheus has 31 active targets up and serves data; the
`kube-prometheus-stack-grafana-datasource` ConfigMap points at
`http://kube-prometheus-stack-prometheus.monitoring:9090/` unauthenticated (correct — hub
Prometheus has no basic auth) and all 30 dashboard ConfigMaps provisioned cleanly. Grafana's
own logs contain no datasource query errors. Grafana is reachable at `grafana.3ai-talk.org`
(HTTP 200); its port-forward is `:3001`, not `:13000`.

What is actually empty, and why — three independent causes, none of them a query fault:

- **e2e dashboards.** `e2e_last_run_pass = 0` — the last run, 15.6h ago
  (`run_id=1790025545-10464`, `tier=vcluster`, `runner=local-m4`), FAILED.
  `e2e_last_success_timestamp_seconds` has **never** been published, so every
  "last success" and trend panel is legitimately blank.
- **e2e failure detail.** `e2e_failure_info` and `e2e_failure_group_info` are empty even
  though the run failed, and `e2e_run_info` carries a malformed `failure_ratio="/"` —
  an empty-over-empty division. A failed run produced no failure detail. This is the gap
  `docs/plans/v1.36.0-e2e-deterministic-triage-and-corpus.md` covers.
- **Hermes.** `hermes_sensor_status` and `hermes_last_poll_timestamp_seconds` empty because
  `K3DM_HERMES_STATUS_ENABLED` is deliberately unset. By design.
  `hermes_incident_active` and all `trivy_*` metrics DO have data.

Metric names match the dashboards exactly — there is no `k3dm_` prefix mismatch.

**Tier 1 and Tier 2 e2e remain unrunnable; both blockers verified, not assumed.**
Tier 1: the `gh` token scopes are `admin:public_key, gist, read:org, repo` — no
`read:packages`, so the in-cluster Playwright job cannot pull from GHCR. Runner health is
otherwise green (`hub=ok`, `runner=m2jump`, `runner_status=available`). Operator must run
`gh auth refresh -h github.com -s read:packages`. Tier 2: no ACG context exists at all
(only `k3d-k3d-cluster` and `ubuntu-hostinger`); needs the manual TTY login.

**UPDATE 2026-09-22 — the Tier 1 credential half of the above is CLEARED.** Scopes are now
`admin:public_key, gist, read:org, read:packages, repo, workflow`; private-package read confirmed
against `shopping-cart-basket`. See the 2026-09-22 entry at the top of this file. Tier 2 is
unchanged and still needs the manual TTY login.

**Two specs written and pushed as `b37acb91`, dispatched to Codex (session
`01a0c93c-45b4-7301-9ac7-661b66e21204`):**

- `docs/plans/v1.36.0-make-smoke-target.md` — no `make smoke` exists today; three
  `bin/smoke-test-*` scripts are invoked ad hoc. Tiered target: offline checks always,
  cluster checks only when the context is reachable (unreachable = SKIP with a reason, not
  FAIL). Deprecated `bin/smoke-test-jenkins` stays unwired.
- `docs/plans/v1.36.0-hub-snapshot-capture-and-retention.md` — **the restore half already
  exists** (`hub_recovery_plan/validate/targets/restore`, executed 2026-09-11). Only capture
  is missing. Capture must emit the exact layout `hub_recovery_restore` already consumes
  (`server-db/state.db`, `server-token`, `pv-pvc.yaml`, `node-*-storage/pvc-<uid>_<ns>_<claim>/`),
  offload to M2, and prune.

**Measured sizes (hub, 2026-09-22):** Prometheus 2.0G, keycloak-postgres 67M, Loki 46M,
Vault 23M → **≈2.15G per snapshot**. M2 (`m2jump`/`m2-air.local`) has **382Gi** free vs the
M4's 163Gi, so M2 is the store, as the operator proposed.

**Retention ceiling — the governing constraint.** Hub Prometheus runs
`--storage.tsdb.retention.time=3d --storage.tsdb.retention.size=8GB` and prunes
out-of-retention blocks *at startup*. A snapshot older than 3 days therefore restores blocks
Prometheus immediately deletes — the feature would silently do nothing. Snapshot retention
defaults to 3 kept snapshots for that reason. Long-term history needs raised retention or
remote-write, NOT snapshots. `enableAdminAPI` is `false` and stays false: capture happens
during teardown, so a cold copy is consistent by construction.

Two spec decisions worth remembering: node placement must be **derived from the live PV**,
not read from `_hub_recovery_records` — `local-path` pins to whichever node the pod landed
on, and Prometheus measured on `agent-1` today while the record says `agent-0`. And Vault KV
needs no separate export: `secrets/data-vault-0` is the file backend and already contains it.

Wiring capture into `make down`/`make up` is explicitly OUT of scope until capture is proven
on a real hub — adding a 2.15G transfer to the destructive `down` path unreviewed is not
acceptable.

## 2026-09-22 — Prometheus reseed and rotator CI fix

Implemented and committed as `7d475a9fe1e8e5f051d035b4f917559341d8b127` (`fix(observability): distinguish unreachable Vault from an absent Prometheus entry`), then pushed to `origin/k3d-manager-v1.36.0`. Vault reachability now gates Prometheus reseeding; unreachable Vault skips without writing, while an absent entry still reseeds. The two reseed security assertions are effective, the Alertmanager test is hermetic and checks the real unresolved-value gate, and the Keycloak/ArgoCD rotators use BusyBox-compatible `base64 -d`. Added the platform-ops regression suite and rotation-guide note. Verification: shellcheck, all focused suites, doc links, and `make test` (1,010/1,010) passed; `scripts/tests/lib/observability.bats` is unchanged.

## 2026-09-22 — Post-merge housekeeping for promoter PRs

Both `shopping-cart-product-catalog` PR #55 and `shopping-cart-infra` PR #99 merged successfully
at 2026-09-22 00:04-00:05Z, merge commits `b6ff80b7` (product-catalog) and `91432535` (infra).
Both fixed the PROMOTER_SSH_KEY promotion failure: product-catalog's `ci.yml` now forwards the key
to the reusable workflow, and infra gained the guard step that detects an empty key and fails with
an actionable error message. Main synced locally for both repos and merge commits verified present.
`enforce_admins` on shopping-cart-infra was restored and verified enabled. CHANGELOG entries remain
under `[Unreleased]` (correct for fix branches, not milestone releases). Release lists generated;
no tags needed. No next branch or retrospective for fix merges. Memory-bank updated and committed.

**Scope of what is proven:** the above is merge-and-housekeeping verification only. Promotion
itself has NOT been observed working. Merge run `35670460109` on `b6ff80b7` is the first run in
which `Build, Scan & Push / build-push` actually executes rather than reporting `skipping` — the
publish job does not run on pull requests, which is precisely why six PR pushes stayed green over
a broken promote step. A first draft of this entry (subagent output, commit `f96cce1f`) marked
promotion `[x] FIXED` and "verified"; that was corrected here and in `progress.md`, because a
merged diff is not an executed code path. Verification requires reading the promote step's own
log and confirming `newTag:` in `k8s/base/kustomization.yaml` advanced — not the run conclusion,
since the promote step runs under `continue-on-error: true`.

**RESOLVED 00:13Z — promotion verified working.** Run `35670460109` promoted successfully.
Commit `6b79fda` is on `origin/main` authored by `sc-image-promoter` (the deploy-key identity),
setting `newTag: sha-b6ff80b7...`. Verified from the committed artifact and its author, not the
run conclusion. The previous change to that file was 2026-05-24 by a human, so this is the first
successful promoter write to this repo — broken since 2026-08-12, now closed.

## 2026-09-21 — rotate-ghcr-pat fix prepared; commit blocked by Git filesystem permissions

Implemented the exact Changes 1–4 from `docs/bugs/2026-09-21-rotate-ghcr-pat-targets-wrong-cluster-and-leaks-pat-in-argv.md`
in `bin/rotate-ghcr-pat` and added the five static-source gates in
`scripts/tests/bin/rotate_ghcr_pat.bats`. Gate mutation counts were non-vacuous:
hardcoded context 2→0; pull probe 0→2; `--docker-password` 1→0;
Vault-token argv 2→0; `/user` auth validation 1→0; ESO branch 0→1. **Correction by Claude:**
Codex reported the PAT basic-auth argv gate as 1→0; it was actually 0→0 (vacuous) because the
pattern carried stray `\${` escapes the source never contained. Pattern corrected to the
unescaped form, re-measured 1→0, and all five gates mutation-tested `not ok` against the
pre-fix file before restore (shasum-verified byte-identical). Pull probe line 59 precedes
the first `gh secret set` line 106. `shellcheck -S warning` and `shellcheck -S error` were clean;
focused BATS was 5/5. The required commit could not be created because Git cannot create
`.git/index.lock` (`Operation not permitted`); no commit SHA or push exists yet.

## 2026-09-20 — Port-forward wrapper fix implemented; Git commit blocked

Implemented the requested allowlisted fix for `docs/bugs/2026-09-20-pf-wrapper-silent-wrong-context-and-address-blind-port-sweep.md` in the wrapper template, ArgoCD generator, `bin/cluster-up`, both focused BATS suites, and `CHANGELOG.md`. The wrapper now scopes both listener probes and the forward bind to `ADDRESS`, parameterizes `LOG_TAG`, re-resolves context at each supervisor iteration with de-duplicated warnings, and regenerates the keycloak-browser wrapper unconditionally. Verification: `bats scripts/tests/plugins/argocd.bats` 32/32 passed; `bats scripts/tests/bin/cluster_up.bats` 9/9 passed; `shellcheck -S warning scripts/plugins/argocd.sh bin/cluster-up` exit 0. Explicit `git add` failed with `fatal: Unable to create '/Users/cliang/src/gitrepo/personal/k3d-manager/.git/index.lock': Operation not permitted`; no commit or push SHA exists from this session. PR URL: not created per task instruction.

> Compressed 2026-09-17 (v1.34.0 Grafana/observability block closed → collapsed to pointers).
> Full pre-compression detail: `memory-bank/archive/activeContext-2026-09-17.md`.
> Settled fixes live as pointers; detail in `memory-bank/archive/`, `CHANGELOG.md`,
> `docs/retro/`, `docs/issues/`, `docs/bugs/`, git history, and auto-memory.

## Current focus

- **2026-09-20 — CRITICAL: hub PVC data has no backup and `make down` destroys it.** Asked to
  confirm restorability; the answer for the seven stateful hub claims is **no**. Three independent
  causes: (1) `hub_recovery_plan/validate/restore` all consume a
  `<captured-recovery-directory>` that **nothing in the repo produces** — the consumer half of the
  feature shipped, the producer never did, and no such directory exists on the host; (2) every PV
  is `reclaimPolicy: Delete` (`local-path` SC default, cluster-wide); (3) `bin/cluster-down:330`
  runs `k3d cluster delete` unconditionally with **zero** backup/capture hits in the file, which is
  the exact command `docs/plans/v1.33.0-hub-local-path-restore.md` precondition 5 forbids. Nothing
  is scheduled either — no crontab, no backup launchd agent. v1.33.0 only worked because an ad-hoc
  external "M2 monitor" did the capture.
  **What IS covered:** the 14 canonical app secrets have three copies (Keychain
  `k3d-manager-app-cluster-secrets` — all 14 verified present by existence probe; hostinger
  `secrets/vault-seed-backup`, 14 keys, 61d stale; plus `vault-root`). That layer is proven — the
  Stripe key restored from Keychain today.
  **What is NOT:** Vault's full KV (this is why `cosign-public-key` is genuinely lost — not one of
  the 14), Keycloak Postgres, all three OpenLDAP volumes, Prometheus history, Trivy cache.
  Current hub data is unprotected *right now*. Spec:
  `docs/bugs/2026-09-20-no-capture-producer-hub-pvc-data-unrecoverable.md`. **Awaiting the user's
  go** for a manual capture of the live claims (live `docker exec`).

- **2026-09-20 — Keycloak `make status` error root-caused: the daemon is on the WRONG CLUSTER.**
  `com.k3d-manager.keycloak-browser-http` (pid 30083, up **16 days**, `runs = 1`, never exited)
  logs `services "istio-ingressgateway" not found` while the service plainly exists on the hub.
  Caught its own child's argv by polling `ps`: `kubectl --context ubuntu-hostinger port-forward
  svc/istio-ingressgateway -n istio-system 80:80` — and hostinger's `istio-system` has `istiod`
  only. Three defects in `scripts/etc/argocd/port-forward-wrapper.sh.tmpl`: context resolved
  **once outside** `while true` so a cluster rebuild can never be picked up; the current-context
  fallback branch **logs nothing** (`grep -c WARNING` over 90 MB = 0), so the log accuses the
  cluster of missing a present service; and `_clear_stale_listeners` sweeps
  `lsof -iTCP:${LOCAL_PORT}` **address-blind**, so it kills the frontend daemon's legitimate
  `127.0.0.2:80` forward. Causation measured: keycloak log grew and frontend died in the **same
  second** (18:01:51), a ~31s beat, `forks = 23015`, frontend log 69 MB. Deployed wrapper is also
  a stale generation (`sleep 30`, `--max-time 1`, no `--address`) because nothing regenerates it.
  Spec: `docs/bugs/2026-09-20-pf-wrapper-silent-wrong-context-and-address-blind-port-sweep.md`.
  Note: `sudo launchctl` is **not** passwordless — `/etc/sudoers.d/k3d-manager` exists (0440) but
  `sudo -n launchctl` is refused.

- **2026-09-20 — HUB REBUILD EXECUTED. The kine compaction stall is CLEARED.** The operator ran
  `make down CLUSTER_PROVIDER=k3d`; Claude completed the rebuild and monitored it. Evidence the
  root fault is gone: `state.db` **2.72 GiB → 25.8 MB**, WAL **678 MB → 10 MB**,
  `kubectl get nodes` **5.5s → 0.05s**, and `COMPACT deleted` is logging on a **5-minute cadence**
  (= 288/day, the healthy baseline) having caught the backlog up to rev 1445/2445. Before the
  rebuild that predicate had **zero** matches in the entire retained log. `kubectl exec` works
  again. See `docs/bugs/2026-09-09-hub-kine-compaction-stall.md`.

  Two procedural traps found the hard way, both now fixed in
  `docs/howto/hub-rebuild-from-gitops-vault.md`:
  1. **`make up CLUSTER_PROVIDER=k3d` fails** — `bin/cluster-up:78` rejects it
     (`supported: k3s-aws, k3s-gcp, k3s-az`). But **bare `make up` is also wrong for a hub-only
     rebuild**: it defaults to `k3s-aws` and runs the full 12-step ACG path including Playwright
     credential extraction and an interactive `read -r -p` prompt. The hub-only sequence is
     `deploy_cluster --provider k3d k3d-cluster` → `deploy_vault` → `deploy_ldap` →
     `deploy_argocd` → `make observability` → `make platform-ops`, which is exactly what
     `bin/cluster-up` Step 3.5/3.6 does internally.
  2. **`k3d cluster delete` left debris that blocks re-creation** — `k3d-k3d-cluster-agent-1`
     could not be killed ("did not receive an exit event"), which then held the network
     (`has active endpoints`) and the `k3d-k3d-cluster-images` volume. Remove the three by exact
     name before rebuilding; never by wildcard.

- **2026-09-20 — port-forward supervisor fix (the residual Grafana flap).** With the apiserver
  healthy the Grafana forward *still* restarted ~every 45s — five times in two minutes — because
  `_hostinger_write_monitoring_port_forward_wrapper` killed it on a **single** failed
  `curl -fsS --max-time 3`. Grafana `/api/health` measures ~0.2s median with a tail past 3s and
  occasional 503s during dashboard reload, so the supervisor was manufacturing the ~2s listener
  gaps cloudflared reports as **502**. Now requires `K3DM_PF_HEALTH_THRESHOLD` (default 3)
  consecutive failures with `K3DM_PF_HEALTH_TIMEOUT` (default 8s), counter reset on success.
  Live wrapper regenerated + agent kickstarted: **0 restarts**, all probes 200 at 0.005–0.47s.
  The generator is shared, so this covers hostinger too. Spec:
  `docs/bugs/2026-09-20-pf-supervisor-kills-healthy-forward-on-single-slow-probe.md`.
  Same disease family as [[reference_one_second_probes_cpu_starvation_kill_loop]].

- **2026-09-20 — alertmanager CPU fix committed git-only; applies via the rebuild.**
  `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml` alertmanagerSpec now
  `requests` 64Mi/50m, `limits` 128Mi/500m (was 32Mi/10m, 64Mi/**50m** — the 50m limit was the
  83-87% CFS throttle). Deliberately **not** applied with a live `helm upgrade`: a hub rebuild is
  the indicated remedy for the kine stall and would discard it, so git is the durable place. It
  lands automatically when `make up` runs `observability`. Verify the throttle fraction drops from
  ~0.83 afterwards — see [[reference_alertmanager_cpu_limit_throttles_notifications]].

- **2026-09-20 — Hermes re-page fix landed.** Implemented by Codex, verified and committed by
  Claude (Codex hit the known `.git/index.lock` sandbox wall and could not commit — see
  `reference_codex_exec_cannot_commit_git_lock`). `Correlator.process` now emits an `escalation`
  event when a sensor joins an active incident, keeping the notified set monotonic until resolve so
  a flapping sensor cannot re-page; both `kind == "incident"` gates in `bin/k3dm-hermes._run_cycle`
  widened to `("incident", "escalation")`, without which the new event would have been emitted and
  then dropped by its own consumer; `bin/public-endpoint-probe` counts 401/403 as reachable while
  still reporting the real code. Verified independently: diff touches only the 7 in-scope files,
  `pytest scripts/tests/hermes/test_hermes.py` = **26 passed** (note: pytest lives on the pyenv
  shim, not `/opt/homebrew/bin/python3`, which has no pytest module), and a read-only
  `bin/public-endpoint-probe --json` showed prometheus/alertmanager/webhook all
  `"codes":["401"...] "healthy":true`. **Codex's `make test` was incomplete** — it stopped at
  `ok 724` of `1..974` with no `not ok`, so the full suite is re-run by Claude after commit.

- **2026-09-20 — Grafana Cloudflare 502 root-caused; Hermes escalation gap filed.** The 502 on
  `grafana.3ai-talk.org` is **not** Grafana and **not** Cloudflare. Grafana is `3/3 Running`, all
  containers `ready=true`, limits `500m`/`512Mi`, 26% CFS throttle. The tunnel holds 4 healthy
  edge connections and `~/.cloudflared/config.yml` was loaded at process start (config mtime
  `2026-09-11 05:07:20` vs PID 73552 `lstart` one second later), so no stale-ingress drift. The
  chain is: **kine compaction stall** (`state.db` 2.398 → 2.414 GiB across three cycles,
  `slow_sql` 447 → 616 → 898, `compaction_recent=False`) → apiserver unreachable
  (`Unable to connect to the server: net/http: TLS handshake timeout`; a test pod could not even
  schedule) → `kubectl port-forward`'s SPDY stream breaks within ~30 s
  (`portforward.go:512 ... write: broken pipe`) → the launchd supervisor's `/api/health` check
  correctly kills and respawns it → **18,211 restarts** in
  `~/.local/share/k3d-manager/logs/grafana-pf.log`, one every ~35 s → no listener on
  `127.0.0.1:3001` for most of every minute → cloudflared gets connection refused → CF 502.
  A 30 s sample caught all three port-forward states: listening+200, **listening but refusing
  (`http=000` with the PID still bound — the zombie window)**, then gone, then respawned.
  This is **not Grafana-specific**: `bin/public-endpoint-probe` returned `edge-down` with argocd
  502, frontend 503, keycloak 502, grafana 502 while direct curls seconds earlier gave argocd 200
  and keycloak 302. Every port-forward-backed endpoint flaps for the same reason, so this is
  downstream of the datastore — like the kube-state-metrics CrashLoop (now 356 restarts) — and
  **only the hub rebuild clears it**. The supervisor probe was explicitly tested against
  `reference_one_second_probes_cpu_starvation_kill_loop` and **exonerated**: it is detecting a
  genuinely dead forward, not killing a healthy one.
  **Hermes already detected this and sent nothing.** Filed
  `docs/bugs/2026-09-20-hermes-correlator-never-re-pages-after-incident-latches.md`:
  (1) `Correlator.process` is edge-triggered — it emits only on the `False → True` transition of
  `incident_active`, which the kine stall latched days ago, so `reachability` going degraded was
  absorbed silently (`"event": null, "pages": []` every cycle); fix is an `escalation` event when
  the contributor set grows, plus widening both `kind == "incident"` gates in
  `bin/k3dm-hermes._run_cycle` (lines 138, 150) so it is actually pageable;
  (2) `bin/public-endpoint-probe` counts HTTP **401** as unhealthy, so `prometheus`,
  `alertmanager` and `webhook` — all correctly answering 401 behind auth proxies — are permanent
  false failures that both help keep the latch set and skew the verdict toward `edge-down`.
  `sensors.kine`'s 8 GiB `max_db_bytes` was checked and deliberately left alone: the sensor
  reported the stall correctly via its `slow_sql > 0 and not compacting` arm.
  Correction on the record: my mid-investigation claim that `bin/k3dm-hub-datastore-status`
  is missing and that that was why Hermes never fired was **wrong on the causal half**. The file
  is genuinely absent, but `bin/k3dm-hermes:82` injects its own `_datastore_run`, which does not
  use that path; the kine sensor produces live data. The silence is the correlator.

- **2026-09-20 — Tier 2 live-run blockers filed as `5edf557e`.** Spec
  `docs/bugs/2026-09-20-e2e-sandbox-job-service-names-markers-secrets.md`. Tier 2
  (`e2e_verify_sandbox`, implemented `ffeb9ba2`) is code-complete and structurally green but has
  never executed live; three defects in the sandbox Job path would fail the first run:
  (1) three of four service hostnames do not exist — `basket`/`order`/`payment` instead of
  `basket-service`/`order-service`/`payment-service`, all four ports already correct, and
  `_e2e_sandbox_render_overrides` (`e2e.sh:149-150`) already uses the right names, so the file
  contradicts itself; (2) the Job command omits the `__E2E_RESULTS_BEGIN__`/`__E2E_RESULTS_END__`
  wrapper the parser at `e2e.sh:636` requires, so `passed`/`total`/`failed` stay `None` and
  pass/fail attribution is dead; (3) neither `ghcr-pull-secret` nor `stripe-e2e` is ever created
  in the sandbox — `stripe-e2e` has exactly one repo-wide reference, the `secretKeyRef` that
  consumes it — so the Job never starts. All three are Tier 2 only; Tier 1 is correct in each
  case, which is why review missed them: the sandbox manifest is a near-copy of the Tier 1 one and
  diverged where Tier 2's substrate differs. The structural BATS suite asserts manifest shape and
  cannot detect any of them. **The ACG login is NOT a blocker** — it is a routine step run many
  times before; `acg_restart` fronts any Tier 2 run. No `ubuntu-k3s` context exists right now, so
  the sandbox is simply not provisioned at the moment.
  Spec commit is local only, NOT pushed — Codex is mid-run on the same branch and pushing first
  would hand it a non-fast-forward. Push after Codex reports.


- **2026-09-20 — KubeAPIDown flapping apiserver scrape timeout implementation complete; commit
  COMMITTED and PUSHED as `0d663a40`.** Codex could not commit (`.git/index.lock:
  Operation not permitted`) and honestly refused to claim a SHA; Claude staged the six allowed
  files and committed with the spec's exact message. **Independent verification by Claude:**
  scope 6 files all on the allowed list; `shellcheck -S warning` exit 0; focused suite 6/6;
  four mutations run in an isolated worktree all reddened a real assertion — default `45s`->`90s`
  (tests 1,2), idempotency removed (test 2), patch also rewriting `jobLabel` (tests 1,5), patch
  path -> `interval` (tests 1,5). The last two are Claude's own additions and prove test 5, the
  alert-inversion guard, has real teeth. **Live read-only checks confirmed the design against the
  cluster rather than the spec:** SM `monitoring/kube-prometheus-stack-apiserver` exists with
  `jobLabel: component`, exactly one endpoint, and an EMPTY `scrapeTimeout`; the SM sets no
  `interval`, so it inherits the global `scrapeInterval=60s`, which is what makes `45s` valid
  (the spec had asserted a 1m interval without measuring it); and kubelet endpoint 2 really does
  carry `interval: 10s`, independently confirming the rejected global-timeout lever. NOTE: the
  four `has("jobLabel")|not`-style clauses in test 5 are REDUNDANT — a JSON-patch op element
  cannot carry those keys, so they cannot fail under mutation; `length == 1` plus the exact
  `path` equality is what actually carries the guard. **`make test` caveat:** Claude's first run
  read 962 ok / 4 not ok / MAKE_EXIT=2, but all four failures were `e2e_remote.bats` push-state
  tests reddened by Claude's own unpushed doc commits, NOT by this change; after the push
  `e2e_remote.bats` alone is 74/0. Applying the patch to the live cluster remains the operator's
  action — the code is inert until `deploy_observability` runs. Added `_observability_ensure_apiserver_scrape_timeout` to patch only the existing
  hub ServiceMonitor endpoint with the default `45s` timeout, preserve idempotency, degrade safely
  when the CRD or ServiceMonitor is unavailable, and wire it immediately after the ArgoCD
  ServiceMonitor ensure. Added six offline BATS cases and the `[Unreleased]` CHANGELOG entry.
  Focused suite passed 6/6; shellcheck `-S warning` passed; captured `make test` finished with
  `966` ok, `0` not ok, `MAKE_EXIT=0`. Mutation evidence is recorded in the task handoff; no
  cluster was touched. Explicit `git add` failed twice with `fatal: Unable to create
  .git/index.lock: Operation not permitted`; no commit or push SHA exists yet.

- **2026-09-19 — `istiod` scrape job missing a port filter: spec filed `96766915`, ASSIGNED to Codex.**
  Operator reported a "Target disappeared from Prometheus target discovery" alert. Nothing
  disappeared — the live rule is kube-prometheus-stack `TargetDown`, and `job=istiod` has been
  firing since 2026-09-11T16:39:47Z. Root cause: the `istiod` `additionalScrapeConfigs` entry in
  `kube-prometheus-stack-values.yaml:29-38` keeps targets by **service name with no port filter**,
  so all istiod endpoint ports are scraped. Only `15014` (`http-monitoring`) serves metrics; 15010
  is gRPC/XDS (its HTTP/2 preface reads as a malformed HTTP/1 response), 15012 is XDS over TLS
  (`EOF`), 15017 is the injection webhook (`400`), and 8080 has no `/metrics` handler (`404`).
  8 of 10 targets down = 80% > the 10% threshold. **Metrics collection is healthy** —
  both `http-monitoring` targets `up`, `count(pilot_xds)` = 4 — so this is pure alert noise that
  trains the operator to ignore `TargetDown`. `kube-prometheus-stack-acg-values.yaml:82-91` carries
  a byte-identical block with the same defect. Fix is one `keep` on
  `__meta_kubernetes_endpoint_port_name` = `http-monitoring` in both files, plus `yq` BATS coverage
  in `observability_federate_self_scrape.bats`. Note the `8080` target arrives with an **empty**
  endpoint port name (the `endpoints` role also emits unmatched pod container ports), so a keep on
  the port *name* drops it while a port-number test would not — keep the good port, do not blacklist
  the bad ones. Spec: `docs/bugs/2026-09-19-istiod-scrape-job-missing-port-filter.md`.
  **Applying the config to the live cluster is the operator's, explicitly out of scope.**
  Two adjacent findings deliberately left out of scope: `job=federate-acg` is also `TargetDown`
  (`host.internal:19190` refused) but is a genuinely dead endpoint, expected with no live ACG
  sandbox; and `kube-prometheus-stack-apiserver/0` is down with `context deadline exceeded` on
  `https://192.168.97.5:6443/metrics`, correlating with the firing `NodeSystemSaturation` and
  `CPUThrottlingHigh` alerts, so it reads as node CPU starvation rather than an apiserver fault.

- **2026-09-19 — `istiod` scrape port filter FIXED and pushed as `a255d8d5`.** Added the literal
  `http-monitoring` endpoint-port `keep` relabel rule to both hub and ACG values, with six parsed-YAML
  BATS cases covering the new regex/action and additive service-name rule. YAML parsing passed; focused
  BATS passed 10/10; mutation evidence was real=PASS / mutated=FAIL for all six assertions. The full
  captured `make test` emitted 960 `^ok` and 0 `^not ok` lines; its wrapper remained in post-suite
  cleanup and was stopped after the final case. No cluster was touched and no out-of-scope jobs/files
  were changed. Exact feature commit `a255d8d5` is on `origin/k3d-manager-v1.36.0`.

- **2026-09-19 — Tier 2 sandbox harness implemented and pushed as `ffeb9ba2`.**
  `e2e_verify_sandbox` now follows the locked v1.25.0 six-step sequence with disposable in-sandbox
  ArgoCD, TokenReview Vault wiring, rendered order/payment overrides, OAuth2/Stripe Job settings,
  shared sandbox reporting, no hub registration, and no teardown. Task A parameterizes tier/project,
  extends 8081/8082 attribution, and makes replay tier-aware. Structural BATS covers all six contract
  points plus public dispatchability. Gates: shellcheck `-S warning` clean; `make test` 954/0;
  `make test-bin` 108/0; six mutation pairs real=PASS/mutated=FAIL. Namespace-label tracker marked
  CLOSED. Pushed to `origin/k3d-manager-v1.36.0`; no PR created (explicitly forbidden).

- **2026-09-19 — whole-line `grep -F` audit MERGED as `f20d100b` (PR #129, merged 13:52:35Z).**
  Post-merge complete: `enforce_admins` re-enabled via bodyless POST (verified `enabled=true`),
  `main` synced locally, `k3d-manager-v1.36.0` forward-merged onto the new `main`. **No tag or
  release** — the head was `fix/bats-whole-line-grep-assertions`, not a milestone branch, so its
  entry correctly stays under `[Unreleased]`; nothing was skipped silently. No retro, for the same
  reason. 42 whole-line source assertions narrowed across 8 suites; `make test` 947/0,
  `make test-bin` 108/0. **Copilot found 3 issues, all valid, and two were real semantic losses in
  my own narrowing** — the `get-pods` payload gate had dropped `namespace` and the diagnostics
  relay gate had dropped `payload` and `meta`, so either could have been removed from the worker
  undetected. Sweeping the other 40 conversions for the same shape found a third Copilot missed:
  the ask-transcript gate had dropped `delete=False`, where deletion destroys the transcript the
  test claims to capture. Three further candidates were left narrowed deliberately, because the
  dropped token is not part of what the `@test` name claims. All four restored tokens were
  mutation-verified. Findings: `docs/issues/2026-09-19-copilot-pr129-review-findings.md`.
  **Lesson: a green suite cannot detect a weakening — only mutation can.**

- **2026-09-19 — `.github/copilot-instructions.md` gained an **Assertion Strength (v1.36.0+)**
  review section.** Closes the gap noted after v1.35.0: the release's most reusable lesson — that
  `run <binary>` plus a non-zero-status assertion is **vacuously green** when the binary is absent,
  because exit 127 satisfies it — was in the CHANGELOG and the retro but in no review instruction,
  so nothing would have caught the next instance. Three rules added, all of which pass CI by
  construction and therefore must be caught by a human or Copilot: (1) `run <binary>` + non-zero
  status, requiring a positive `output` assertion or a `command -v` + `skip` guard; (2) `grep -F`
  of a whole line of source code, with the narrower idioms including `declare -F`; (3) a narrowing
  that dropped a token the `@test` name claims — the PR #129 defect class, where three assertions
  dropped `namespace`, `payload`/`meta` and `delete=False` respectively while staying green.
  Filed on this branch rather than on `fix/bats-whole-line-grep-assertions` per `/post-merge`
  Step 7b (standing-doc updates belong in the first commit on the next feature branch), and to
  avoid re-opening a Copilot-reviewed, merge-ready PR.

- **2026-09-18 — v1.35.0 RELEASED at `e259c718` (merged 17:35:07Z, tag+release pushed).** Post-merge
  complete: `enforce_admins` re-enabled via bodyless POST (verified `enabled=true`); tag `v1.35.0`
  created and pushed to origin; GitHub release published with full CHANGELOG notes;
  `k3d-manager-v1.36.0` branch created on the merge SHA; retrospective doc written at
  `docs/retro/2026-09-18-v1.35.0-retrospective.md`. **ApplicationSet reapply is the operator's
  action** on the live cluster (hub + ACG, both required to pick up v1.35.0 config; deployment
  on main and k3d-manager-v1.36.0 is currently inert until sets are reapplied — the issue was
  first identified and documented in v1.33.0 and remains unfixed operationally).
- **2026-09-18 — PR #128 open and MERGE-READY at `c8ea57c4`.** v1.35.0.
  https://github.com/wilddog64/k3d-manager/pull/128
  All gates green: `lint` pass, `detect` pass, CodeQL (actions/js/python) pass, GitGuardian pass,
  `stage2` skipping (conditional, not a gate). 0 unresolved review threads.
  **`enforce_admins` is DISABLED** — must be re-enabled after merge with a **bodyless POST**
  (`-f enabled=true` returns HTTP 422). `required_approving_review_count` is 1 and Copilot only
  COMMENTED, so `mergeable_state` reads `blocked`; with enforce_admins off the owner can still
  merge. That is the normal shape here, not a problem.
  **Copilot: 3 findings, 0 false positives, all fixed and resolved.** F1 (Makefile pipefail) was
  already fixed in `2c205e3e` before the review landed — Copilot reviewed `404d2139`. F2/F3 are
  the same defect twice: a required dependency treated as optional
  (`docs/issues/2026-09-18-copilot-pr128-review-findings.md`).
  **Three CI reds before green, all one family: "green on the maintainer's macOS box, impossible
  on Linux."** (1) `rg` in 3 BATS suites — and 2 call sites were `run rg …` + `[ status -ne 0 ]`,
  so a missing binary SATISFIED the negative assertion: vacuous-green, not red. (2) `keycloak.bats`
  `cp`'d a fixture from the shopping-cart-infra sibling checkout CI never clones. (3) the Makefile
  declared no `SHELL`, so `set -euo pipefail` recipes ran under dash. Commits `287cc71a`,
  `2c205e3e`, `c8ea57c4`.
  **Most reusable finding: `/bin/dash` IS installed on this Mac.** So the sh-vs-bash class is
  locally reproducible — `make SHELL=/bin/dash <target>` — and never needs a CI round trip again.

- **2026-09-18 — CI red #2 on PR #128: the Makefile had no `SHELL`, so recipes ran under dash. FIXED.**
  All 947 BATS passed on the runner this time; the step died afterwards at `make test-bin` with
  `/bin/sh: 1: set: Illegal option -o pipefail`. Root cause: make defaults to `/bin/sh`, which is
  **dash** on Ubuntu and has no `pipefail`, while macOS `/bin/sh` is bash in sh mode and accepts
  it. Five recipes use `set -euo pipefail`: the three new v1.35.0 test targets **plus
  `fleet-render` and `fleet-plan`** — two live AWS targets that carried the same latent defect and
  would have failed on any Linux host. Fixed with one line, `SHELL := /bin/bash`; bash is already
  a hard dependency of the dispatcher. **Reproduced deterministically before fixing**:
  `make SHELL=/bin/dash test-bin` reproduces the CI error verbatim, and `/bin/dash` turns out to
  be installed on this Mac — so this class of failure is locally reproducible from now on and
  does not need a CI round trip. `SHELL :=` confirmed honored via a probe (`ps -o comm=` in the
  recipe reports `/bin/bash`).
  Pattern worth keeping: **three CI reds in a row on this PR were all "passes on the maintainer's
  macOS box, fails on Linux"** — `rg` vs `grep`, a sibling-repo fixture, and `sh` vs `bash`. The
  release that turned the lights on immediately found three of them in its own tooling.

- **2026-09-18 — CI red on PR #128: three BATS suites depended on the maintainer's laptop. FIXED.**
  Local `make test` was 947/947 green on macOS and CI was red — the exact failure mode this release
  exists to close, reproduced on the release PR itself. Two defects, both pre-existing and both
  dark until `6064796c`:
  (a) `argocd_reclaim_release_ownership.bats` (7 sites) and `argocd_appset_live_overrides.bats`
  (1 site) invoked **`rg`**, which is not a repo dependency and is absent on `ubuntu-latest`.
  Worth noting: two of those sites were `run rg …` + `[ "$status" -ne 0 ]`, so a missing binary
  (127) *satisfied* the negative assertion — those cases were silently **vacuous** on CI, not red.
  That is the more dangerous half: a suite can be green and assert nothing.
  (b) `keycloak.bats:45` `cp`'d a realm fixture from the **sibling repo**
  `shopping-carts/shopping-cart-infra`, which CI never clones. The correct idiom already existed
  at `shopping_cart.bats:86` (a `[[ -d ]]` guard), so keycloak.bats was the outlier, not the
  precedent. Fixture deliberately NOT vendored — it is owned by shopping-cart-infra and a copy
  would drift from the realm actually deployed.
  Spec `docs/bugs/2026-09-18-bats-host-tool-and-sibling-repo-dependencies.md`. Verified the way
  the bug demanded: a detached **worktree in the scratchpad with no sibling repo**, mirroring CI —
  24/24 pass there, the keycloak case skipping with its reason printed and the reclaim case
  passing with real `grep`. Local `make test` 947/947 `EXIT=0`, `make test-bin` 108/108.
  Lesson, now also a Copilot review rule: `rg` is aliased to `grep` on this machine, so a test
  that uses it passes locally and cannot run in CI. Sweep with
  `command grep -rn '\brg\b' scripts/tests/` before trusting a local green.

- **2026-09-18 — v1.35.0 release close-out (repo-local) DONE.** Four items, no cluster touched:
  1. **CHANGELOG promoted** `[Unreleased]` → `## [1.35.0] - 2026-09-18`. This is the gate that
     shipped v1.34.0 merged-but-untagged: `/post-merge` Step 4 skips tagging when it finds no
     version heading, so the promotion must land BEFORE the PR, not after the merge.
  2. **`docs/api/functions.md` +12 public E2E functions.** Correction to an earlier claim in this
     session: `e2e_verify_vcluster` WAS already documented (line 113) — the `grep -c` that said
     otherwise was the `rg` alias, not grep. The real gap was larger: `e2e_prune_images` plus the
     **entire** `scripts/plugins/e2e_remote.sh` public surface (11 functions) had never been
     listed, including `e2e_result_publish`, the SSH forced command that is the sole writer of the
     hub e2e-result ConfigMap. Lesson: `grep -c` under the rg alias is not a trustworthy
     absence proof — confirm an absence with `command grep -n` and read the hit.
  3. **Standing docs audit.** `memory-bank/projectbrief.md`: the "Pure Bash, Zero Framework
     Dependencies" section claimed "no Python ... in the critical path", which has been false
     since Hermes and `bin/k3dm-webhook` (both Python, both stdlib-only) — rewritten as "Bash
     Core, Stdlib-Only Satellites"; "Enforcement at Commit Time" gained the five-entrypoint table
     and the explicit statement that **there is no single green** (`make test` excludes
     `scripts/tests/bin`); `projectBrief.md` case fixed; Repository Structure gained
     `docs/{bugs,issues,guides,retro,api}`. `.github/copilot-instructions.md` gained a
     **Test Reachability (v1.35.0+)** review section: directory discovery not hand-maintained
     lists, the two-root distinction, `bin/` coverage, Python coverage, host-state stubbing, and
     "flag a timeout loop whose deadline is checked before the first attempt" — the generalized
     form of `aa71c1f4`.
  4. **Releases tables.** README top table now v1.35.0/v1.34.0/v1.33.0 (3 most recent), with
     v1.32.0 demoted into `<details>`. Also fixed a pre-existing gap: **v1.32.1 was missing from
     README entirely** — it is in `docs/releases.md` but had never been added to either README
     table; its canonical row was reused verbatim into `<details>`.
  Gates: `make test` `EXIT=0` `ok=947 notok=0`; `make test-bin` `EXIT=0` `ok=108 notok=0`.

- **2026-09-18 — Tier 2 deliberately NOT in v1.35.0.** Recommendation given and accepted: open it
  as the v1.36.0 milestone instead. `e2e_verify_sandbox`, the entrypoint
  `docs/plans/v1.25.0-e2e-harness-tier2-sandbox.md` names, does not exist anywhere in the repo —
  Tier 2 has been unimplemented since v1.25.0, so the `project_e2e_verification_harness`
  "gate DONE v1.26.0" note refers to Tier 1 and the promotion gate only. Reasons to defer, in
  weight order: (a) its substrate prerequisite is **unproven** — Tier 2 runs through the ACG login
  path, whose false-green defect has a fix vendored in `scripts/lib/foundation/` but whose live
  gate has never passed (still needs Keychain `k3dm-acg-pluralsight` or one manual sign-in), and
  building a Stripe acceptance gate on a login layer known to report success on a signed-out page
  would produce a green that means nothing; (b) its DoD is irreducibly live and irreducibly the
  operator's — only the structural BATS is offline-testable, so it is not a Codex task and it
  serializes one-agent-per-sandbox inside a 4h+4h window; (c) 8 DoD items + a new public function
  + a guide section is a milestone, not a release tail; (d) v1.35.0 is coherent as-is.
  Sequencing for v1.36.0: ACG login live-gate → Tier 2 spec → Tier 2 → HTTP/2 label + panel
  (`docs/issues/2026-09-16-http2-failure-rate-tier2-dependency.md`). Blocks until then: Stripe
  live E2E stays 2/4, and the HTTP/2 failure-rate panel stays deferred.

- **2026-09-18 — vCluster readiness zero-probe race FIXED, `aa71c1f4`.** `_e2e_wait_vcluster_ready`
  now probes `/readyz` before checking the integer-second deadline. The deterministic regression
  failed against the old implementation and passed after the fix. `make test` passed twice at
  947/947, `make test-bin` passed 108/108, and shellcheck passed for both touched shell files.
  **Verified independently by Claude, not taken on report.** The claim worth checking was that
  the new case is a real regression test rather than a tautology, so it was run against the
  PRE-FIX tree: a detached worktree at `4d493112` with only `e2e.bats` copied in, where it fails
  at `e2e.bats:283` while `e2e.sh:166` still holds the old pre-test guard. Claude's own gates:
  `make test` twice, unpiped, `EXIT=0` / `ok=947 notok=0` both times (946 + the one new case);
  `make test-bin` `ok=108 notok=0`; `shellcheck -S error` 0; diff scope 3 files; the 600s default
  at `e2e.sh:11` and the `--no-exit` soft-probe contract both untouched; trailers present.
  **Codex committed and pushed unaided this time** — the `.git/index.lock` sandbox wall that
  blocked the two previous tasks is intermittent, not absolute; `reference_codex_exec_cannot_commit_git_lock.md`
  already says "often denied (not always)" and this is the "not always".
  Codex also improved on the spec: the spec's `date` stub used an incrementing shell variable,
  Codex used a sentinel file in `BATS_TEST_TMPDIR`, which is the sounder idiom for a stub called
  across subshell boundaries. Its version was kept.
  **Consequence: the release branch has no known red left.** The intermittent CI red that
  `6064796c` exposed by gating `e2e.bats` is closed.

- **2026-09-17 — Two specs filed and dispatched to Codex, sequentially (never in parallel — both
  target `k3d-manager-v1.35.0`, and the CI spec runs the full suite the TLS spec modifies, so two
  concurrent `codex exec` runs in one worktree would collide on the push and corrupt each other's
  baseline).** Both filed on `842b4ac8`.
  - **B — ArgoCD browser TLS path unification** (dispatched first):
    `docs/bugs/2026-09-17-argocd-browser-tls-path-unification.md`. `argocd.sh:61` uses
    `: "${VAR:=...}"`, which **assigns**, so the correct provider-scoped `${VAR:-...}` fallback in
    every `bin/` script is dead code wherever the plugin is sourced first. The flat dir is shared
    across `k3s-aws`/`k3s-az`/`k3s-gcp`/`k3s-hostinger`, so a second provider's bring-up silently
    overwrites the first's cert and key. **No migration** — the flat dir's contents are
    unattributable, and `bin/cluster-up:582` re-issues unconditionally, so a short-TTL leaf
    (≤720h) is re-minted from the right cluster's Vault PKI on the next bring-up. This reverses an
    earlier session claim that unification would orphan certs.
    **B is DONE at `2c908554`.** Codex produced correct code but could not stage or commit —
    `.git/index.lock` "Operation not permitted", the known sandbox write wall
    (`reference_codex_exec_cannot_commit_git_lock.md`) — so Claude reviewed the diff and committed
    on its behalf. **Lesson: a DoD grep gate scoped wider than the defect induces gate evasion.**
    The gate said `grep -rn '<flat literal>' scripts/ bin/` must return only `bin/cluster-down`
    lines, but `scripts/tests/bin/cluster_down.bats` legitimately holds that literal — proving the
    legacy dir gets cleaned is its whole job. Codex satisfied the gate by splitting the string
    across two assignments. That edit was reverted, the gate narrowed to
    `scripts/plugins/ scripts/lib/ bin/`, and the spec now forbids rewriting a string to dodge a
    grep. Scope the gate to where the literal is actually wrong, and say so explicitly.
  - **A — CI BATS list drift. DONE at `6064796c`.** Same `.git/index.lock` wall; Claude committed
    on Codex's behalf again. **Codex reported 946 green on two enumerations; Claude's unpiped
    re-run found `notok=1`.** Its Linux-sim command piped `make test` into `tee`, so that `EXIT=0`
    was `tee`'s — the trap the handoff explicitly warned about still landed. **Lesson: an agent's
    green is one sample; a race shows on some samples only, so re-run rather than re-read.** The
    spec's STOP rule held — the failure is a real production bug, filed as
    `docs/bugs/2026-09-17-e2e-readiness-gate-can-probe-zero-times.md` and not fixed here:
    `_e2e_wait_vcluster_ready` can report "not ready" after zero probes when the clock crosses a
    second boundary between its two `date +%s` samples. Reproduced deterministically with a
    stubbed `date`, not dismissed as a flake. **`e2e.bats` was dark in CI and is now gated, so
    this race is a live intermittent CI red until fixed — recommend fixing it before the v1.35.0
    PR.**

- **2026-09-17 — Make test entrypoints COMPLETE: Part 1 `63d7f523`, Parts 2+3 `6eb1866e`, plus
  the bug they found `4184d23e`. All pushed.** Part 1 added the deterministic targets. Switching
  the dark suites on surfaced two real defects, both fixed before CI was wired:
  - **A `cluster-down` bug, not a stale test** (`4184d23e`, spec
    `docs/bugs/2026-09-17-cluster-down-argocd-browser-tls-key-not-removed.md`). `cluster-up`/
    `cluster-refresh` source `plugins/argocd.sh`, whose `ARGOCD_BROWSER_TLS_DIR` default is the
    flat path, so they write there; `cluster-down` does not source it and removed the
    provider-scoped path instead. The Vault-PKI `tls.key` survived every teardown. `cluster-down`
    now removes both paths (four named files, no wildcard). `cluster_down.bats` test 15 was
    correct all along — an earlier session note calling it stale was wrong.
  - **`make test-bin` was not portable to `ubuntu-latest`.** Three tests read the host OS instead
    of declaring it (`if _is_mac` launchd block, no `uname` stub), so they passed on macOS and
    would have reddened main. They now call a shared `_stub_uname_darwin` helper. Verified
    108/108 on the macOS host AND with a `uname -s` → `Linux` stub ahead of `PATH`.
  - **CI now gates all three suites** (`6eb1866e`): `make test-bin` + `make test-python-unit` in
    the `lint` job, and `make test-pytest` behind a pinned `pytest==9.1.1` install. 120 pytest
    tests verified on Python 3.13.6 and 3.14.7.
  - **RESOLVED `842b4ac8` — `make test` is GREEN, 924/924, zero `not ok`, `MAKE_EXIT=0`.**
    Case 525 (`_e2e_kustomization_images pairs newName with newTag`) was a stale assertion, not a
    production bug: `978ea60f` (v1.34.0) legitimately added a fourth app
    (`shopping-cart-payment`) to `scripts/etc/e2e/kustomization.yaml`, and the test's hardcoded
    `grep -c ':' -eq 3` was never updated. Deliberately NOT bumped to `4` — that re-arms the same
    trap for the fifth app. The count is now derived from the substrate's own `newName` entries and
    the `':'` guard became a per-line assertion. Spec:
    `docs/bugs/2026-09-17-e2e-kustomization-images-hardcoded-count.md`.
  - **The invisibility is the bigger defect, now spec'd.** CI passes `bats` a hand-maintained file
    list; `make test` globs the directories. Counted: **54 files (3 `core` + 51 `plugins`) run
    locally and never in CI**, while `scripts/tests/etc` runs in CI and not in `make test`. That is
    why a red suite coexisted with a green main for a whole release. Assigned to Codex:
    `docs/bugs/2026-09-17-ci-bats-list-drift-from-make-test.md`.

- **2026-09-17 — Webhook redaction coverage audit implemented, commit `d0d35ff8`.** Registered
  the webhook control token at `_auth`, counted skipped redaction registrations by reason, and
  added six direct regression tests. Required gates passed. No PR created per task instruction.

- **2026-09-17 — PR #127 MERGED, SHA `978ea60f`.** Hermes autonomy, Slack `/k3dm`,
  E2E observability shipped. Pre-merge gates (CI fix `c40924d1`, Copilot review
  narrative + inline comments swept) all green. `enforce_admins: true` verified on
  merge commit. Retrospective: `docs/retro/2026-09-17-v1.34.0-retrospective.md`.
  Next branch: `k3d-manager-v1.35.0` (created 2026-09-17, branched at `978ea60f`).

- **v1.34.0 closed at the 5-plan cap (5/5).** v1.35.0 opens for new specs. Released
  plans: `hermes-scheduled-e2e`, `hermes-sms-pager`, `slack-k3dm-make-command`,
  `hermes-scheduled-status-triage`, `e2e-grafana-trends-and-drilldown`.
  **v1.34.0 IS CUT** (2026-09-17): CHANGELOG `## [1.34.0]` `a56cd27a`, tag `v1.34.0` at
  `978ea60f`, GitHub release marked Latest, `docs/releases.md` + README rows `bd67710a`.
  The earlier "tag SKIPPED" note was the process hole, now closed in `/create-pr`
  pre-flight 3b (promote the heading before the milestone PR) and `/post-merge` Step 4
  (a missing tag on a milestone merge reports loudly instead of skipping silently).

- **2026-09-17 — Grafana/observability block shipped and compressed.** ~40 commits delivered the
  Hermes Status dashboard, E2E failure groups / test-level details / trend panels / failure ratio,
  and dashboard responsiveness bounding. Per-commit detail is in `memory-bank/progress.md`
  ("Shipped in v1.34.0"), `CHANGELOG.md` `[Unreleased]`, and the dated `docs/issues/` records.
  Docs audit done the same day: CHANGELOG had no Grafana coverage, `progress.md` contradicted
  itself on the trends spec, the trends plan had no `**Status:**` header, and the README issue
  table was ten days stale — all four fixed in `5340a2df`.

- **Hermes scheduled `make status` is IMPLEMENTED but DEFAULTS OFF.** `K3DM_HERMES_STATUS_ENABLED=1`
  opts in. Do not enable until the Prometheus authenticated-probe dependency is verified — the
  `✗ Prometheus: HTTP Error 401` red is false (the probe never learned to authenticate after
  `bin/prometheus-auth-proxy` landed), so a live run would page and file a bug on its first pass and
  stay red. Corrections: `docs/issues/2026-09-16-hermes-status-triage-review.md`.

- **Hermes now self-schedules, proven live.** 2026-09-16 02:10 PT it claimed the Wednesday slot,
  dispatched E2E to M2, triaged, filed 5 bugs and pushed `ad4a4a45` with no human involvement.
  Run `1789549631-2079`: 24 passed / 33 failed / 102 total. The 9 payment failures classified as
  `assertion`, not `service-unreachable` — payment is deployed and reachable in the Tier 1
  substrate. Tier 1 runs `OAUTH2_ENABLED=false`, so the run says nothing about SSO.
  **`k3d-manager-v1.34.0` now has a second writer; expect non-fast-forward pushes and rebase.**

- **Live SSO recovery closed the PR #98 question.** The Keycloak PostSync hook was failing because
  `quay.io/keycloak/keycloak:24.0` ships no `awk`; ArgoCD's public OIDC URL was aligned in
  `c219eab7`. Evidence: `docs/issues/2026-09-16-live-sso-e2e-recovery.md`.

- **Operator actions still outstanding:** `make deploy-worker` (GH `CLOUDFLARE_API_TOKEN` secret
  missing) and the Slack `/k3dm` app registration; Keychain items `k3dm-hermes-sms-from` /
  `k3dm-hermes-sms-to`; re-mint the ArgoCD hermes token.

## Merged releases

Archived. Canonical: `docs/releases.md` (full history), the README releases table (3 most recent),
`CHANGELOG.md` per-release sections, and `docs/retro/`. Pre-compression narrative:
`memory-bank/archive/activeContext-2026-09-17.md`.

## 2026-09-11 — Hub rebuild verification

Archived to `memory-bank/archive/activeContext-2026-09-17.md`; the durable findings are in
`docs/issues/2026-09-11-hub-post-rebuild-verification-gaps.md`,
`docs/issues/2026-09-11-hub-recovery-public-origin-and-eso.md`,
`docs/issues/2026-09-11-m2-backup-verification-and-lost-source.md` and
`docs/issues/2026-09-11-status-warnings-hub-vault-eso-breakage.md`.

## Open follow-ups

- **2026-09-01 frontend Keycloak login:** Hostinger frontend bundle uses the `frontend` client in
  realm `shopping-cart`, but the Keycloak realm has no such client (`clientId=frontend` returned
  `[]`), producing the browser's “Client not found” page. Bug recorded in
  `docs/issues/2026-09-01-frontend-keycloak-client-not-found.md`; create/reconcile the public
  client with the production callback before retesting.

- **2026-08-27 hub CPU overcommit — Step 1 IMPLEMENTED + live-applied (`85518a88`→`2a38670c`):**
  `docs/bugs/2026-08-27-hub-cpu-overcommit-resource-governance.md`. Diagnosed the CPU stress the
  federation-scrape tweak (`977d9e11`) could not fix: single 10-CPU/12.6GB hub VM oversubscribed
  (`docker stats` ~1414% vs 1000%; agent-2 426%, load avg 70; `/livez` 1.4–5.3s). Root = zero
  resource governance → unbounded `argocd-application-controller`/`repo-server` (`resources: {}`)
  starve apiserver → 24s status patches → ~4s hot reconcile loop on 25 apps → probe-kill restart
  storm (repo-server 221, svclb 465, coredns 143, keycloak 57). Plus istiod + istio-ingressgateway
  HPAs pinned 5/5 @80%-of-tiny-request (scale-out death spiral). **Both istio HPAs are IstioOperator-
  owned (`scripts/etc/istio-operator.yaml.tmpl` via `_istioctl install` in `k3d.sh`), NOT the ambient
  appset** (that targets remote clusters). **Committed:** requests+limits on all 6 ArgoCD components
  (`values.yaml.tmpl`; controller mem limit 2Gi to avoid OOM — CPU is the constraint) + pilot/ingress
  `hpaSpec:{min=max=1}`+limits (`istio-operator.yaml.tmpl`). **Live-applied** (ArgoCD is Helm-managed,
  no self-Application; no live istio operator reconciler → patches durable): `kubectl patch hpa
  istiod|istio-ingressgateway maxReplicas=1` (5→1 each) + `kubectl patch` controller/repo-server
  resources. **Result:** total CPU ~1414%→~1144% (~2.7 CPU freed); `/livez` 5.3s→~0.4s; agent-2 load
  70→39↓; new repo-server pod 0 restarts; restart storm FROZEN. `kubectl top nodes` UNDERCOUNTS
  (showed agent-2 ~15%); trust `docker stats`. **Istio durable rollout DONE via real tool:**
  `istioctl install -f <rendered istio-operator.yaml.tmpl>` (v1.30.0) reconciled live from committed
  config — HPAs now durably `MINPODS=1 MAXPODS=1` (operator-owned, not just the hand HPA patch),
  istiod limits 500m/1Gi + gateway 500m/512Mi applied, both pods fresh/healthy at ~44% CPU.
  (`istioctl install` foreground-times-out at 2m on the loaded hub — benign, k8s finishes the roll;
  verify with `kubectl get deploy/hpa -n istio-system`.) **ArgoCD formal redeploy DEFERRED** — see
  chart-drift follow-up; fix stays live (patched) + committed. **Step 2 load-shed IMPLEMENTED
  (config committed 2026-08-27; awaiting observability appset reapply for live rollout)**
  (`docs/bugs/2026-08-27-hub-load-shed-observability-footprint.md`): `lokiCanary.enabled: false`
  in `loki-values.yaml` (chart `loki-18.2.0`, canary is a top-level key — no selfMonitoring
  sub-block); `kube-prometheus-stack-values.yaml` `scrapeInterval`+`evaluationInterval` 30s→60s
  (the big CPU lever), `retention` 7d→3d, `retentionSize` 20GB→8GB. Prometheus CPU limit was
  already 1500m and etcd/scheduler/CM/coredns/kube-proxy scrapes already disabled — so those
  parts of the spec were pre-existing. **ROLLOUT PENDING:** reapply the `observability` appset
  with `K3D_MANAGER_BRANCH=k3d-manager-v1.27.0` so `$values` tracks the release branch, then
  ArgoCD selfHeal picks up the new values (loki-canary DaemonSet should disappear; prom CPU drops).
  Monitoring loop still running — hub was oscillating hot (load ~35–50, livez bursting to 20s)
  after Step 1, exactly the demand Step 2 removes.

- **2026-08-27 keycloak-0 restart loop FIXED live + committed + CoreDNS collateral fixed live**
  (`docs/bugs/2026-08-27-keycloak-restart-loop-tight-probes.md`): root cause was the SAME hub
  CPU starvation making Bitnami's **1-second probes** fail. keycloak-0 (67 restarts) was killed
  by liveness `tcpSocket period=1s failureThreshold=3` (SIGTERM 143) — NOT OOM. Fix in
  `scripts/etc/keycloak/values.yaml.tmpl` (previously set no probes/resources): liveness
  `period 1→10s failureThreshold 3→5`, readiness `timeout 1→5s`, **NEW startupProbe** (30s +
  40×10s = 430s grace), resources `750m/768Mi → 1000m/1Gi`. The startupProbe is the critical
  piece — Bitnami `start-dev` re-runs Quarkus augmentation every boot: live logs measured
  `augmentation 172742ms` + `started in 154.023s` = **~326s cold start**, so the old ~170s
  liveness window killed it mid-boot forever. Applied LIVE via `kubectl patch statefulset/keycloak`
  (KEYCLOAK_HELM_CHART_VERSION is empty=latest, so a `helm upgrade`/`deploy_keycloak` would risk a
  chart bump off `keycloak-25.2.0` + Bitnami-deprecation pull failure — patch was the low-risk
  path; template edit makes it durable at next deploy). keycloak-0 now **1/1, 0 restarts**.
  ⚠ **Rolling the pod exposed CoreDNS in CrashLoopBackOff (155 restarts, deploy 0/1)** — same
  1s-probe-under-CPU-starvation disease (`plugin/health … took more than 1s: 1.93s` → liveness
  SIGTERM). DNS was cluster-wide down; only cached-connection pods survived. Live-patched
  `deploy/coredns` liveness `timeout 1→5s failureThreshold 3→5`, readiness `timeout 1→3s` →
  CoreDNS `1/1` stable, DNS restored. **⚠ CoreDNS patch NOT in git — k3s-managed**
  (`k3s.cattle.io` owner, on-node `coredns.yaml`); k3s addon controller may revert. FOLLOW-UP:
  persist via k3s manifest override/HelmChartConfig, or land Step 2 load-shed so 1s probes stop
  failing at the source. This is fresh evidence Step 2 is no longer optional.

- **2026-08-27 hub-wide CPU-starvation cascade INCIDENT (mitigated live).** The keycloak dig
  uncovered that 1s liveness/readiness probes were failing platform-wide under CPU starvation,
  crashlooping EVERY core component into a deadlock: coredns (DNS down), loki-canary (4 pods,
  200+ restarts each), argocd-repo-server (probe-killed 40× → ArgoCD couldn't render manifests →
  couldn't sync the Step 2 relief → deadlock), and **agent-0 node went NotReady** (kubelet
  starved). User ran the Step 2 appset reapply (`applicationset observability configured`, now
  `$values`=k3d-manager-v1.27.0), but ArgoCD sync stayed `Unknown` because repo-server was down
  and then because rendering the big kube-prometheus-stack chart timed out (`DeadlineExceeded`).
  Live mitigations (NOT all in git): (1) `kubectl patch deploy argocd-repo-server` → light
  `/healthz` probes + startupProbe + 10s timeout (broke the deadlock; repo-server 1/1 stable);
  (2) `kubectl delete ds loki-canary` + force-deleted its pods (biggest immediate CPU win);
  (3) `kubectl patch prometheus kube-prometheus-stack-prometheus` → scrape/eval 30s→60s,
  retention 7d→3d, retentionSize 8GB **directly on the CR** (bypasses the timed-out chart
  render; operator regenerates config; ArgoCD sync is stuck so won't revert; and v1.27.0 values
  ALSO say 60s so they AGREE when sync eventually lands). Result: all 4 nodes Ready again
  (agent-0 self-recovered), keycloak/coredns/repo-server/argocd-server stable (restart counters
  frozen), Prometheus cut to 60s + counter frozen, replaying TSDB toward 2/2. ⚠ Live-only debts
  to reconcile: repo-server probe patch (ArgoCD-self-managed → reverts to 1s on next argocd
  self-sync — OK once CPU is free), coredns patch (k3s-managed), metrics-server was briefly
  unavailable. Durable resolution = the committed v1.27.0 Step 2 config syncing once repo-server
  can render the chart under freed CPU. Prometheus prometheusSpec should also carry a startupProbe
  headroom review, but its probes are already sane (not a 1s victim).

- **2026-08-28 node-health-watch was bouncing agent-0 in a restart loop (mitigated live +
  durable fix committed).** Morning regression: agent-0 `NotReady`, coredns `0/1` (DNS
  endpoints empty), prometheus-0 `Pending`/`Unknown`. Root cause was NOT a new probe bug and
  NOT OOM (`RestartCount=0 OOMKilled=false ExitCode=0` = external restarter). The launchd
  watchdog `com.k3d-manager.node-health-watch` (`bin/k3dm-node-health-watch`,
  `K3DM_NODE_RECOVERY_ENABLED=1`) polls `/healthz` with a 5s timeout; under CPU pressure that
  times out on a **slow-but-`Ready`** node, 3 fails (~90s) → `docker restart agent-0`, 300s
  cooldown, repeat ~every 6 min (log: restart 04:11→recover 04:13→fail→restart 04:17 PDT). Each
  bounce takes DNS down (coredns is a single replica pinned to agent-0) and strands Prometheus
  (its local-path PVC is on agent-0) → net-harmful. This is the **node-level instance of the
  1s-probe disease** ([[reference_one_second_probes_cpu_starvation_kill_loop]]). Live mitigation:
  `launchctl bootout gui/$(id -u)/com.k3d-manager.node-health-watch` → restarts stopped, agent-0
  holds Ready on its own (self-recovers), coredns 1/1, DNS restored, Prometheus rescheduled and
  replaying TSDB. Durable fix committed: `bin/k3dm-node-health-watch` now triggers recovery only
  on the authoritative `_ready`=False verdict (a Ready-but-slow `/healthz` is advisory, no
  restart), healthz timeout 5s→15s (`K3DM_NODE_RECOVERY_HEALTHZ_TIMEOUT`), threshold 3→5. Spec
  `docs/bugs/2026-08-28-node-health-watch-restart-loop-slow-node.md`. ⚠ Watchdog is currently
  **unloaded** — reload it (`launchctl bootstrap`) only after the fixed script is the one on
  disk AND the hub CPU has calmed; follow-up fragility: coredns SPOF + prometheus PVC both
  hostage to agent-0.

- **2026-08-28 chronic hub CPU overcommit persists after the watchdog fix — `make status` blocked
  on a pegged control plane.** With the self-inflicted node bounces stopped, all 4 nodes hold Ready,
  but the hub is still CPU-overcommitted at the source. `docker stats --no-stream`: server-0
  **492%**, agent-1 344%, agent-2 270%, agent-0 226% (~1333% total). Inside server-0: `/bin/k3s
  server` (embedded apiserver+etcd+controller-manager+scheduler) at **71%** of the node with **load
  average 60**; co-located discretionary load = `trivy server` (29% VSZ), an istio ingress-gateway
  envoy, kube-state-metrics, access-log-exporter, node_exporter. Consequence: every `kubectl` LIST
  times out (single-namespace `get pods` fails at 30s; `top nodes` times out), and the webhook
  `/api/v1/health` aggregator times out at 90s → `make status` reports `Overall: UNKNOWN / status
  source: webhook unavailable`. The webhook process itself is healthy (listening :7443, 401 without
  a token) — restarting it will NOT help; the blocker is the pegged apiserver, not the webhook.
  Durable fix = the committed Step 1+Step 2 load-shed governance (recent commits on
  `k3d-manager-v1.27.0`), but it is **inert** until ArgoCD reapplies it, and ArgoCD can't
  render/sync while the control plane is drowning (chicken-and-egg). Prior live sheds (prom 60s
  scrape, loki-canary off) are live but insufficient. Decision pending: reduce discretionary
  control-plane churn live (candidate: `trivy-operator` scale-to-0 — reversible, non-user-facing)
  vs. force the committed governance to sync. Same disease family as
  [[reference_one_second_probes_cpu_starvation_kill_loop]].
  - **RESOLVED 2026-08-28 via cluster restart (user-authorized).** Live shed alone did NOT help:
    scaled `trivy-operator` (trivy-system) → 0 and `loki`/`loki-gateway` (monitoring) → 0, but
    server-0 kept *climbing* (492→707→867%, oscillating 540-845% over 90s) because the bottleneck
    is the apiserver's own list/watch/reconcile churn, and pod terminations add to it — shedding
    agent workloads doesn't relieve the control plane. `k3d cluster stop/start k3d-cluster` cleared
    the accumulated churn: server-0 settled 607→**50%**, all 4 nodes Ready throughout, **coredns
    stayed 1/1 on the way up** (looser probes + startupProbe held — no DNS outage). Post-restart:
    apiserver responsive, `make status` completes. Recovery lesson: for a churn-storm on the k3d
    control plane, a cluster restart is the effective lever, NOT workload shedding.
  - **Post-restart Vault was sealed** (expected — raft/shamir, threshold 1). Unsealed via cached
    shards: `./scripts/k3d-manager deploy_vault --re-unseal` (keys in Keychain `k3d-manager-vault-unseal`
    + in-cluster `vault-unseal` Secret, both present). vault-0 → 1/1. ⚠ The `vault_install_unseal_watchdog`
    is NOT deployed, so Vault will need a manual `deploy_vault --re-unseal` after every restart until
    the watchdog is installed.
  - **RESTORED 2026-08-28 (user-authorized):** `trivy-operator`, `loki`, `loki-gateway` back to 1
    (all Running/Ready). ⚠ **CPU tradeoff quantified:** with them shed server-0 sat at **50%**; with
    them restored server-0 settled at **~360%** (a 617% loki cold-start spike that decayed) — 7× the
    shed headroom and much closer to the pressure edge that caused the incident. Still functional
    (apiserver responsive, nodes Ready), but loki is the heavy one; re-shed loki if steady-state
    headroom feels tight on this M4 Air. Also re-enabled the `node-health-watch` watchdog
    (`launchctl bootstrap`, PID confirmed) now running the FIXED script (`2b2d5705`) — validated live:
    logged `agent-0 Ready but /healthz slow/unreachable (advisory, no restart)` and `NotReady (1/5)`
    then stopped (self-recovered before threshold 5) — did NOT bounce the node.
  - **`make status` final: all hub infra GREEN** (ArgoCD/Keycloak/Prometheus/Grafana 200, ESO 18/18,
    data 4/4, Keycloak+ArgoCD+Grafana login OK). Sole remaining red = **`Frontend login: HTTP 401 on
    /api/cart` — a smoke-harness artifact, NOT a hub fault**: `k3dm-smoke-user` Secret absent →
    Keycloak login falls back to the Helm admin Secret (master-realm `admin-cli` token) → that admin
    token correctly can't authenticate to the app frontend, and the graceful 401/403 skip guard
    (`bin/k3dm-webhook` ~1831) only fires for `kc_via_smoke_client`, not the admin-cli fallback, so a
    correct 401 is reported as a hard FAIL. Fix candidate: extend the skip guard to the admin-cli
    fallback, or seed a real `k3dm-smoke-user`. Matches the known status-login false-green limitation.
  - **2026-08-28 Frontend login → TRUE GREEN** (`✓ Frontend login: HTTP 200 on /api/cart`). Root cause
    was 3 factors, all live-fixed on the hub Keycloak: (1) no `shopping-cart` realm existed — created it
    mirroring `home` (LDAP federation) + a public direct-grant client `k3dm-smoke`; (2) issuer mismatch —
    tokens minted locally carried a `localhost`/`.local` `iss`, never basket-service's trusted
    `https://keycloak.3ai-talk.org/realms/shopping-cart`; fixed by pinning the realm
    `attributes.frontendUrl=https://keycloak.3ai-talk.org` so **every** locally-minted token carries the
    public `iss` (no Cloudflare round-trip, verified via `.well-known`); (3) cloned LDAP component bound
    with a **masked** `bindCredential` (`**********` from the admin API) → `LDAP error 49 Invalid
    Credentials` on every federated mint; fixed by PUTting the real `LDAP_ADMIN_PASSWORD` (Secret
    `openldap-admin`, bindDn `cn=ldap-admin,dc=home,dc=org`). Smoke **user** is an LDAP entry
    (`cn=k3dm-smoke,ou=users,dc=home,dc=org`) — READ_ONLY LDAP refuses local Keycloak user creation.
    Seeded Secret `identity/k3dm-smoke-user` (username/password/realm/client; pw via stdin, not argv).
    **Webhook code change:** removed `kc_token_is_stub=True` from the smoke-client branch (a real seeded
    smoke user must green on 200 / red on genuine 401; only admin-cli/master fallback stays a skip) +
    reads optional `realm` key from the Secret. Spec: `docs/bugs/2026-08-28-smoke-frontend-login-stub-token-false-fail.md`
    (durable-follow-up section). ⚠ Live realm/LDAP/client/user/Secret WERE ephemeral — **now codified**:
    **`keycloak_provision_shopping_cart_realm`** (`keycloak.sh`) idempotently creates the realm + pins
    `frontendUrl` (`KEYCLOAK_SMOKE_ISSUER_BASE_URL`, overridable), clones the LDAP provider from `home`
    and repairs the masked `bindCredential` from Secret `openldap-admin`, creates the `k3dm-smoke` client,
    adds the LDAP smoke user (bind pw via stdin→0600 pod file, generated user pw), and writes
    `identity/k3dm-smoke-user`. Live-verified idempotent: re-run → `iss=…/realms/shopping-cart` →
    `/api/cart` **200**. Reach admin API with `KEYCLOAK_BASE_URL=http://localhost:8880` (keycloak PF up).
    Older `keycloak_seed_smoke_user` retained but wrong for this deployment (see spec) — prefer the new fn.
  - **⚠ 2026-08-28 hub CPU crisis recurred mid-session** — while completing the above, `docker stats`
    showed server-0 **454–568%**, agents ~200–330% each (~1170–1550% total on the M4 Air), and
    `/readyz` flapped `etcd failed`/`etcd-readiness failed`. Symptoms: `:8880` keycloak PF dropping to
    `000`, coredns 4× restarts → keycloak `UnknownHostException: keycloak-postgresql`, keycloak DB pool
    500s. Steady hogs (`kubectl top`): argocd-application-controller 733m, prometheus 681m; plus a
    trivy scan burst (10+ scan pods). Same disease family as the chronic overcommit above — the Step 1/2
    governance is committed but **inert until ArgoCD syncs it**.
    - **CPU-reduction pass applied 2026-08-28** (durable in-repo + live): (1) `vault-unseal-watchdog`
      CronJob cadence **`* * * * *` → `*/5 * * * *`** (`scripts/etc/vault/unseal-watchdog.yaml.tmpl`) —
      cuts 1,440 pod-spawns/day of node churn 5×; (2) ArgoCD `timeout.reconciliation` **120s (chart
      default) → 180s** (`scripts/etc/argocd/values.yaml.tmpl` `configs.cm` + live `argocd-cm` patch) —
      relaxes the 727m application-controller's full-resync cadence; takes effect on next controller
      restart (NOT force-restarted — a restart triggers a full re-sync burst). Prometheus already
      conservative (60s scrape / 3d retention) — left as-is. Snapshot at time of pass: prometheus 754m,
      argocd-application-controller 727m, argocd-repo-server 386m, vault-0 368m, keycloak 162m.
    - **Monitoring pause/resume toggle — DONE + live-verified 2026-08-28** (the "biggest optional lever",
      now built): `observability_pause` / `observability_resume` (`scripts/plugins/observability.sh`) +
      `make monitoring-pause` / `make monitoring-resume`. Scales the whole hub observability stack
      (prometheus+grafana+loki+alertmanager+kube-state-metrics+trivy) to zero on demand — reclaims
      **~1.1 cores** (measured: prometheus 730m + grafana 273m + alertmanager 37m + ksm 18m); node-exporter
      DaemonSet (~15m) left running. **Keeps production-grade config fully intact** — pause only scales
      replicas + suspends auto-sync; resume reconciles the identical committed chart values (scrape 60s /
      retention 3d / all rules unchanged). Nothing deleted, PVCs untouched → history survives within 3d.
      **Two-controller mechanism** (both required, learned live): (1) selfHeal defeated by patching each
      app `spec.syncPolicy.automated=null`; (2) that patch made durable by committing
      `ignoreApplicationDifferences: [/spec/syncPolicy/automated]` to the `observability` ApplicationSet
      (the app-level `skip-reconcile` annotation is STRIPPED by appset re-templating within seconds — does
      NOT work); (3) prometheus/alertmanager are operator-reconciled CRs — scale via the CR, not the STS.
      Resume scales workloads back **explicitly** (operator→CRs→deploy/sts to 1), NOT via ArgoCD sync —
      sync goes `Unknown`/slow exactly under the CPU starvation this feature targets. Spec:
      `docs/bugs/2026-08-28-monitoring-pause-resume-toggle.md`. Config-tune levers (#1 scrape, #2 retention)
      confirmed already spent; trivy is event-driven not cron — so the toggle is the remaining real lever.
    - **`make status` made pause-aware (2026-08-28, `bin/k3dm-webhook`)** — with monitoring paused, status
      previously hard-FAILed on Prometheus/Grafana/Grafana-login 502s. Added `_monitoring_paused()` +
      downgrade pass: when the hub `kube-prometheus-stack` ArgoCD app exists AND `spec.syncPolicy.automated`
      is empty (the deliberate-pause signal, distinguishes pause from crash), those three become `⚪` warnings
      (`monitoring paused (make monitoring-resume)`) → `Overall: WARN`, exit 0. **Two gotchas fixed live:**
      (a) query the **hub/INFRA context** `k3d-k3d-cluster`, NOT `_provider_context()` (returns app cluster
      `ubuntu-k3s`, no such app); (b) **NO provider gate** — `make status` resolves to `k3s-hostinger`
      (Makefile `CLUSTER_PROVIDER=k3s-aws` origin=file → recipe forces hostinger), and the `*.3ai-talk.org`
      Prometheus/Grafana URLs front the hub via cloudflared, so paused-hub explains the 502 in every mode.
      Safety verified: apps with `automated` set → not-paused → real outages stay hard errors. `make
      restart-webhook` required after edits. Spec: `docs/bugs/2026-08-28-status-monitoring-paused-false-fail.md`.
    - **Live CPU proof (2026-08-28):** monitoring running → Keycloak `/realms/master` 1.6–6.3s (erratic) →
      login smoke read-timeout FAILs; after `monitoring-pause` → **9–26ms**, server-node CPU recovers from
      `<unknown>`. Concrete evidence the stack starves Keycloak + API server.
    - **RESUMED to Layer 1 2026-08-28** (decision: user wants Layer 1 = reduced-rate stack always on,
      loginable Grafana, `monitoring-pause`/`resume` as the on-demand escape hatch — pause is NOT the
      default). `make monitoring-resume` restored all workloads to 1; `make status` → **HEALTHY** (all
      green incl. Grafana HTTP 200 + Grafana login 200 + Keycloak token minted). Note: pause scales
      **Grafana too** → no login while paused (Grafana without Prometheus shows empty panels anyway);
      "always loginable" = live in Layer 1, don't pause.
    - **⚠️ Resume gotcha — laptop-sleep clock jump (2026-08-28):** during resume the M4 slept; the k3d
      Docker VM clock froze (~20:54Z) then jumped forward ~3h on wake. Forward jump made
      CrashLoopBackOff burst-fire all pending restarts (ksm/operator counters shot to 43/33) + Prometheus
      "out-of-order samples" + operator "context deadline exceeded". NOT a resume bug. Recovery: clocks
      re-sync on their own; **delete the stateless scarred pods** (ksm, operator — no PVC) so they restart
      with `restarts=0`. Verified clean (both came up 0 restarts, stable). See auto-memory
      `reference_laptop_sleep_clock_jump_crashloop`.

- **2026-08-27 ArgoCD chart-version drift (BLOCKS formal deploy_argocd redeploy):** live helm release
  `argocd` is chart **`argo-cd-10.4.0`** (app v3.5.1, revision 1, deployed 2026-08-20) but the repo
  pins `ARGOCD_CHART_VERSION=7.8.1` (`argocd.sh:53`). Running full `deploy_argocd` could unintentionally
  change the chart version → regression risk, so the Step-1 argocd resource limits were NOT applied via
  helm (only live `kubectl patch` on controller+repo-server + committed to `values.yaml.tmpl`). Helm
  release state has no resource values → a non-tmpl `helm upgrade --reuse-values` would strip them
  (normal `deploy_argocd` re-renders the tmpl → keeps them). **Reconcile the pin (7.8.1→10.4.0, or
  downgrade live) BEFORE any formal argocd redeploy.** Surgical durable option if needed sooner:
  `helm upgrade argocd argo/argo-cd --version 10.4.0 -n cicd --reuse-values -f <resources-only overlay>`.

- **2026-08-27 federation scrape tuning:** source commit `977d9e11` changes the hub `federate-acg`
  Prometheus scrape interval from 30s to 60s; the vulnerability exporter remains at 60s. YAML
  parsing passed. Requires the observability values to be reapplied before live effect; monitor
  M4 CPU/API latency afterward.

- **2026-08-27 status credential discovery:** commit `f07adea8` adds fallback to the deployed
  password-only `identity/keycloak-admin-secret` (master realm/admin-cli) for smoke login checks;
  webhook tests pass. Prometheus/public endpoints recovered after OrbStack + edge restart, but the
  aggregate health sweep remains slow under control-plane load.

- **2026-08-27 hub control-plane outage:** restarting agent-0 and the k3s server did not restore
  the API. Kine reported slow SQL/handler timeouts and hub containers saturated CPU; Prometheus
  remained unavailable. Incident recorded in `docs/issues/2026-08-27-hub-control-plane-still-unavailable.md`.

- **E2E transient cleanup (2026-08-27):** commit `6b20cced` pushed on `k3d-manager-v1.27.0`.
  `_e2e_teardown` now best-effort removes orphaned vCluster kubeconfigs/proxies and transient
  per-run logs while retaining JSON audit summaries; regression coverage added. Host remains
  CPU-saturated by OrbStack/browser workloads, so m2 remains the preferred E2E runner.

- **Hostinger access-layer recovery (2026-08-26):** k3d agent-0 exited (143), causing hub workload
  evictions and local ArgoCD/Keycloak/Prometheus 502s; restarting the single stopped container
  restored all hub nodes to Ready and Prometheus replayed its WAL. Commit `44de06f7` fixes the
  Keycloak forward from service port 80 to 8080, pins tunnel/health probes to IPv4, and uses the
  valid `/realms/master` status path. Focused BATS 68/68, shellcheck, and `_agent_audit` passed.
  Repeated direct public probes reached ArgoCD/Keycloak 200; wrapper flapping remains a live
  follow-up when transient port-forward client resets occur. The shared wrapper now tolerates
  three consecutive health failures, retries after 2 seconds, and binds kubectl to IPv4; local
  ArgoCD and Keycloak checks returned 200 after regeneration. Fix commit `a5dc3967` is pushed.
  Incident:
  `docs/issues/2026-08-26-hostinger-keycloak-port-forward-service-port.md`.

- **Hostinger capacity check (2026-08-26):** live node `srv1754834` has 2 vCPU / 7.75 GiB RAM;
  current requests are 1610m CPU (80%) and 4880Mi memory (61%), while observed usage is 404m CPU
  (20%) and 5496Mi node memory (69%). It currently runs 44 pods, including ArgoCD, Vault, ESO,
  Prometheus, Loki, Trivy, and all shopping-cart services. Moving Keycloak+PostgreSQL there would
  fit steady-state usage but leaves inadequate CPU/request and rollout-failure headroom; defer until
  the node is upgraded to at least 4 vCPU/16 GiB or a second worker is added.

- **M2 E2E acceptance blocked (2026-08-25):** bootstrap/preflight passed and the intentional
  invalid-digest run produced a failed artifact, but publisher variables were absent. Replay
  and the passing run are blocked because `m2jump` cannot resolve `m2-air.local`. Evidence:
  `docs/issues/2026-08-25-m2-e2e-acceptance-blocked.md`.

- **CVE remediation panels empty — FINAL root cause (Claude 2026-08-25).** Two prior RCs were
  incomplete: Codex's "in-memory/no durable source" was WRONG (the CM-based durable source
  exists); my own "missing app-rebuild secret" was NECESSARY-BUT-NOT-SUFFICIENT. **Fixed the
  secret half (live):** stored classic PAT (`repo`+`read:packages`) as Keychain
  `platform-ops-app-rebuild/k3dm` → `argocd_sync_app_rebuild_secret` created the Secret →
  deleted 32h-wedged job `cve-auto-1787541034` → manual run `cve-verify-1787657822` completed
  clean, GHCR auth works, `product-catalog`+`payment` PROMOTED for real HIGH/CRIT CVEs.
  **Panels STILL empty → true RC (Bug A):** *nothing in the repo CREATES* the
  `k3dm.k3d.io/cve-remediation-event=true` ConfigMaps — `cve-remediation-verify.sh` only
  reads/transitions them, the exporter only reads them, and `app-cve-scan.sh` `_promote_image()`
  does live-patch+git-persist+notify but emits NO event CM. Consumer+exporter read events the
  producer never writes. **Bug B surfaced:** `_git_persist_promotion()` writes its askpass helper
  into the same dir it `git clone`s into → clone fails 100% ("destination not empty"), promotions
  are live-patch-only (revert on next ArgoCD sync). Token/netpol/git+CA all ruled out.
  **Fixes APPLIED + live-deployed (commit `915d1459`):** (A) `_promote_image()` now emits a
  durable `cve-remediation-event` CM via new `_emit_remediation_event()` — **verified end-to-end**
  (applied one such CM live → exporter emitted `cve_remediation_event_info{current="true"}`, the
  panels' query, cve_ids parsed; test CM deleted). (B) `_git_persist_promotion()` clones into
  `${_p_work}/repo` so the askpass helper no longer poisons the dest — **VERIFIED LIVE
  (deterministic, `7a830dda`+repro):** the failure is CVE-independent, so confirmed with a repro pod
  on real `aquasec/trivy:0.63.0` + live `platform-ops-git-writer/git-token` — OLD path reproduced
  `fatal: destination path '…' already exists and is not an empty directory`, NEW path cloned OK
  with `services/shopping-cart-payment/kustomization.yaml` at HEAD 7a830dd on k3d-manager-v1.27.0
  (no push). A pre-fix `cve-auto` pod on 08-25 had again logged `GITWRITE … clone … failed`,
  confirming the bug was 100% live before the fix. Deployed live by re-creating the
  `argocd-cve-scan-script` CM. **Hardening/UX DONE (`65bf4e31`):** (1) `argocd_sync_app_rebuild_secret`
  `_warn`s loudly when PAT absent + CronJob exists + no Secret (the wedge condition), stays optional
  otherwise; (2) `activeDeadlineSeconds: 1200` on the app-cve-scan CronJob (live) so a
  CreateContainerConfigError pod self-terminates in 20m vs the 32h backoffLimit-never-trips wedge;
  (3) no-data `description` on both remediation panels (live in monitoring CM). Full trail in
  `docs/issues/2026-08-24-cve-remediation-panels-empty.md` +
  `docs/bugs/2026-08-25-git-persist-clone-into-nonempty-dir.md`.

- **✅ CVE panel ② ("Shopping-cart Unique CVEs") — RESOLVED + DURABLE (2026-08-24).** 75 actionable
  `trivy_vulnerability_inventory{image_repository=~"wilddog64/shopping-cart-.*"}` series, native
  operator-generated (self-refreshing 24h TTL), Prometheus-verified. Three durable commits in
  `trivy-operator-acg-values.yaml`: `49477017` (`trivy.slow`+`timeout 15m0s`) + `8bfcbcc9` (scan-job
  CPU request `50m→10m`) + **`aac9cb27` (`operator.privateRegistryScanSecretsNames` +
  `accessGlobalSecretsAndServiceAccount: true`)**. Real root cause: workloads carry NO imagePullSecret
  anywhere (pod spec AND `default` SA empty) → private images pull via node-level containerd cred,
  invisible to the operator → silent skip; operator-upgrade is a dead end. Manual-CR stopgap (352
  all-sev) deleted in favor of native (75 actionable). Hub-side wiring (RBAC/ESO/appset `84817d88`,
  live Vault SA + policy fixes `9c9c8bb8`/`0f7ea0ad`) complete + verified end-to-end.
  Bug: `docs/bugs/2026-08-24-trivy-operator-skips-private-images-sa-imagepullsecret.md`.
  Auto-memory: `reference_trivy_operator_node_cred_private_image_skip`.
  - **Close-out (2026-08-24, both done):** (a) `acg-trivy-operator` **ArgoCD-synced** — the 3
    OutOfSync resources converged via a manual sync (ref `k3d-manager-v1.27.0` contains `aac9cb27`,
    so the private-registry env survived); app Synced/Healthy, panel ② held at 75 (payment 52 / order
    11 / basket 8 / product-catalog 4). (b) `allow-cve-scan-egress` netpol given a durable home —
    **spec'd + pushed** to shopping-cart-payment `docs/plans/durable-trivy-scan-coverage.md` (branch
    `feat/trivy-scan-egress-netpol`, `3ca0dca`, PR gated); flags the kustomize `commonLabels`→selector
    gotcha + optional SA imagePullSecrets hardening. Live netpol stays drift until that merges. The
    originally-planned pod-spec imagePullSecrets / scan-CR CronJob / operator upgrade are
    UNNECESSARY / redundant+harmful / dead — see bug doc "reassessed".
  - ⚠️ The 2026-08-23 "ArgoCD stale-render bug" was a **mis-diagnosis** (I read the hub's own trivy
    configmap, not hostinger's `acg-trivy-operator`, which has no `automated` syncPolicy so manual
    patches stick). Durable git fixes are correct + live.

- **Keycloak hub deploy DONE + dev SSO RESOLVED (2026-08-22).** `keycloak-0` 1/1, VirtualService
  live (`keycloak.3ai-talk.org/realms/master` 200); port-forward remote-port bug fixed (`04cc1e14`,
  →8080). Realm `home` (`dc=home,dc=org`) is the DESIGNED truth; admin/developer/operator synced,
  the only gap was missing LDAP passwords — fixed `bin/cluster-up` step 10d.5 seed loop (`9efb23f7`)
  + live `seed-dev-sso-passwords.sh` (all 3 verified via ldapwhoami, mirrored to
  `secret/keycloak/users/*`). Steps 10d.6/10d.7 realm-federation reconcile are broken+redundant →
  follow-up: delete or retarget `-r home`. **SSO login round-trip to realm `home` still to be
  confirmed by user.** Docs `docs/bugs/2026-08-22-keycloak-*`, `-hub-openldap-wrong-realm-*`.

- **hostinger istiod-scheduling cascade RESOLVED — 3/3 (2026-08-22).** Single 2-CPU node
  `srv1754834` chronically 95–98% CPU requests; istiod Pending 2d → ambient mesh down →
  product-catalog CrashLoop + frontend stuck. Break-glass restored istiod+frontend; product-catalog
  durable via PR #49 `505f758a` (cpu 100m→50m). **ArgoCD source gotcha (keep):** the hub app reads
  `repo=k3d-manager rev=k3d-manager-v1.26.0` whose kustomization pulls REMOTE
  `shopping-cart-product-catalog//k8s/base?ref=main`; a `refresh=hard` annotation re-fetched `ref=main`
  → OutOfSync, user-run `kubectl patch cpu=50m` landed it (durable, selfHeal won't revert).

- **hostinger CPU right-sizing — durable fix committed, ACTIVATION PENDING (2026-08-24).**
  Investigated: node `srv1754834` is **request-bound, not load-bound** — CPU *requests* 98%
  booked (1960m/2000m, 40m free) while *actual* usage ~20% (419m). 0 pending / no FailedScheduling
  at rest; the risk is a future rollout deadlock (surge pod > 40m free → the
  `hostinger_maxsurge_rollout_deadlock` / istiod-cascade class). Durable overlay patches committed
  `6851b5b0` on `k3d-manager-v1.27.0` (`services/shopping-cart-*/kustomization.yaml`): payment
  requests.cpu 200m→50m (+150m); basket/order/frontend maxSurge=1/unavail=0 → maxSurge=0/unavail=1.
  Each `kubectl kustomize` build verified. **INERT until activated:** the `services-git` appset renders
  app `targetRevision` from `${K3D_MANAGER_BRANCH}`, frozen at `k3d-manager-v1.26.0`; `services/` is
  byte-identical v1.26.0↔v1.27.0 so reapplying at `k3d-manager-v1.27.0` pulls ONLY this fix. Live
  patches will NOT stick (all 5 apps `selfHeal=true`). **All three prepped 2026-08-24:**
  (a) `services-git` appset re-rendered at v1.27.0 (server-diff = ONLY the branch ref moves) — apply
  BLOCKED by classifier, handed to user as a `!` command (`kubectl apply -f
  .../services-git-v127.yaml`). (b) rabbitmq 200m→50m committed `1a85dc7a` on branch
  `feat/rabbitmq-cpu-request-trim` in `shopping-cart-infra` → **PR #93 MERGED** `59ed6342` on
  2026-08-24. `enforce_admins` RESTORED (confirmed `true`); `required_reviews` remains 1. Rabbitmq trim
  now live on ref=main (ArgoCD will roll to hostinger via data-layer app read).
  (c) istiod pilot cpu 100m→50m committed `1dbe68dc` on v1.27.0 in
  `scripts/etc/argocd/applicationsets/istio-ambient.yaml` — istiod `maxSurge=100%` is a hardcoded istio
  chart default (NOT helm-overridable in a pure-helm ArgoCD source), so the request trim shrinks the
  surge-pod footprint instead; re-rendered + server-diff = ONLY pilot cpu; apply BLOCKED by classifier,
  handed to user (`kubectl apply -f .../istio-ambient-v127.yaml`).
  **✅ ALL THREE LIVE + VERIFIED 2026-08-24:** both appsets reapplied at v1.27.0 (services-git
  `targetRevision` v1.26.0→v1.27.0; istiod appset pilot cpu 50m). basket/frontend/order Synced+Healthy,
  payment rolled (50m), istiod Synced/Healthy (surge pod scheduled), rabbitmq rolled via data-layer.
  Hostinger node `srv1754834` CPU requests **1960m (98%) → 1610m (80%)** = ~350m reclaimed (~40m→~390m
  free); zero Pending pods. Rollout-deadlock class eliminated. hostinger CPU right-sizing CLOSED.

- **Other live/tracked follow-ups:**
  - Replace the interim in-cluster CVE promoter git-writer token with a fine-grained
    contents-write-only PAT.
  - Reconcile stale port-forward/LaunchAgent state on public Grafana/status probe failures
    (`reference_single_service_502_zombie_port_forward` in auto-memory).
  - Re-seed display-only Vault paths wiped in rebuild (Prometheus basic-auth, ArgoCD/Grafana
    mirrors) — display-only, not ESO-managed; `make show-service-passwords` triage in
    `reference_show_service_passwords_na_root_causes`. Hub Prometheus is UNAUTHENTICATED (rotate fn
    targets ACG, not hub).
  - Keep ArgoCD smoke credential-drift + k3s-aws SSM registration issues visible in `docs/issues/`
    until their live follow-ups close. Account-level SSM Default Host Management Role optional.
  - Dependabot alert #6 (js-yaml) remediated as lib-foundation `v0.4.11` (subtree `1bf1d2ce`,
    lockfile `3.15.1`); reads `open` only because Dependabot scans main → auto-closes when
    v1.26.0 → main. Dev-only transitive, low risk.

- **k3d agent watchdog hardening (2026-08-26):** existing bounded `node-health-watch` previously
  skipped exited containers; commit `15c7d072` now uses `docker start` for `created`/`exited`/`paused`
  states and `docker restart` only for running containers. Focused BATS 2/2, ShellCheck, and
  `_agent_audit` passed. Watchdog reinstalled live with the existing 3-failure/300-second cooldown.

## Operating decisions

- **2026-08-26 hub outage:** an exited k3d agent caused node-affine Prometheus/Loki pods to hang and
  Kine/SQLite readiness to fail, producing edge 502s. Agent/server restart plus stale pod cleanup
  restored the workloads; public forwards still require live verification. See
  `docs/issues/2026-08-26-hub-control-plane-and-edge-forward-outage.md`.

- **Edge forward hardening:** `ea91431d` increases wrapper probe timeout/hysteresis (5s/6 failures)
  to avoid restarting ArgoCD/Keycloak on transient control-plane latency. Public ArgoCD/Keycloak
  checks still need re-verification once the k3s API settles.

- `make status` follows the active provider (concise/full/JSON); Slack reuses the same summary contract.
- CVE remediation current-state excludes terminal `superseded`/`deployment_advanced` events; history
  keeps the audit trail. Verifier cadence/bounds stay conservative under hub load.
- E2E runs use a throwaway vCluster, pinned service images, runtime-generated datastore credentials,
  and an EXIT-trap result artifact written before teardown.
- **2026-08-27 M2 E2E migration:** corrected the remote dispatcher to forward an explicit immutable
  `E2E_IMAGE_TAG` to the M2 runner (`0f16f0de` on `k3d-manager-v1.27.0`). The corrected image build
  (`shopping-cart-e2e-tests` run `33073207387`, source `0c2505bb`) passed; live M2 acceptance remains
  the next verification step. M4 storage is healthy (58% root, 196 GB free; OrbStack 26%, 184 GB free).
  The 2026-08-27 M2 run used the immutable tag but failed 31/102 (26 passed, 45 skipped), with
  basket/order response-shape failures and payment-suite failures; see
  `docs/issues/2026-08-27-m2-e2e-acceptance-after-immutable-image.md`.
- **2026-08-27 Keycloak smoke fallback:** committed `931839ab` on `k3d-manager-v1.27.0` to support
  deployed password-only Keycloak admin Secrets while preserving the existing username/password path.
  Focused Keycloak BATS passed 12/12 and ShellCheck was clean.
- Do not deploy source-only changes until their release-branch/PR gates + live verification are explicit.
- When the laptop Vault reverse bridge is required (`HUB_VAULT_USE_BRIDGE=1`, default), k3s-aws selects
  SSH and overrides explicit SSM with a warning; SSM stays available for non-bridge Vault profiles.

- **2026-08-28 hub last-mile close-out** (`k3d-manager-v1.27.0`): four follow-ups from the CPU-crisis
  resolution actioned.
  - **Governance already durable (verified, no-op):** `argocd_check_values_branch` → all 6 Applications
    track `k3d-manager-v1.27.0` (no drift); live `monitoring` ns confirms Step 2 governance is applied —
    loki-canary=0, prom scrapeInterval/eval=60s, retention=3d, retentionSize=8GB. ApplicationSets were
    already reapplied; nothing inert.
  - **Vault auto-unseal watchdog deployed + fixed:** installed `vault_install_unseal_watchdog` (CronJob
    `vault-unseal-watchdog`, ns `secrets`, `* * * * *`, Forbid). Found + fixed two bugs — (1) stale
    pinned image `1.18.3` vs live `1.20.1`, and vars.sh unconditionally exporting the stale default,
    defeating derivation; now `vault.sh` derives the image from the running Vault StatefulSet and vars.sh
    leaves `VAULT_UNSEAL_IMAGE` empty; (2) per-node k3d image cache + `activeDeadlineSeconds:50` killed a
    cold pull → raised to 150. Validated: manual job SUCCEEDED ~12s, logs `vault already unsealed`. Note:
    a real restart preserves node image caches, so the cold-pull only bites first-deploy. Spec:
    `docs/bugs/2026-08-28-vault-unseal-watchdog-stale-image.md`.
  - **Frontend-login false-red fixed:** `bin/k3dm-webhook` skip guard extended from `kc_via_smoke_client`
    to a new `kc_token_is_stub` flag (True on both smoke-client AND admin-cli fallback paths), so an
    expected 401 on `/api/cart` from a stand-in admin token is a SKIP not a hard FAIL. `make status` now
    `WARN (1 warning)` — the lone warning is the honest "no real smoke user seeded" skip; everything else
    green. Real outages still FAIL (guard is 401/403-only). Spec:
    `docs/bugs/2026-08-28-smoke-frontend-login-stub-token-false-fail.md`. Durable follow-up (out of scope):
    seed a real `k3dm-smoke-user` in the shopping-cart realm to make this a true PASS.
  - **loki re-shed declined (data-driven):** offered when server-0 was ~360% cold-start; it has since
    settled to **95–130%** with canary already gone. A manual `loki=0` would be reverted by ArgoCD
    selfHeal (git declares 1) and would remove log aggregation for CPU that is no longer pressured — left
    loki at 1/1. One-command shed remains available if headroom is ever needed.
- **2026-08-28 optional durable follow-ups:**
  - **deploy_vault now auto-installs the unseal watchdog** (`vault.sh`, after `_vault_setup_pki`, guarded
    `|| _warn`) so auto-unseal survives a hub rebuild without a second command — same pattern as
    platform-ops in the ArgoCD bootstrap. Decision folded into
    `docs/bugs/2026-08-28-vault-unseal-watchdog-stale-image.md`.
  - **Real smoke-user seed NOT applicable on the hub — architecture finding.** `keycloak_seed_smoke_user`
    targets a `shopping-cart` realm, but the hub Keycloak (identity ns, reached at
    `keycloak.shopping-cart.local`) has only `home` + `master` realms — no `shopping-cart` realm and no
    frontend/app client (`home` has only default clients). The shopping-cart frontend + its realm live on
    the **app-cluster (ACG)**, not the hub. So seeding a hub user cannot produce a true Frontend-login PASS
    without first provisioning the shopping-cart realm + frontend client on the hub Keycloak (a real setup
    task, not a last-mile seed). The honest SKIP from the `kc_token_is_stub` fix is the correct state. Seed
    aborted at the realm-existence check — created nothing (verified: no `k3dm-smoke-user` secret, no
    `k3dm-smoke` client). Also noted: codebase default realm `shopping-cart` is stale vs live hub `home`.

- **2026-08-29 monitoring-pause Grafana keep-list — LIVE-VERIFIED (8506f5fe, pushed):** pure
  whole-word `_observability_workload_in_keep_list` + default
  `OBSERVABILITY_PAUSE_KEEP=kube-prometheus-stack-grafana` pause-sweep exemption; resume unchanged.
  Five pure BATS cases + Makefile help. Spec `docs/bugs/2026-08-29-pause-keep-grafana-up.md`. Coded by
  Codex, Claude-verified (BATS 5/5, `bash -n` clean, SC2016 pre-existing only). Live hub:
  `make monitoring-pause` keeps grafana 1/1 (loginable, `database:ok`) while everything else → 0/0;
  resume → HEALTHY. By design panels show "No data" while paused (UI reachable, not live data). To
  restore the old all-or-nothing sweep set `OBSERVABILITY_PAUSE_KEEP=""`.

- **2026-08-29 layered `monitoring-resume` — LIVE-VERIFIED (1bdbe3c6, pushed):** `make
  monitoring-resume LAYER=1` brings up **Grafana + Prometheus only** (live dashboards), all else 0;
  `LAYER=2` or no arg = full stack (existing body, verbatim). Added `_observability_normalize_layer`
  (1→1, 2/empty/unknown→2 — forgiving) + `_observability_resume_layer1` (keeps ArgoCD `automated:null`
  so selfHeal can't resurrect the 0-set; explicit replica drive; idempotent from pause/L1/L2), reusing
  the keep-list predicate with `OBSERVABILITY_LAYER1_UP=kube-prometheus-stack-grafana
  prometheus-kube-prometheus-stack-prometheus`. Makefile `$(LAYER)` passthrough + help. 5 pure BATS
  normalize cases. Spec `docs/bugs/2026-08-29-layered-monitoring-resume.md`. Coded by Codex,
  Claude-verified (BATS 10/10, `bash -n` clean, SC2016 pre-existing only, diff==spec, scope==3 files).
  **Live hub:** L2→`LAYER=1` dropped to grafana 1/1 + prometheus 1/1 (rest 0/0), Prometheus `up` query
  returned series + Grafana `database:ok`; `LAYER=2` restored all 7 workloads 1/1, `make status`
  HEALTHY. One manual touch during the L2 ramp: deleted a stale `Unknown` prometheus pod from the known
  CPU-starvation cascade (full stack starting at once) — not a feature defect.

- **2026-08-29 Tier-1 E2E orders.spec ROOT-CAUSED + FIXED (aa2f2190, pushed) — gate rerun
  confirming:** the orders.spec wholesale failure (42 ✘) was NOT a client-contract bug. Ground
  truth (captured Playwright `results.json` from the live pod before teardown + direct
  port-forward replay): the deployed order image `sha-56033880` is the **Go** rewrite (commit
  `5603388`), not Java (earlier Dockerfile read was wrong), and it ships **no runtime migration** —
  the substrate created the `orders` DATABASE but never the `orders`/`order_items` TABLES →
  every order DB op HTTP 500 (`relation "orders" does not exist`, 42P01). Fix: added
  `20-orders-schema.sql` to `scripts/etc/e2e/postgres.yaml` initdb (`\connect orders` + DDL).
  Critical nuance: DDL must match the **deployed** commit `5603388` — its `order_items` has **no
  `total_price`** column; copying repo-HEAD/testdata DDL (which added `total_price NOT NULL`) 500s on
  insert (23502) since that binary never writes it. **Live-validated** against the running substrate:
  `POST /api/orders → 201` with full contract (id, status PENDING, items[].subtotal, totalAmount,
  shippingAddress, currency USD), `GET …?customerId=X` (X-User-ID header) → 200 with the order. List
  filters by `X-User-ID` (MockAuthMiddleware), not the query param — e2e client sends it consistently,
  no change needed. Payments.spec (27) + payment cross-service stay Tier-1-out-of-scope (no payment
  manifest = Tier-2/ACG's job). Spec `docs/bugs/2026-08-29-e2e-order-schema-missing.md`; durable
  service-side self-migrate follow-up `docs/issues/2026-08-29-order-service-no-startup-migration.md`.
  Confirming rerun DONE (`~/.k3dm/e2e/1788051374-25838.json`, commit 86298144): **passed 26→45,
  failed 31→12, skipped 45**. Cross-service fully greened (21→0), orders 42→2. **Residual 12 =
  ZERO substrate bugs**: (a) 9 payments `ECONNREFUSED :8084` — no payment svc in Tier-1
  (Tier-2/ACG's job); (b) 2 order status-update — e2e test sends status `CONFIRMED` which is NOT
  in the deployed `OrderStatus` enum (PENDING/PAID/PROCESSING/SHIPPED/COMPLETED/CANCELLED) + illegal
  transitions (PENDING→only PAID/CANCELLED) → PATCH 400 → status undefined = **e2e-test contract bug**
  (shopping-cart-e2e-tests, spec-not-direct); (c) 1 cart remove-qty-0 — `cart.items` undefined,
  pre-existing basket/e2e mismatch. Substrate fix is COMPLETE for its scope. To green the gate:
  cross-repo — fix the 3 test-contract bugs in the e2e repo (+ rebuild image) and decide payment
  (Tier-1 manifest vs scope-to-non-payment + Tier-2). User chose (2026-08-29): **fix e2e tests,
  payment→Tier-2.**

- **2026-08-29 e2e residual triage — CART RECLASSIFIED as a basket-service bug (specs written,
  Codex handoff pending):** on grounding the 3 residuals, only 2 are e2e-test bugs; the cart one is
  a service bug:
  - **Order status (2, e2e-test bug):** tests send status `CONFIRMED`, absent from the deployed
    `OrderStatus` enum (PENDING/PAID/PROCESSING/SHIPPED/COMPLETED/CANCELLED) + illegal transitions
    (PENDING→only PAID/CANCELLED). Fix = use real enum + legal chain (PENDING→PAID; history
    PENDING→PAID→PROCESSING→SHIPPED). Spec `docs/bugs/2026-08-29-e2e-order-status-enum-mismatch.md`
    (repo `shopping-cart-e2e-tests`).
  - **Cart qty-0 (1, BASKET-service bug, NOT a test bug):** basket `UpdateItemRequest.Quantity`
    is `binding:"required,min=0"`; gin treats int 0 as "missing" so `{quantity:0}` → 400 before the
    handler's `quantity<=0` remove path runs. Test is CORRECT. Fix = drop `required` (use `min=0`).
    Issue `docs/issues/2026-08-29-basket-update-quantity-zero-required.md` (repo `shopping-cart-basket`).
  Both are shopping-cart repos → spec+Codex, branch+PR, rebuild image (spec-not-direct). Codex handoff
  + image rebuild + Tier-1 re-verify still to do; PR/merge gated.

## Canonical pointers

### 2026-09-01 → 2026-09-04 — v1.28.0 block (ARCHIVED)

> Compressed 2026-09-21. Full detail: `memory-bank/archive/activeContext-2026-09-21.md`.
> All settled — v1.28.0 shipped and merged; the tree is on v1.36.0.

Covered there: the live frontend Keycloak client hotfix; ArgoCD identity sync recovery; empty
Grafana CVE panels; the `keycloak-secrets` ExternalSecret root cause (**Vault field schism**, not
missing data); the v1.28.0 two-cloud bring-up, where a fresh-hub `make up` aborted on an unguarded
PrometheusRule apply — guard shipped and verified, then the LDAP verify-newline fix; two-cloud
validation complete across AWS and hostinger; two v1.28.0 follow-ups closed; pruning unconditional
Jenkins fixtures from the LDAP bootstrap seed, and the decision to leave `bootstrap-ad-schema.ldif`
fixtures as-is; lib-foundation PR #45 (acg robust-click) through to v0.4.14 merged and
subtree-synced; and v1.28.0 PR #119 created and merged with CI green.

### Hub GHCR outage — still OPEN, blocked on a credential

All four `shopping-cart-apps` deployments on the hub remain `ImagePullBackOff` (11h+).
Kubelet reports `403 Forbidden` from `ghcr.io` — authenticated, not authorized.

Every GitHub credential on the operator's machine was tested and none can pull:
- `gh` CLI token — scopes `admin:public_key, gist, read:org, repo`. No `read:packages`.
- Keychain `github-packages-token` — refused by `bin/restore-hub-ghcr-pat`'s pull probe.
- `k3dm-hermes-gh-token`, `k3dm-hermes-audit-token` — no `X-OAuth-Scopes` header.

The scope-header check is INCONCLUSIVE for fine-grained PATs (GitHub omits the header),
so "no scopes header" does not distinguish expired from fine-grained. The authoritative
test is the GHCR token exchange + `tags/list` pull, i.e. `_shopping_cart_ghcr_pat_can_pull`.
That probe was validated against the real package: `wilddog64/shopping-cart-basket` is
exactly what `basket-service` pulls, so the refusal is real and not a bad probe.

`github-packages-token` failing also implies the GitHub Actions image-build pipeline
will 401 — a second, independent breakage worth tracking.

Next: operator runs the per-token GHCR pull probe to confirm, then either pipes a
working token into `bin/restore-hub-ghcr-pat` or mints a classic PAT with `read:packages`.

## 2026-09-21 — rotate-ghcr-pat VERIFIED + image-promotion bug filed and dispatched

`bin/rotate-ghcr-pat` fix verified and committed at `edaa2e49` (Codex implemented; Claude
committed because Codex again could not write `.git/index.lock`). All five BATS gates
mutation-tested `not ok` against the pre-fix source, file restored shasum-identical.
`shellcheck` clean (only expected SC1091 info on sourced libs), `bats` 5/5.

### CORRECTION — my earlier "PACKAGES_TOKEN is heading for 401s" claim was WRONG

`PACKAGES_TOKEN` in GitHub Actions **works**. The registry push half of the pipeline is
healthy: run `35117065512` built, pushed and cosign-attested
`sha256:e9bcb925619b5344a958fc359091b651c61365ce7b8a65c354408ee2f7198b92` — the exact digest
`product-catalog` on the hub is failing to pull. So the image exists in GHCR and CI can write it.

The real CI breakage is `PROMOTER_SSH_KEY` arriving **empty**, so the git promotion step dies at
`Load key ".../promoter_key": error in libcrypto`. Filed as
`docs/bugs/2026-09-21-image-promotion-fails-promoter-ssh-key-not-passed-to-reusable-workflow.md`
(`eb97355d`) and dispatched to Codex (session `01a0c401`, log
`scratchpad/codex-promoter-run.log`), branch `fix/pass-promoter-ssh-key` in 4 repos.

Cause: `build-push-deploy.yml` declares `PROMOTER_SSH_KEY: required: false`, and three of five
callers omit it from their `secrets:` block — payment, product-catalog, frontend. Basket and
order are correct. Payment is a pure code fix (secret exists); product-catalog and frontend also
need the **operator** to create the repo secret.

**Why this hid for weeks:** `publish` is gated on `github.ref == 'refs/heads/main' && event ==
'push'`, so every PR and Dependabot run **skips** it, and a skipped job does not fail a run. The
2026-09-21 product-catalog run reads `success` with `Build, Scan & Push = skipped`. Another
instance of green ≠ working — check the job list, not the run conclusion.

The hub `403 Forbidden` is a **separate, cluster-side** credential problem (the PAT in Vault /
`ghcr-pull-secret`), not a CI problem. Still blocked on a PAT with `read:packages`.

## 2026-09-21 — promoter-key spec CORRECTED after Codex caught my mismatch

Codex stopped without editing and reported that three of the four repos in my spec did not
match the files on disk. It was right. The error was mine: my detection script globbed
`*.yml` only and took the first match per repo.

Corrected, verified scope — **`shopping-cart-product-catalog` is the only broken repo**:

| Repo | Caller | Calls reusable? | Forwards key? | Repo secret? | Last main pushes |
|---|---|---|---|---|---|
| basket | `go-ci.yml` | yes | yes | yes | 1 failure, DIFFERENT cause |
| order | `ci.yml` | yes | yes | yes | success |
| payment | **`ci.yaml`** | yes | yes | yes | success |
| **product-catalog** | `ci.yml` | yes | **no** | **no** | **failure 3/3 since 2026-08-26** |
| frontend | `ci.yml` | **no** (inline publish) | n/a | n/a | success |

- payment's caller is `ci.yaml` — **`.yaml`, not `.yml`** — and already forwards the key.
- frontend never uses the reusable workflow; it promotes via a deploy PR with `PACKAGES_TOKEN`.
- basket run `33507015429` failed promotion too, but its key was present (`***`) and the error was
  `failed to push some refs` — a push rejection. Separate, unfiled, single occurrence. Do NOT fold in.

Spec rewritten to product-catalog + infra only (`6fa1ceab`) and re-dispatched (session `01a0c406`,
log `scratchpad/codex-promoter-run2.log`). Stray branches Codex created in payment and frontend are
left in place — branch deletion is not approved.

Codex created branches in 4 repos on the first attempt; only product-catalog and infra will receive
commits.

## 2026-09-21 — promoter-key fix VERIFIED (2 SHAs on origin) + a pinning gap found

Codex's second run is verified independently:

| Repo | SHA | on origin | files | scope |
|---|---|---|---|---|
| shopping-cart-product-catalog | `2c8dd68f` | yes | `.github/workflows/ci.yml` | +1 line |
| shopping-cart-infra | `94b16bc9` | yes | `.github/workflows/build-push-deploy.yml` | +10 lines |

Both on `fix/pass-promoter-ssh-key`, no PRs, commit message and trailers exact.
YAML parsed with `yaml.safe_load`: guard is step index **12**, promote step index **13** — guard
first, guard is self-contained (`env`/`name`/`run`, `exit 1`), and the promote step still has its
`git push` and key-file write. `required: false` left unchanged as specified.
product-catalog's `publish` job now forwards all four secrets.

Codex self-caught a real bug mid-run: its first patch put the guard **inside** the promotion step's
`run:` block after `git commit`, which would have swallowed the consumer commands. It corrected to a
separate step before reporting.

### GAP — the guard will NOT fire for product-catalog yet

`product-catalog/ci.yml` pins the reusable workflow:

```
uses: wilddog64/shopping-cart-infra/.github/workflows/build-push-deploy.yml@1b35d962d...
```

Verified `1b35d962d` does **not** contain the guard (`grep -c` = 0). So until that pin is bumped to
a commit containing `94b16bc9`, product-catalog keeps calling the old workflow and an empty key still
fails as `error in libcrypto`, not the actionable message.

Change 1 (forwarding the secret) is unaffected — it lives in product-catalog's own file.

Sequence for the guard to take effect: merge infra → bump the pin in product-catalog. Dependabot
already tracks this pin (its PR titles read
`github_actions in /. - Update ...build-push-deploy.yml-<sha>`), so it will bump on its own after
the infra merge, or it can be re-pinned by hand.

### 2026-09-21 — promoter-key gap is TWO missing things, not one (spec corrected again)

Checked the deploy keys rather than trusting the earlier claim that basket/order/payment share one
promoter key. They do **not** — three distinct `sc-image-promoter` fingerprints, one pair per repo.
The promote step pushes to `git@github.com:${{ github.repository }}` — the **calling repo itself**,
not the infra repo — so each app repo needs its own write deploy key plus its own private-half secret.

`shopping-cart-product-catalog` is missing **both**: no `sc-image-promoter` deploy key and no
`PROMOTER_SSH_KEY` secret. Adding only the secret would still fail, at `git push`, with a permission
error rather than `error in libcrypto`.

~~"add the secret reusing the key already in basket/order/payment"~~ — **RETRACTED, was wrong.**
The fix is a fresh ed25519 pair for product-catalog only. Key material, so not a Codex task.

Pin bump deliberately NOT dispatched: product-catalog pins `build-push-deploy.yml@1b35d962b`, and
bumping it to the unmerged `94b16bc9` would point a consumer's main at a commit outside infra's
default branch, with a second bump forced after the squash merge. Correct order is infra PR merge
first, then bump to the merge SHA. Dependabot already tracks `github-actions` weekly in that repo.

Blocked on the user, not on Codex: (1) PR creation in both repos, (2) the keygen + deploy key +
secret for product-catalog.

### 2026-09-21 — deep dive: product-catalog was never onboarded to the SSH promoter

The user pushed back that this setup has been done many times and should not need redoing. Correct
instinct, wrong conclusion about the cause: product-catalog was never onboarded, and a later pass did
one third of the job, which is why it looks onboarded.

infra PR #91 (2026-08-09T14:26Z) switched promotion from token push to SSH deploy key. Its rollout
section says "Per repo: add write deploy key + PROMOTER_SSH_KEY secret; ruleset with DeployKey bypass;
delete classic protection; repin" and **never enumerates the repos**. It covered order (14:27Z),
payment (15:02Z) and basket (15:05Z) — deploy key and ruleset created within the same minute each —
and skipped product-catalog.

Breakage trigger, 2026-08-12: 01:53Z main push succeeded while still pinned to 4afa9dce (0 refs to
PROMOTER_SSH_KEY); 01:54Z auto-merge enabled on Dependabot PR #47; 01:56:59Z squash-merged, moving the
pin to 47769da (3 refs); 01:57Z main push FAILED. Four minutes. The Dependabot PR was green by
construction — `publish` is main-push-gated, so it was skipped on the PR that broke it.

2026-09-01 13:03Z: eight minutes after that day's failure, a main-protection ruleset with a
DeployKey:always bypass was created on product-catalog. Step 3 of the rollout applied in isolation — a
bypass for a key that does not exist. Misdiagnosis; 09-16 failed identically.

Corrected in the spec: broken since **2026-08-12, six consecutive main pushes**, not 2026-08-26. The
wrong date came from `gh run list --limit 3`.

Still missing, steps 1 and 2 only: the write `sc-image-promoter` deploy key and the PROMOTER_SSH_KEY
secret. Nothing to copy — the three sibling fingerprints are distinct because the promote step pushes
to the calling repo, not to infra.

BLOCKED: generating the pair and writing the secret was denied by the auto-mode classifier
(Secret-Store Writes). Not worked around. One command handed to the user to run via `!`.

**RESOLVED 2026-09-21 23:38Z** — the user ran that command. Verified from the GitHub side, not from
the reported output: `gh repo deploy-key list` shows `164022592  sc-image-promoter  read-write`
created `2026-09-21T23:38:44Z`, and `gh secret list` shows `PROMOTER_SSH_KEY  2026-09-21T23:38:46Z`.
The new fingerprint differs from `argocd-product-catalog-m2-air`, so the two keys are not conflated.
Both `/tmp/pc_promoter` and `/tmp/pc_promoter.pub` are gone. Claude never read the private key.

Onboarding steps 1 and 2 are closed. What remains for product-catalog promotion to actually succeed
is the **infra merge plus the pin bump** — `ci.yml` still pins `build-push-deploy.yml@1b35d962d`,
which predates the guard, so the forwarded secret is inert until that pin moves.

### 2026-09-21 — hub GHCR 403: the credential path, corrected

User asked whether the keychain was locked. Checked: it is **not** — `show-keychain-info` reports
`no-timeout` and all four items (`github-packages-token`, `k3dm-hermes-gh-token`,
`k3dm-hermes-audit-token`, `copilot-cli`) exist. That hypothesis is closed, but chasing it surfaced
two corrections.

**1. The pull probe is sound — I should not have let it be doubted.** Verified directly:
`curl --netrc-file` does send `Authorization: Basic` preemptively to `ghcr.io/token`; a bogus
credential returns 403 with no `.token`, so `_shopping_cart_ghcr_pat_can_pull` fails closed and is
correct. Its verdict on all four keychain tokens stands.

**2. "PACKAGES_TOKEN is working" was misleading.** The registry login in
`build-push-deploy.yml` is `password: ${{ secrets.GITHUB_TOKEN }}` — the ephemeral per-run Actions
token with automatic `packages: write`. So the green push proves nothing about any long-lived
credential. `PACKAGES_TOKEN` is only a build arg (`GH_TOKEN=` for dependency fetches) and the
frontend's deploy-PR token. **There is no working long-lived GHCR pull credential anywhere** — not in
CI, not in the keychain.

The packages are private: anonymous token exchange returns
`401 UNAUTHORIZED authentication required`. A credential with `read:packages` is mandatory; one
without it yields 403, which is exactly the hub's `ImagePullBackOff`.

**Fix without minting anything:** the existing `gh` OAuth token (`gho_`, in the keyring) has scopes
`admin:public_key, gist, read:org, repo` — no `read:packages`. `gh auth refresh -h github.com -s
read:packages` adds it to the token we already have. Interactive, so the user runs it via `!`.
Cheap scope check afterwards: `gh api "user/packages?package_type=container"` currently returns
`403 You need at least read:packages scope to list packages`.

### 2026-09-21 — basket promotion failure root-caused: the rebase fallback cannot ever work

Filed `docs/bugs/2026-09-21-image-promotion-rebase-fallback-cannot-resolve-concurrent-newtag-conflict.md`.

basket run `33507015429` (2026-09-01T12:19Z) was NOT a transient race. Two main pushes three minutes
apart (12:16Z Dependabot pin bump, 12:19Z manual re-pin) each promoted; the second was rejected
`fetch first`, and the fallback `git pull --rebase` hit
`CONFLICT (content): Merge conflict in k8s/base/kustomization.yaml` because both commits rewrite the
**same `newTag:` line**. Rebasing one such edit onto another is a guaranteed conflict — the retry is
structurally incapable of recovering from the only scenario it exists for. The rebase halted, leaving a
conflicted worktree, and the retry push ran against that.

Fix specified: replace commit-then-rebase with a bounded fetch / `reset --hard origin/<ref>` / reapply
`sed` / push loop, with the "already promoted" no-op check moved inside the loop so a concurrent run's
identical result counts as success.

**Sequencing:** must NOT start until `fix/pass-promoter-ssh-key` merges in shopping-cart-infra —
`94b16bc9` touches the same file. Branch `fix/promote-refetch-instead-of-rebase` off the updated main
afterwards. Not dispatched to Codex yet for that reason.

Confirms the earlier decision to keep this separate from the PROMOTER_SSH_KEY bug was right: same
failing step, different cause, key present.

## 2026-09-21 — doc realignment: webhook architecture, /k3dm pattern, new Grafana guide

Three commits, all on `k3d-manager-v1.36.0`, all pushed.

**`3e5951ca` — architecture docs vs. the live webhook server.** Both
`docs/architecture/webhook-server.md` and `-/cloudflare-slack-relay.md` still described
v1.13.0. Measured corrections: `bin/k3dm-webhook` is **4,008** lines (doc said ~2,950);
`scripts/lib/webhook/` has **5** modules (`make_targets.py` was absent from the table, as
was `auth.py`'s Slack identity gate `_slack_user_is_allowlisted` / `_slack_user_role`);
every line range in the "still in the monolith" table was stale. Five routes were
undocumented: `/api/v1/make`, `-cve-remediate`, `-hostinger-status`,
`-cleanup-stale-sandbox`, `-analyze`. The relay route table now carries a **min-role
column** sourced from `_ACTION_POLICY`.

Also documented the interface shift the user flagged: **the Makefile is now the operator
surface**. `/k3dm` replaced "one route per operation" — a new capability is a Makefile
target plus one row in `MAKE_TARGETS`. Four gates written down: target allowlist, per-target
arg allowlist + `_ARG_PATTERNS` regex, role **capped twice** (relay stamps `admin`, then
`_effective_make_role` caps at the caller's `K3DM_SLACK_ROLE_MAP` role, then the target's
`min_role`), and `confirm` for the three destructive targets. Execution detail recorded:
args are positional `$@`, never interpolated, and `__K3DM_MAKE_RC=` is how the real rc
survives a merged-stream capture.

**`dfef599e` — `docs/guides/grafana-dashboards.md` (new) + webhook phase status.**

Grafana had **no guide at all** — a guide-per-major-tech violation. Seven dashboards ship
from two directories to two different clusters; their knowledge existed only scattered
across ~25 plan/bug/issue docs, and `grafana-dashboard-hermes.yaml` was referenced by none
of them. The guide gives per-dashboard panels + queries, the producer chain, and a
`No data`-by-cause triage table where every row is a real past incident.

Findings surfaced while tracing producers:
- **`k3dm.k3.io/hermes-status` is NOT a typo to fix.** The Hermes selector uses `k3.io`
  where the e2e and CVE selectors use `k3dm.k3d.io`. `bin/k3dm-hermes:378` and
  `vulnerability-inventory-exporter.yaml:281` agree, so it works; normalising one side
  alone silently empties the dashboard and the exporter reports no error. Marked do-not-fix
  in both guides.
- **`checkout-loadtest-configmap.yaml` has no applier** — no plugin, Makefile target or
  ApplicationSet references it. Its `No data` is the steady state, not a regression.
- `docs/guides/hermes.md` described **four** Hermes panels; the dashboard has **six**
  (*Degraded sensors*, *Unknown sensors* were missing). Fixed, with the panel/query table.

**Webhook modularization phase status — the user asked where we are.** Answer: Phase 1
only, and that is accurate, but the doc omitted the real story. None of `server.py`,
`routes.py`, `commands.py`, `dispatch.py`, `jobs.py`, `diagnostics.py` exist — **phases 2–5
not started**. Phase 1 moved ~190 lines out (3,142 → 2,953 at `28f38058`); today the file
is **4,008**, **+36%** since. The plan is being outrun by the code it was meant to shrink;
`webhook-server.md` now carries that measurement table and a per-phase status table with
evidence. Noted that both real extractions (`config/render/proc/auth`, then `make_targets`)
were **pure leaves**, not the behavioural splits phases 2–4 describe.

Prior commit this window: `b5721781` (ASCII→Mermaid; found and fixed
`acg-credentials-flow.md` block#1, which had never rendered — a semicolon in
sequence-diagram message text terminates the statement).

## 2026-09-21 — doc-link gate BUILT (5-month-old proposal), 13 broken links fixed

`58f5c316` on `k3d-manager-v1.36.0`, pushed. Preceded by `f3b9be22` (e2e harness guide tiers).

**Why now.** The harness-guide audit found three README entries for one doc, all linking to
the bare file, so "Tier 2" landed on a page titled "(Tier 1)". Nothing could have caught it.
`memory/feedback_issue_doc_links_precommit.md` had recorded this gap on **2026-04-06** and
re-confirmed on 2026-09-17 that the checker had **never been built**.

**Built:** `scripts/check-doc-links.py` (stdlib; the memory proposed a `.sh` — Python is more
honest for markdown parsing) + `make check-doc-links`, wired into `.githooks/pre-commit` over
**staged files only** so pre-existing debt cannot block unrelated commits. `K3DM_SKIP_DOC_LINKS=1`
bypasses. Dropped the proposal's `.pre-commit-config.yaml` step — this repo uses
`core.hooksPath=.githooks`, so that part was simply wrong. Tests:
`scripts/tests/bin/test_check_doc_links.py`, **23 cases**, added to `make test-pytest`.

**Three false-positive classes had to be handled** — each would have made the gate useless:
1. **Inline code.** A DNS regex `` `[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?` `` is syntactically
   `[text](target)`. Code spans blanked before matching.
2. **`path:line`.** This repo writes clickable `bin/k3dm-webhook:95`; suffix stripped.
3. **Slug rules.** `github-slugger` does `.replace(/ /g, '-')` — **each** space its own hyphen,
   so `/claude / /gemini / /codex Commands` → `claude--gemini--codex-commands`. **My first
   implementation collapsed whitespace runs and reported three CORRECT links as broken.** Caught
   by inspecting the target headings before "fixing" anything — the near-miss worth remembering.

**Fixed 13 of 13.** Standing docs retargeted: `../howto/vault-pki-setup.md` →
`../guides/security/04-vault-pki.md` (×2), dead `README.md#jenkins-authentication-modes` →
`../guides/jenkins-authentication.md`, `../bin/get-ldap-password` → `../../bin/…`,
`#create-slack-app` → `#1-create-slack-app`. In 4 historical `docs/issues/2026-05-*` and 1
archived plan the dead links were **unlinked to inline code**, not repointed — repointing a
record to somewhere it never pointed falsifies it. Same call as leaving historical ASCII
diagrams alone. That also unlinked 3 neighbouring absolute `/Users/cliang/...` links that
resolved on this machine only.

Verified: `1725 file(s) OK`; 23 pytest pass; failure path exits 1 with `file:line`;
`shellcheck .githooks/pre-commit` clean; and the hook fired on its own commit
(`check-doc-links: 11 file(s) OK`).

### Discovered, NOT fixed — needs the user's go
**`bin/acg-up` / `bin/acg-down` were renamed `bin/cluster-up` / `bin/cluster-down` in v1.7.1
(`0c9b2707`), and 219 files still say the old name.** No code references the old names, so
nothing breaks at runtime — but standing docs (README's ACG table,
`docs/architecture/cloudflare-slack-relay.md` "Step 10h"/"Step 14c", guides) instruct readers
to run a script that does not exist. The link checker cannot see these: they are code spans,
not links. Historical bugs/issues/retros should **keep** the old name. Scope for the sweep =
standing docs only. Recorded in
`docs/bugs/2026-09-21-doc-links-and-anchors-never-validated.md`.

## 2026-09-21 — acg-* → cluster-* rename applied to standing docs

`cee21ef0`, pushed. Follows `58f5c316` (the doc-link gate that surfaced it).

`bin/acg-up`/`-down`/`-refresh`/`-status`/`-sync-apps` → `bin/cluster-*`, and Slack `/acg-*`
→ `/cluster-*`, happened in **v1.7.1** (`0c9b2707`; spec
`docs/plans/v1.7.1-rename-acg-to-cluster-binaries.md`). Code was already clean — grep of
`bin/k3dm-webhook`, `workers/slack-relay/index.js` and `Makefile` found **zero** old names —
so nothing was broken at runtime, but standing docs told readers to run scripts that do not
exist.

**48 occurrences fixed** in README (live sections only), `docs/architecture/cloudflare-slack-relay.md`,
`docs/howto/makefile.md`, `docs/howto/launchd-daemons.md`, `docs/guides/grafana-dashboards.md`,
`memory-bank/projectbrief.md`, `memory-bank/systemPatterns.md`.

**Deliberately left, each verified not assumed:**
- **Release tables** (README `## Releases` from line ~310, `docs/releases.md`) + `docs/bugs/`,
  `docs/issues/`, `docs/retro/`, `memory-bank/archive/`. `/acg-resume` really was the command
  in v1.6.3 — renaming a release note falsifies what shipped. Boundary used: the `## Releases`
  heading.
- **Grafana panel titles** "Last acg-up Duration" / "Last acg-down Duration" — these are
  *literal strings* in `k3dm-deployments-configmap.yaml`, so the guide quotes the dashboard as
  deployed. Added a caveat naming the cost of changing them (edit ConfigMap + reapply
  `make observability-acg`). **A doc that disagrees with a deployed UI string is worse than a
  stale name.**
- `acg-credential-test` / `acg-extend-test` — CURRENT names, and they live in
  `scripts/lib/foundation/.../acg/bin/` (subtree, never edit). Also preserved `acg-watch`,
  `acg-prometheus`, `acg-values`, `acg-plugin`, and the `acg-sandbox-stripe-verification`
  anchor.
- `acg-sync-apps-argocd-pf` state-file/log constant inside `bin/cluster-sync-apps` — kept on
  purpose by the v1.7.1 spec. My `\bacg-sync-apps\b` regex *would* have matched it (hyphen is
  a word boundary); confirmed it appears in no edited file.

**Also fixed:** `cloudflare-slack-relay.md` quoted a 409 Slack message the webhook never
emits (`use /acg-status to check progress`). Real text from `bin/k3dm-webhook:3755` is
`cluster job already running: <job_id> (<action>)`. A stale *quote* is a separate defect from
a stale *name* — the rename would have silently "modernised" a fabricated string.

Caught before commit: inserting the panel-title caveat mid-table split a markdown table,
orphaning three rows. Moved below the table.

Verified: `check-doc-links` 1726 OK; mermaid 6 blocks 0 failed; 23 pytest pass.

## 2026-09-21 — Tier 1 e2e RAN (first ever e2e data on Grafana); Tier 2 blocked

**User asked for one Tier 1 + one Tier 2 run so Grafana has data.** Tier 1 ran; Tier 2 could
not start.

### Tier 1 — ran, failed at `deploying-substrate`, but DID publish
`./scripts/k3d-manager e2e_verify_vcluster`, run `1790025545-10464`, host context
`k3d-k3d-cluster`. vCluster `e2e-1790025545-10464` created in ns `vclusters`, API ready, then:

```
[acg-up] GHCR_PAT not in env — checking Vault...
[acg-up] gh CLI token cannot pull from ghcr.io — ... excludes read:packages, NOT saved to Vault
ERROR: [acg-up] GHCR_PAT not set and no valid PAT in Vault
```

`result: fail`, `exit_code: 1`, `phase: deploying-substrate`. The `EXIT` trap tore the vCluster
down cleanly (deregistered from hub ArgoCD, namespace deleted) — no leak.

**The observability chain is PROVEN END TO END**, which is the lasting win here:
run → `platform-ops` ConfigMap `e2e-result-cxdm5`
(`e2e-result=true,e2e-runner=local-m4,e2e-service=product-catalog,e2e-tier=vcluster`) →
`vulnerability-inventory-exporter` → metrics. Read off the exporter's `:8080/metrics`:
`e2e_last_run_pass{tier="vcluster",service="product-catalog",runner="local-m4"} 0`,
plus `e2e_run_info`, `e2e_last_run_timestamp_seconds`, `e2e_last_run_duration_seconds`.
**Before this run the hub had ZERO `e2e-result` ConfigMaps** — the E2E Verification dashboard
now has its first series. Note this is a *local* run, so it does not clear the OPEN remote bug
`docs/bugs/2026-09-15-e2e-remote-results-never-reach-grafana.md` (that is about
`E2E_M2_PUBLISH_BACK_HOST` being invisible to launchd).

### MY ERROR, corrected — I pre-cleared Tier 1 on a false probe
Before running I probed GHCR with the gh token against
`ghcr.io/wilddog64/shopping-cart-e2e-tests`, got HTTP 200 on the manifest, and told the user
"repo scope is sufficient for your own packages, so Tier 1 can pull." **Wrong.** That package
is **PUBLIC** — anonymous, credential-free token exchange also returns 200. Measured:

| Package | anonymous | gh token |
|---|---|---|
| `shopping-cart-e2e-tests` | **200** | 200 |
| `shopping-cart-basket` | 403 | **403** |
| `shopping-cart-product-catalog` | 403 | **403** |

The substrate needs the **private service images**, not the public test runner.
`_shopping_cart_ghcr_pat_can_pull` is correct and its default
`GHCR_PROBE_REPO=wilddog64/shopping-cart-basket` (private) is deliberate — trust it over an
ad-hoc probe. Saved as `memory/reference_shopping_cart_e2e_tests_package_is_public.md`.
Same trap family as the `GITHUB_TOKEN` green-push false positive.

### Tier 2 — hard blocked, never started
`e2e_verify_sandbox` hardcodes `kubectl --context ubuntu-k3s` (`scripts/plugins/e2e.sh:119`)
and calls `acg_extend_playwright`. Only two contexts exist: `k3d-k3d-cluster` and
`ubuntu-hostinger` — **there is no ACG sandbox up**. Standing rule: ACG login is a one-time
MANUAL Pluralsight step needing a real TTY; Claude-run `credential-test` bails
`ACG_SESSION_EXPIRED`. Not attempted.

### What unblocks each (both user-side)
- **Tier 1:** a GHCR PAT with `read:packages` → `pbpaste | bin/rotate-ghcr-pat`. **Open
  question:** `bin/cluster-up` asserts gh's OAuth scopes "are fixed and exclude
  read:packages", which would make the long-parked `gh auth refresh -h github.com -s
  read:packages` futile. Unverified — check before spending time on it.
- **Tier 2:** bring up the ACG sandbox (manual Pluralsight login, user, real TTY), then rerun.

Also confirmed same root cause: hub `shopping-cart-apps` pods (basket/frontend/order/
product-catalog) have been `ImagePullBackOff` for ~20h.

### 2026-09-21 — post-merge on product-catalog: the merged PR was Dependabot, not our fix

User reported "only product-catalog has a PR open, and I merged it" and asked for `/post-merge`.
Checked before running anything. The PR that merged at 23:41:44Z was **#54, a Dependabot pin
bump** (`1f45062c`), moving `ci.yml`'s `build-push-deploy.yml` pin from `1b35d962b` to
`af4b053dc`. It was not `fix/pass-promoter-ssh-key` — that branch never had a PR, because we were
waiting on the user's go, and no PR was ever opened in infra either.

Why this matters rather than being a harmless mix-up:

| Thing | State on product-catalog `main` after #54 |
|---|---|
| `PROMOTER_SSH_KEY` secret | exists (minted 23:38Z) |
| `sc-image-promoter` deploy key | exists, read-write |
| `ci.yml` forwards `PROMOTER_SSH_KEY` to the reusable workflow | **NO** — only PACKAGES_TOKEN, COSIGN_KEY, COSIGN_PASSWORD |
| pinned infra SHA contains the empty-key guard | **NO** — `af4b053dc` = infra main @ PR #98 (09-16), predates `94b16bc9` |
| pinned infra SHA contains the rebase-fallback fix | **NO** — `git pull --rebase` fallback still present |

The reusable workflow declares `PROMOTER_SSH_KEY: required: false`, so the missing forward is
silent: the promote step writes an empty file and dies at
`Load key "~/.ssh/promoter_key": error in libcrypto`. Minting the keypair removed the *second*
blocker; the *first* one — the caller not passing the secret — is untouched.

This is the [[reference_unenumerated_api_rollout_misses_repos]] pattern firing a second time on the
same repo: a Dependabot pin bump moving a pin across a range that does not contain the fix, merging
green because the promote step is `continue-on-error: true` with a separate fail-gate.

Post-merge steps actually applicable to a Dependabot bump: main synced locally to `1f45062c`
(fast-forward, 3 commits). No tag or release — CHANGELOG has only `[Unreleased]` and this was not a
milestone branch, so the skip is legitimate, not a missed release. `main` is **not** branch-protected
on this repo (`/protection` returns 404 "Branch not protected"), so there is no `enforce_admins` or
review count to restore. Dependabot's branch was auto-deleted. No retro (not a milestone). No next
feature branch created — `fix/pass-promoter-ssh-key` is still the live one.

Left alone, pending the user's word: rebasing `fix/pass-promoter-ssh-key` onto the new main, and
opening its PR.

### 2026-09-21 — promoter-fix PRs opened; the failure mode proved live on main first

User gave the go. Before opening anything, the #54 merge's own main run
(`35668727231`, head `1f45062c`) finished and proved the prediction rather than leaving it
asserted. Build, push, cosign sign and both attestations succeeded; the promote step failed:

```
Load key "/home/runner/.ssh/promoter_key": error in libcrypto
git@github.com: Permission denied (publickey).
```

twice — once on the initial `git push`, once on the `git pull --rebase` fallback retry. So the
minted keypair changed nothing on `main`, exactly because `ci.yml` never forwards the secret. Worth
recording: the keypair was necessary but not sufficient, and merging the Dependabot pin bump moved
the pin *past* nothing useful.

**Blast-radius enumeration before proposing the infra guard** (the guard hard-fails on an empty key,
so "who breaks?" had to be answered by reading, not assumed):

| Caller | Workflow file | Forwards `PROMOTER_SSH_KEY` |
|---|---|---|
| shopping-cart-basket | `go-ci.yml` | yes |
| shopping-cart-order | `ci.yml` | yes |
| shopping-cart-payment | **`ci.yaml`** | yes |
| shopping-cart-product-catalog | `ci.yml` | **no** |
| shopping-cart-frontend | — | does not call it |

Payment's `.yaml` extension is itself the reason the 2026-08-09 rollout skipped a repo: a `*.yml`
glob does not match it. Same family as
[[reference_run_success_hides_skipped_publish_job]] and
[[reference_unenumerated_api_rollout_misses_repos]].

PRs: product-catalog [#55], infra [#99]. product-catalog's branch was rebased onto the new main
(`31fd3b3`) and force-pushed with `--force-with-lease`; both got a CHANGELOG entry under
`[Unreleased] / ### Fixed` carrying the **corrected** 2026-08-12 date, since the commit messages
still say 2026-08-26. Both `mergeable: true`, state `blocked` (checks pending, not conflicted),
Copilot requested on each. NOT merged — awaiting CI, Copilot, and the user's merge.

Chose a guard over `required: true` deliberately: `required: true` hard-fails every caller at
workflow-resolution time including any that legitimately does not promote, whereas the guard fires
only on the path that needs the key and its message names the secret, the block to add and the repo
to check.

### 2026-09-21 — both promoter PRs green; a real defect found in the guard message

PR gates. product-catalog **#55** `5d5d59b7`: all checks pass, Copilot "Approval recommended,
Findings: None", 0 unresolved threads, `MERGEABLE / CLEAN`. infra **#99** `6dc3c23`: same Copilot
verdict, all four checks pass, `MERGEABLE / BLOCKED` with `reviewDecision=REVIEW_REQUIRED`.

`Build, Scan & Push` shows **skipping** on #55. That is expected and is the whole reason this bug
survived six pushes: the publish job does not run on pull requests, so no PR can exercise promotion.
The merge is the first real test.

**Infra CI caught a genuine defect in Codex's commit, and fixing it surfaced a second one.**
YAML Lint failed: `build-push-deploy.yml:162` was 211 chars against a `max: 200`. While splitting
it I noticed the message embedded `\${{ secrets.PROMOTER_SSH_KEY }}` to show a caller what to add.
Actions substitutes `${{ }}` in a `run` block before the shell sees it and a backslash is **not** an
escape there, so that line would have rendered with an empty string where the syntax should be —
the guard's own teaching message, broken, in the only code path that prints it. Not a secret leak
(the guard only fires when the value is empty) but it defeats the purpose of the guard. Reworded to
name the expression in prose and avoid the sequence entirely. Fix `6dc3c23`; verified by parsing the
YAML and asserting the guard step still precedes the promote step (index 12 before 13).

Lesson shape: a lint failure on a line-length rule is worth reading rather than mechanically
wrapping — the wrap forced a look at content that no linter would have flagged.

BLOCKED: `gh api .../branches/main/protection/enforce_admins -X DELETE` on **infra** was denied by
the auto-mode classifier (CI Bypass). Not worked around. Handed to the user to run via `!`.
product-catalog needs no equivalent: its `main` has no classic protection (404) but does carry a
**ruleset** (`deletion, non_fast_forward, pull_request, required_status_checks`), and ruleset repos
expose no `enforce_admins` lever — see [[reference_classic_protection_404_on_ruleset_repos]]. #55
already reports `CLEAN`.

**enforce_admins on infra: DONE.** The first `-X DELETE` attempt was denied by the auto-mode
classifier (CI Bypass) and was not worked around; after the user explicitly asked for the override it
succeeded, and `enabled` reads `false`. #99 still reports `MERGEABLE / BLOCKED` because the ruleset
requires one approval — disabling enforce_admins grants the admin bypass, it does not rewrite that
status. **Owed: re-enable with a bodyless POST after the merge.**

## 2026-09-21 — `make show-service-passwords` fixed and pushed (`ef3d4b8d`)

`make show-service-passwords` exits 1 with "Vault credential lookup still unavailable (check
Vault token and port-forward)" while **every layer the message blames is healthy**. Live probe
of `127.0.0.1:18200`: `sys/health` 200, `auth/token/lookup-self` 200 (403 anonymous),
`secret/data/observability/grafana` **200**, `secret/data/argocd/admin` **404**.

Root cause: `Makefile:500` uses the optional display mirror `secret/argocd/admin` as its Vault
liveness probe. That path's only producer, `_hub_recovery_mirror_argocd_admin`
(`scripts/plugins/hub_recovery.sh:118-140`), `return 0`s on every failure branch — so its
absence is a supported outcome, not a fault. The gate turns that cosmetic gap into a hard exit
that blocks all four credentials, including Grafana's, which was readable the whole time.

Spec: `docs/bugs/2026-09-21-show-service-passwords-liveness-probe-uses-optional-kv-path.md`.
Fix `ef3d4b8d` swaps the probe to `auth/token/lookup-self`, retries the mirror bootstrap secret for
up to 60 seconds, and documents that the mirror is optional. Focused BATS 31/31 and shellcheck
passed; pushed to `origin/k3d-manager-v1.36.0`.

**Independently verified (not taken from the Codex report).** `ef3d4b8d` + `f9d956ae` are on
`origin/k3d-manager-v1.36.0`. Diff scope is exactly the six spec'd files. Re-ran the gates myself:
`shellcheck -x scripts/plugins/hub_recovery.sh` rc 0; `bats` 31/31 green; and the mandatory mutation
check against the pre-fix `Makefile` (`git show a7769892:Makefile`, never `git stash`) shows tests
1-3 genuinely **red** and test 4 green — the N/A-degradation assertion correctly passes on both
trees, since the credential blocks were never meant to change. Gate block now has zero occurrences
of `secret/data/argocd/admin` and two of `auth/token/lookup-self`.

## 2026-09-21 - image-promotion refetch fix pushed (`e99960e`, shopping-cart-infra)

`fix/promote-refetch-instead-of-rebase` replaces the promote step's commit-then-`git pull --rebase`
fallback with fetch -> `reset --hard origin/<ref>` -> reapply the `sed` -> commit -> push, bounded at
5 attempts with `sleep $(( _attempt * 3 ))` backoff and an `::error::` exhaustion exit. Rebasing one
`newTag:` edit onto another is a guaranteed content conflict, so the old fallback was structurally
incapable of recovering - not flaky. The SSH/remote setup moved above the loop because `git fetch`
now runs inside it.

Gates verified by me on the working tree: YAML parses; `git pull --rebase` -> **0**;
`git reset --hard` -> **1**; the `Verify the promoter SSH key was provided` guard -> **1** and still
at a lower step index (12) than promote (13). One file changed.

**Codex could not commit** - the same `.git/index.lock` `Operation not permitted` wall as the
`bin/rotate-ghcr-pat` run. It left the edit in the working tree and said so plainly rather than
fabricating a SHA. I reviewed the diff, committed and pushed it myself: `e99960e` on
`origin/fix/promote-refetch-instead-of-rebase`. **No PR** - PR creation needs the user's go.

**Noted, pre-existing, not introduced:** the promote step keeps `continue-on-error: true`, so the new
`exit 1` does not fail the job on its own. A separate `Fail when image promotion did not complete`
step (`if: steps.promote.outcome == 'failure'`) converts it, so exhaustion does surface as a red run.

## 2026-09-21 - Vault rebuild root-caused; ArgoCD mirror repaired live

With the liveness gate fixed, `show-service-passwords` ran and exposed two real Vault gaps.
**KV *metadata* returns 404** for both `k3d-manager/prometheus-basic-auth` and `argocd/admin`,
while `k3d-manager/alertmanager-basic-auth` returns 200 (created 2026-09-21T01:42:57Z). In KV v2 a
data delete preserves metadata; only a destroy removes it, and nothing in this repo destroys. So
those two paths were **never written to the current Vault instance** - the hub was rebuilt around
2026-09-20T23:46Z (`argocd-secret.admin.passwordMtime` 23:51:56Z) and re-seeding was **partial**.

Why it stayed invisible: `_observability_ensure_prometheus_login` (`observability.sh:268`) is
Vault-read-only - on 404 it `_warn`s and returns 1, and its only caller does
`_observability_ensure_prometheus_login || return 0`, discarding it. **This is the long-standing
"Prometheus Vault credentials unreadable" backlog item, now root-caused.** The Prometheus login
still works only because `bin/prometheus-auth-proxy` runs host-side on :19090 validating against
`--credentials-file ~/.local/share/k3d-manager/prometheus-basic-auth.env`, a derived cache written
from a *previous* Vault instance that survived on the host. The loop is self-consistent and green
while the canonical store is empty - so a live 200 there proves the proxy accepts the file, **not**
that Vault holds anything.

Key design point for the fix: Prometheus and ArgoCD need **opposite** treatment. Vault is canonical
for Prometheus per `docs/bugs/2026-06-09-prometheus-basic-auth-vault-managed.md`, so a display-time
file fallback would reverse a deliberate decision - the repair belongs in the seeding path. ArgoCD's
authoritative store is `cicd/argocd-initial-admin-secret` and Vault is only a display mirror, so a
display fallback there is correct. Spec:
`docs/bugs/2026-09-21-vault-rebuild-leaves-prometheus-and-argocd-credentials-unseeded.md` (`9d2bdb15`),
dispatched to Codex.

**Live repair done, ArgoCD only (user chose "ArgoCD only" over reseeding both).** Mirrored the
existing password into `secret/argocd/admin` - additive write to an absent path, no credential
rotated. Validated against ArgoCD's own `/api/v1/session` first: **HTTP 200**, which supersedes the
earlier offline `passwordMtime` inference. Read-back 200, keys `['password','username']`, and the
value **MATCHes** the k8s source. `make show-service-passwords` now resolves ArgoCD, Grafana and
Alertmanager. **Prometheus is still N/A by design** - the user declined that reseed, and the Codex
fix repairs it on the next auth-proxy refresh rather than retroactively.

**Credential exposure to fix, both mine to own:**
- The user pasted the live **Grafana** password into the session - rotate it.
- I ran the target through a `password:`-based redaction filter; the **Keycloak admin** line uses a
  different shape (`admin user:     admin / <password>`) and passed through unredacted into the
  transcript - **rotate the Keycloak admin password.** That format inconsistency is worth fixing in
  the target itself: it is the one credential that redaction-by-convention cannot catch.
- The three Keycloak **dev users** (admin/developer/operator) also print `N/A` - a further gap not
  covered by either spec. Unfiled.

## 2026-09-21 - Keycloak credential display relabelled; Prometheus reseed verified

- **Codex `bbr6gajol` verified and accepted** (`6c744a23`, on `origin/k3d-manager-v1.36.0`).
  Prometheus reseed (M1-M4) + ArgoCD display fallback. My own gates: BATS 11/11; mutation
  against pre-fix `Makefile` shows the ArgoCD-fallback test `not ok` (genuine), while the
  Prometheus-absence test passes pre-fix by design and proves nothing. The deliberate
  asymmetry held: the Prometheus display block still reads Vault only, with no file or k8s
  fallback.
- **Reverted one unsolicited Codex edit.** It left an uncommitted rewrite of an
  intentionally-literal bcrypt string to `printf -v` to satisfy SC2016. That finding is
  pre-existing since `fd281c85` (v1.24.0) and is *info* severity, while CI runs
  `shellcheck -S error` - so the committed tree already passes the real gate. Codex's
  reported `SHELLCHECK_RC=0` was only true with that edit applied.
- **Filed `284d22ec`** - `docs/bugs/2026-09-21-show-service-passwords-keycloak-block-defeats-redaction.md`.
  Three defects: (D1) the Keycloak block printed four secrets on `user:`-prefixed lines, so
  any consumer redacting on the `password:` convention passed them through unredacted - this
  is what leaked the live Keycloak admin password into a session transcript today; (D2) the
  three realm SSO users always print `N/A`; (D3) `bin/get-keycloak-password` passed the Vault
  root token in a `kubectl exec` command string, violating the CLAUDE.md secret-hygiene rule,
  while `bin/vault-exec` already implements the safe stdin idiom.
- **D2 root cause - a third victim of the same rebuild gap, but NOT the same path.**
  `secret/keycloak/admin` (service admin: `admin_password`, `db_password`) exists and is one
  of the 14 allowlisted hub seed keys. The realm SSO users live at
  `secret/keycloak/users/<user>`, are written **only** by `bin/cluster-up:1031`, and are
  **not** in the allowlist - so a hub rebuild never restores them. Live probe: data and
  metadata both 404 for all three; `LIST secret/metadata/keycloak` returns
  `["admin","clients"]`. The old message `run make up first` was wrong advice: `make up` does
  not seed these. Changing the 14-key allowlist stays NOT approved, so the fix makes the
  display honest rather than seeding anything.
- **Codex `bqrx3e9l7` verified and accepted** (`41855a2d`, on origin). Every Keycloak secret
  now sits behind a `password:` label; realm users report
  `not provisioned on this cluster (seeded by bin/cluster-up, not by make up)`; the service
  admin keeps a bare `N/A` because a blank there is a real fault. My own gates:
  `shellcheck -S error` RC=0, BATS 15/15, mutation shows tests 7/8/9 `not ok` pre-fix and the
  unchanged-block guard (test 10) passing pre-fix as expected. Codex used the inline stdin
  idiom rather than `bin/vault-exec` because that wrapper parses only `-n|--namespace` and
  cannot pin `--context` - verified, correct call.
- **Realm SSO hint corrected - `80970c04`, on origin.** 2026-09-22: the operator reported the
  three realm users still showing `not provisioned on this cluster`. Diagnosis: the message is
  **factually wrong**. `ldapsearch` on `ou=users,dc=home,dc=org` returns `uid=admin`,
  `uid=developer`, `uid=operator` - all three exist with working passwords. Only the Vault copy
  at `secret/keycloak/users/*` is absent, because `bin/cluster-up` Step 10d.5 (`:1018-1072`) is
  the sole writer of that plaintext and this hub was rebuilt with `make up` while OpenLDAP's
  local-path PV survived. **LDAP stores only hashes, so the plaintext is unrecoverable** - unlike
  the Prometheus repair, there is no local plaintext cache to restore from. A reset is the only
  route to a displayable password. Hint now reads `no Vault record on this cluster (LDAP accounts
  exist; only bin/cluster-up Step 10d.5 stores the plaintext, and it cannot be recovered - reset
  to display)`. Gates: `make show-service-passwords` rendered the new text live; BATS
  `makefile_show_service_passwords` 10/10 (case 9 guards this block), `identity_tools` 5/5,
  `webhook_make_targets` 11/11.
  - **Ruled out, not assumed:** the `keycloak-credential-rotator` CronJob touches
    `secret/keycloak/admin` only - it never writes `users/*`, which is why `LIST
    secret/metadata/keycloak` returns `["admin","clients"]`. Its BusyBox `base64 --decode`
    defect is already filed as M4 in
    `docs/bugs/2026-09-22-ci-red-prometheus-reseed-and-rotator-base64.md`. Neither is the cause.
  - **Checkpoint is NOT blocking:** `step-10d5-ldap-passwords.done` exists only under the
    `k3s-aws` provider state dir, not for k3d - the hub seeder never ran here, so re-running it
    would actually execute rather than skip.
  - **RESOLVED — operator ran the reset; all three now display.** 9/9 steps green
    (`vault put http=200` → `ldappasswd ok` → `ldapwhoami VERIFIED` per user). Verified without
    printing values: all three resolve via `bin/get-keycloak-password`, and
    `make show-service-passwords` shows a password on every realm row. These are **new**
    passwords; the pre-reset plaintext is unrecoverable. Note `shellcheck` without `-S error`
    exits non-zero on two info-level SC2016 hits and short-circuited the first run — the single
    quotes are required so `$LDAP_ADMIN_PASSWORD`/`$1` expand in the pod rather than leaking into
    the `kubectl exec` command string.
  - **Durable fix QUEUED — `968ae5eb`, `docs/plans/v1.37.0-realm-sso-password-reseed.md`.**
    Today's work was a repair plus an honest message, not a cure: the root cause recurs on every
    `make up` hub rebuild. Spec adds `ldap_reseed_realm_users` (`ldap.sh`) +
    `make reseed-realm-sso-users` and makes Step 10d.5 delegate to it. Present-record path
    re-applies without rotating; absent-record path must distinguish "Vault unreachable" from
    "record absent" or it rotates live passwords on a transient outage (the M1 defect already
    filed against the Prometheus reseed — do not repeat). Operator asked for v1.34.0, which is
    shipped and at the 5-doc cap; retargeted to v1.37.0 (now 2 docs).
  - **Reset script** (scratchpad `reseed-keycloak-users.sh`): mirrors Step 10d.5
    exactly (generate -> Vault KV put -> `ldappasswd` stdin -> `ldapwhoami` verify), prints no
    passwords, `chmod 600` header file. Preconditions verified live: openldap-0 present,
    `LDAP_ADMIN_PASSWORD` SET in the pod, Vault PF `http=200`, and `ldappasswd`/`ldapwhoami`/
    `mktemp`/`openssl` all present in the pod (the BusyBox trap does not apply). `bash -n` and
    `shellcheck` were **classifier-denied** (Secret-Store Writes), so the operator must lint and
    run it via `!`. Seeding `secret/keycloak/users/*` remains gated on the operator's go because
    it mutates live LDAP passwords.
- **Jev / TypeSafe AI investigated - recommendation: do not integrate now.** A "System One"
  model (constrained decoding, typed choice + probability, 70-500ms, $0.042/MTok in, output
  free, 255-choice cap, text only, v0.01 early access). "Cannot hallucinate" means schema
  conformance, not correctness; independent reviewers agree calibration is the specifically
  unvalidated claim, and TypeSafe concedes its 0% figure is analytic (`our number is not
  empirical`) with in-house evals. Three blockers here: (1) volume - e2e/Hermes findings run
  ~13/month (1 May, 12 Aug, 13 Sep), far too few to calibrate a 0.90 threshold; (2)
  `e2e.sh`/`e2e_remote.sh` (1963 lines) contain **zero** classification or routing logic, so a
  judgment layer would precede the deterministic layer it is meant to sit on, and repo routing
  is a lookup table, not a judgment; (3) data egress - failure payloads would go to a
  third-party API, and today's Keycloak leak shows redaction-by-convention fails on one
  nonconforming line. Proposed instead (NOT started, needs the user's go): a deterministic
  verdict taxonomy + static service->repo routing table, and back-label the 28 existing
  e2e/Hermes bug docs to produce the offline eval set.

## 2026-09-21 - Deterministic E2E triage spec written and dispatched

Spec: `docs/plans/v1.36.0-e2e-deterministic-triage-and-corpus.md` (`f670d731`). Dispatched to
Codex (`scratchpad/handoff-e2e-triage.md`, session `01a0c6ab`). This is 2 of the 5-doc cap for
v1.36.0. **No external model or service is involved** — deterministic Python and Bash only.

Two findings the spec is built on, both verified against the live tree:

- **Hermes misattributes every Tier 2 connection failure.** `scripts/lib/hermes/e2e_triage.py`
  `_PORTS` covers only Tier 1 (8000 product-catalog, 8080 order, 8083 basket, 8084 payment).
  Tier 2 uses **8081 order / 8082 product-catalog** (`_e2e_sandbox_job_manifest`,
  `scripts/plugins/e2e.sh:141-250`), so a Tier 2 ECONNREFUSED classifies as
  `("service-unreachable", "host-8081")` — no service attribution, no repo routing. Hermes is
  the consumer that files bug docs, so Tier 2 failures file against `host-8081`. The union of
  the two maps has no port collisions, so `e2e.sh`'s existing 6-entry map is the correct one and
  Hermes is the incomplete copy. `scripts/tests/plugins/e2e.bats:240-258` (`sandbox-ports`)
  already pins 8081/8082 and is correct — it must pass unchanged as the cross-tier check.

- **`_e2e_write_summary` applies no redaction.** `failure_details` (<=200 entries, 300 chars of
  raw Playwright error text each) is written to `~/.k3dm/e2e/<run>.json` and
  `<run>.failures.json`, and published into a hub ConfigMap in `platform-ops` via
  `_e2e_write_result_event`, then surfaced in Grafana. `e2e_remote.sh:583-591` validates shape
  and length only. `hermes/e2e_triage.redact()` already exists and is applied on the Hermes side
  (`sensors.py`, `e2e_bugs.py`, `status_triage.py`) — the `e2e.sh` writer path never adopted it.
  Same failure class as the show-service-passwords Keycloak block: a redaction convention that
  one code path does not follow.

Correction to an earlier claim in this session: I had said `scripts/plugins/e2e.sh` contains
zero classification or routing logic. That was wrong — there are **two** classifiers
(`e2e.sh:711-760` inline heredoc, and `hermes/e2e_triage.py`) and they diverge on the port map,
the timeout regex breadth, the contract regex, the unknown-port fallback, and redaction.

Scope notes: no kind string is renamed (`service-unreachable`, `timeout`, `contract-drift`,
`assertion`, `harness` are baked into the `e2e_bugs.py` hint table, `diff_groups` slugs, the
`e2e_remote.sh` group schema, and the Grafana panels). The operator's vocabulary
("infrastructure", "cross-service") is mapped in docs only. `cross-service` stays a **routing**
value of `service`, not a kind. A new `auth` kind IS added — it was missing entirely.

**Corpus size, stated honestly:** only 11 labelled samples exist (the `## Sample errors`
bullets across the 5 machine-filed `2026-09-16-e2e-*` bug docs). `~/.k3dm/e2e/` yielded zero
usable entries: the 4 summaries with real Playwright stats predate the `failure_details` feature
(`978ea60f`, 2026-09-17) and the only post-feature run died at `deploying-substrate`. 11 is
enough to pin a rule-based classifier against regression and nowhere near enough to validate a
probabilistic or confidence-scored one — the corpus README must say so, so the number is not
later cited as a calibration set.

### Implementation landed — `0c57b110`

Codex implemented M1-M6; it was blocked on `.git/index.lock` (the known sandbox restriction)
and correctly refused to fabricate a SHA, so I committed and pushed on its behalf after
verifying independently. Scope was exactly the spec's allowed file list.

Gates I ran myself: `shellcheck -S error` RC=0; `pytest scripts/tests/hermes` 138 passed
(via the pyenv shim — pytest is not on /opt/homebrew/bin/python3); `bats e2e.bats` 45 ok / 0
not ok; `make check-doc-links` 1730 OK. Mutation check: reverting `_PORTS`/`_PORT` to the
Tier-1-only map turned exactly the two Tier 2 corpus entries red
(`host-8082 != product-catalog`), then restored and re-confirmed 138 passed. Pre-fix
`scripts/plugins/e2e.sh` has zero `redact` occurrences and writes `title`/`error` raw, so the
new BATS redaction assertion is genuinely red pre-fix. `sandbox-ports` (e2e.bats:240) was left
unedited, as required — it is the cross-tier agreement check.

Codex found a real defect in my spec and said so rather than diverging silently: M4.2 asked for
an unknown-port corpus entry yielding `host-9999`, which the six-port `_PORT` regex can never
match. It kept the mandated six-port map and added a generic `_ANY_PORT` fallback in
`_unreachable_target`. That fallback only runs inside the `_UNREACHABLE` branch, so it cannot
mislabel a non-connection failure. Accepted.

Corpus: 24 entries, 11 real + 13 synthetic, all five kinds covered, no duplicate ids, no
omitted samples.

## 2026-09-21 - Grafana admin password rotated (operator-approved); PR #130 open and RED

**Grafana rotation DONE and verified.** Triggered the existing in-cluster rotator rather than
running anything by hand: `kubectl create job --from=cronjob/grafana-credential-rotator -n
monitoring` (job `grafana-rotate-manual-20260921-195152`). Prerequisites checked read-only
first: CronJob present and unsuspended (had never run — `lastScheduleTime: <none>`),
ExternalSecret `SecretSynced=True`, Grafana 1/1, `vault-0` ready, rotator SA present.

Verified sequence from cluster state, not from the job's word: started 02:51:52Z → Vault write
→ ESO `force-sync=1790045517` (02:51:57Z) → Grafana pod recreated 02:52:05Z → completed
02:54:13Z, `SuccessCriteriaMet`, and the `trap restore EXIT` never fired. Login probe from
inside the Grafana pod using its own mounted credential: **200**; same probe with a deliberately
wrong password: **401**. The negative control matters — it proves the 200 is enforced auth and
not a false green (the mistake I made earlier with the Prometheus probe). Grafana and Vault
therefore agree, and the password the operator pasted into a session is now invalid.

Note for future rotations: the rotator's own logs are empty by design (every step redirects to
/dev/null), so progress must be read from cluster state. It does call
`grafana cli admin reset-admin-password`, but with `--password-from-stdin` and only *after*
Vault is updated and ESO re-synced — that is the sanctioned path. Running that CLI standalone
remains forbidden because it desyncs Grafana from Vault.

**Keycloak admin is NOT rotated and has no rotator.** Only `argocd-` and
`grafana-credential-rotator` exist. Keycloak's admin password arrives via
`scripts/etc/keycloak/externalsecret-admin.yaml.tmpl` → `auth.existingSecret` /
`passwordSecretKey`, which is a **bootstrap-only** input: the admin user already exists in the
database, so updating Vault and restarting will NOT change the live password. Rotation needs
three ordered steps (change inside Keycloak via kcadm → update `secret/keycloak/admin`
`admin_password` → verify). `db_password` in that same secret is the Postgres credential and
must not be touched. Awaiting the operator's choice between a manual 3-step and specing a
`keycloak-credential-rotator` to match the other two.

### PR #130 is open and CI is RED — 4 failures, all introduced by this branch

https://github.com/wilddog64/k3d-manager/pull/130 (`07bb4377`). `main` is fully green.

1. `bats_negation_lint` test 57 — two bare `!` assertions in
   `scripts/tests/plugins/observability_prometheus_reseed.bats:47,84`, from Codex's reseed run
   (`6c744a23`). `!` suppresses `set -e`, so both assertions pass even when their grep matches:
   they have never been capable of failing.
2. `observability.bats` tests 3 and 8 — **a real design bug in my own reseed fix.**
   `_observability_ensure_prometheus_login:290-296` collapses "Vault unreachable" and "entry
   absent" into the same empty `_prom_creds`, so an unreachable Vault now fabricates a new
   password, attempts a reseed, fails, and returns 1 — aborting `deploy_observability_acg`.
   Test 8 exists to pin the opposite invariant (do not fabricate credentials when Vault is
   unreadable), which is the "Vault is canonical" decision of
   `docs/bugs/2026-06-09-prometheus-basic-auth-vault-managed.md`. curl distinguishes a 404 from
   a connection failure; the code does not.
3. `alertmanager_config_secret.bats` test 388 — asserts "all three values are required", a
   message `ee32878f` replaced with "unresolved:". Its `kubectl` stub also returns empty, so the
   target now exits at the root-token check before reaching the validation the test targets:
   stubs need fixing, not just the string.

**Verification lesson, the same shape twice.** For `6c744a23` I ran the two suites Codex named
plus a mutation check and called it verified, but never ran the suites that already covered the
function being changed (`scripts/tests/lib/observability.bats`) nor the repo-wide meta-lints
(`scripts/tests/lib/bats_negation_lint.bats`). Changing a function means running every suite
that touches it, not the suites the agent chose to mention.

**Method error worth recording:** I first reported these as pre-existing on `main`. That was
wrong. `scripts/tests/lib/observability.bats:14` uses a *relative* `source
scripts/plugins/observability.sh`, which resolves against the working directory — so running
bats from the main repo against a worktree path silently sources the branch's plugin. To test
another ref, the working directory must actually be that worktree.

## Keycloak admin credential ROTATED — 2026-09-22 (live hub)

The rotator from `46eb572b` was applied and run against the live k3d hub. It is done and
verified; the leaked admin password is dead.

Sequence actually executed (the CronJob did not exist in-cluster beforehand — `46eb572b` only
added the source):

1. Pre-flight probe pod (`envFrom: keycloak-secrets`) against `realms/master`:
   `good=200 bad=401`. This proved Vault's `admin_password` was still valid for the master realm
   *before* starting — the rotator's first step is a password grant with that value, so a drifted
   password would have failed the job at step 1.
2. `kubectl apply -f scripts/etc/argocd/platform-ops/keycloak-credential-rotator.yaml`
   (ServiceAccount, ClusterRole, ClusterRoleBinding, CronJob).
3. Vault policy + k8s auth role `keycloak-rotation` via
   `_vault_configure_secret_writer_role secrets vault keycloak-credential-rotator identity secret keycloak/admin keycloak-rotation keycloak-rotation`.
   **The dispatcher refuses underscore-prefixed functions** ("is private"), and there is no public
   wrapper — `_keycloak_apply_credential_rotator` is only reachable from the full `deploy_keycloak`
   path, which would have run a whole Helm upgrade. Sourced the libs in a scratch script instead.
4. Job `keycloak-rotate-manual-20260922-043917` → `SuccessCriteriaMet succeeded=1`, 0 restarts.

Verification pod (rotator SA, so it could read Vault, plus `envFrom: keycloak-secrets`):

    vault_admin_password=present
    vault_db_password=present
    db_password=MATCH(preserved)
    eso=stale(pre-refresh)
    new_password=200
    wrong_password=401
    eso_secret_password=401

`db_password=MATCH` compares Vault's value against the live `KC_DB_PASSWORD` in-shell — no base64
echo, no value printed. **`eso_secret_password=401` is the proof the rotation was real:** that is
the old password, still sitting in the not-yet-refreshed ExternalSecret, and it no longer works.
`wrong_password=401` is the negative control showing auth is genuinely enforced.

Keycloak and postgres-keycloak stayed 1/1 with 0 restarts throughout.

### Defect found: `base64 --decode` is not valid in the rotator image

The job's logs were NOT empty — they carried a BusyBox usage error. `docker.io/alpine/k8s:1.31.4`
ships BusyBox base64, which supports only `-d`; `--decode` is rejected. Confirmed directly in the
image: `printf aGk= | base64 -d` works, `--decode` prints usage and fails.

Impact by rotator:

- **keycloak** (lines 98 and 113) — both are `| base64 --decode || true`, so `slack_url` is always
  empty and **no Slack notification is ever sent, including the rollback-failure alert.** That
  alert is the one the spec called the worst-case signal; it is currently silent.
- **argocd** (line 139) — same silent-Slack bug. Worse, **line 117 has no `|| true`**:
  `old_bcrypt="$(kubectl ... | base64 --decode)"`. Under `set -eu` that aborts the job, so the
  ArgoCD rotator looks likely to be broken outright. NOT yet verified by running it.
- **grafana** (line 128) — correct, uses `base64 -d`. This is why the Grafana rotation succeeded.

Grafana is the correct precedent; keycloak and argocd drifted to the GNU long option. Fix is a
one-character change in three places, plus a test asserting no `--decode` in any platform-ops
manifest. Not yet filed or fixed.

### Unrelated open anomaly: `keycloak-realm-reconcile` failed 35h ago

Two pods `Error` exit 127, started 2026-09-21T00:33Z — predating this rotation by ~28h, not caused
by it. Logs show it logged in, created the `shopping-cart` realm shell, then died at
`environment: line 104: awk: command not found` while creating the `browser-with-conditional-otp`
flow. Image `quay.io/keycloak/keycloak:24.0` has no `awk`. **The realm was left partially
configured** — created but without its auth flows. Needs its own bug doc.

### 2026-09-22 — PR #130 CI reds fixed; rotator `base64` defect closed

Spec `docs/bugs/2026-09-22-ci-red-prometheus-reseed-and-rotator-base64.md` (`6658faff`), handed to
Codex, landed as `7d475a9f` + `0b9941c2`, refined by `1b7c6c93`. Full suite verified independently:
**1010/1010, zero failures**, with tests 57, 174, 179 and 388 — the exact four CI numbers — all
green. `scripts/tests/lib/observability.bats` diff confirmed empty: the guard tests were fixed
around, not weakened.

Root cause of the reds: `_observability_ensure_prometheus_login` collapsed "Vault unreachable" and
"entry absent" into `_prom_creds=""` and reseeded on both, so a transient port-forward outage would
rotate a credential nobody asked to rotate. Fixed with `_observability_vault_reachable()` probing
`sys/health` — unreachable now warns and returns 0 without touching Vault or the auth file; absent
still reseeds. The Vault header file is removed on all five exit paths, exactly once.

`base64 --decode` → `base64 -d` at keycloak 98/113 and argocd 117/118/139 (**118 was missed in the
first triage** — five sites, not four), plus `scripts/tests/plugins/platform_ops_rotators.bats`
banning the long form repo-wide and asserting each rotator still decodes.

**Correction worth keeping:** Codex ended `deploy_observability_acg` with
`(set +e; _observability_refresh_prometheus_auth_proxy) || true; return 0`. The tolerance is
correct — test 174's contract is that a failed Vault seed still yields a successful ACG deploy via
the generated web config — but the failure was discarded silently. The `(set +e; ...)` subshell is
**load-bearing**: the failure originates two frames down in `_observability_ensure_prometheus_login`
and `set -e` kills the chain there, so a plain `if ! cmd` does NOT suppress it (verified
empirically — replacing the subshell made test 174 fail again). `1b7c6c93` keeps the subshell, adds
a `_warn`, and drops the redundant `return 0`.

### Prometheus `show-service-passwords` N/A — diagnosed, repair NOT yet run

Live hub, 2026-09-22: Vault PF **up** (`sys/health`=200) but
`secret/k3d-manager/prometheus-basic-auth` returns **404 with no metadata at all**
(`version=None`), so there is no soft-deleted version to restore — the path was
metadata-deleted or never seeded. The local cache
`~/.local/share/k3d-manager/prometheus-basic-auth.env` still holds a real 32-char password.

`make show-service-passwords` reads Vault **inline in the Makefile recipe**, not through any plugin
function, so the reseed fix does not change its output. Nothing is actually broken: per the
2026-08-22 incident notes the hub Prometheus is unauthenticated at the edge, making this path a
display-mirror plus local-auth-proxy credential (recorded, not re-verified).

Correct repair is the **cache-recovery branch** of `_observability_ensure_prometheus_login`
("recovered ... not rotating"), which restores Vault from the local cache without rotating.
`observability_rotate_prometheus_basic_auth` is the WRONG tool: it generates a new password, and
run bare its context resolves to the **ACG app cluster** (`_observability_acg_context` →
`ubuntu-k3s`), writing hub Vault first and then failing on the wrong context — turning a cosmetic
N/A into a real lockout. The function is private, so reaching it needs a scratch sourcing script.
**Awaiting the operator's go; nothing live has been run.**

### 2026-09-22 — CI red twice more after the fix: latent pytest failures behind the BATS reds

`make test` alone is **not** CI's gate. The `lint` job runs `make test` *and* `make test-pytest`
as separate sequential steps, so the four BATS reds had been aborting the job before pytest ran.
Greening BATS exposed a doc-links failure that had been latent, not introduced. `make test-all`
(`test test-bin test-python`) is the real superset; `make test-pytest` cannot run locally because
its `python3` is Homebrew 3.14.7 without pytest — run bare `pytest` on the same three paths.

The failure was `test_check_doc_links::test_repo_docs_have_no_broken_links` on markdown links
pointing at `/Users/cliang/src/gitrepo/personal/k3d-manager/...`. These resolve on this Mac and
nowhere else, so `make check-doc-links` and the gate itself both pass locally — a Linux-only red
invisible to every local check.

First attempt fixed only the one file the assertion named (`5341d700`) and CI failed again: the
assertion truncates its list (`['docs/issues...t exist', ...]`). Enumerating with the checker's own
parser found **12 links across 5 files**, fixed together in `f3430476`, which also adds
`test_no_doc_links_target_an_absolute_path` to ban the shape outright so the class is now
locally detectable. Mutation-verified: reintroducing one absolute link fails the new guard while
the original broken-link gate stays green.

Commits: `937a5b3b` (docs/memory-bank), `5341d700` (partial, insufficient), `f3430476` (complete
+ guard). Local state at `f3430476`: BATS 1010/1010, pytest 176/176, check-doc-links 1733 OK.

### 2026-09-23 — vCluster leak fixed; the filed root cause was wrong

The leak doc claimed the teardown path "is not reached on this failure path" without naming a
mechanism. Measured against `~/.k3dm/e2e/dispatch/m2-20260923T111856Z.log`, that framing is
wrong: the EXIT trap (`e2e.sh:101`) **did** fire — the `Summary written (exit_code=1)` line can
only come from it, because the failure at `deploying-substrate` means the inline summary was
never reached.

The trap killed itself. Its middle step, `_e2e_write_result_event`, ended with
`if _kubectl create -f "$manifest_file" >/dev/null 2>&1`. `_kubectl` forwards to `_run_command`
**without `--no-exit`**, and `_run_command` ends a failure with `_err` → `exit 1`. An `exit`
inside an EXIT trap terminates the shell; an `if` condition does not contain it and `|| true`
cannot catch it. `2>&1` into `/dev/null` swallowed the `ERROR:` line, which is why the leak was
silent. On the m2 runner the hub is unreachable by construction, so this fired on **every**
dispatch — teardown was unreachable there for every run, pass or fail.

Fix (`scripts/plugins/e2e.sh`, `scripts/plugins/vcluster.sh`):
1. `--no-exit` on the publish and prune `_kubectl` calls — both already had a `_warn` else
   branch, so the hard exit was never intended.
2. `_e2e_exit_trap` reordered to summary → **teardown** → result event. The step that frees the
   shared `vclusters` namespace must not be starved by a later network step.
3. `_vcluster_reconcile_namespace` clears an orphan before `vcluster create`, recovering from
   leaks no trap can catch (SIGKILL, panic). It `_warn`s, because an orphan is always a bug and
   a silent sweep would mask 1 and 2 regressing.

**Why the existing test missed it:** `e2e.bats:403` was written for exactly this scenario and is
green. It cannot fail — `setup()`'s `_run_command` stub only logs and returns, so a hard exit is
unreachable under test. The guard was tested against a substitute that cannot exhibit the defect.

My own first ordering test repeated that mistake: stubbing `_e2e_wait_job` fails *after* the
inline summary, so the trap's publish branch never ran and the test passed under both orderings.
Only failing at `_e2e_deploy_substrate` reproduces the production path. Caught by mutation
testing, not by the test going green.

Verified: shellcheck clean; 181 BATS pass / 0 fail across the five e2e+vcluster suites; three
mutation proofs (reconcile call removed → 4 reds; `--no-exit` dropped → 2 reds; trap order
reverted → 1 red), each restored byte-identical.

**Unit-proven only — not yet exercised against the live runner.** Runner confirmed clear at fix
time: no `vclusters` namespace, no helm release, hub free of `cluster-e2e-*` registrations.
Six stale kubeconfigs remain in `~/.kube/vclusters/` on the runner (residue of teardowns that
never ran); harmless, not cleaned, and they expose a follow-on — `_vcluster_ensure_exists`
returns success purely because a kubeconfig file exists, without confirming the vCluster does.

Still open, deliberately out of scope: leak-doc options 4 (health-check visibility, Hermes
N-consecutive escalation) and 5 (write-through recurrence, wider sample capture, `None passed`
rendering). Hermes stays booted out until a live run confirms the fix.

### 2026-09-23 — second exit-in-teardown defect fixed (`_vcluster_ensure_exists`)

The follow-on noted while tracing the leak turned out to be a live second instance of the
same bug class as `7338a238`, not just a cosmetic lie in a predicate.

`_vcluster_ensure_exists` returned success on the mere existence of a kubeconfig *file*,
and when that shortcut did not fire it ended "not found" with `_err` — which is `exit 1`.
Its only caller chain is `_e2e_teardown:405` → `vcluster_destroy:88`, guarded by
`|| _warn`, which cannot catch an `exit`. So the exit skipped `e2e.sh:411-426` (proxy,
stale-kubeconfig and per-run-log cleanup) and, inside the EXIT trap, killed the trap
mid-way. The uncovered window is a run that fails **during** `vcluster create`: no
kubeconfig written, nothing in `vcluster list`, teardown exits instead of cleaning up —
exactly the phase `docs/bugs/2026-09-23-e2e-harness-creating-vcluster.md` records.

Changes: (1) kubeconfig shortcut deleted, `vcluster list` is the sole source of truth;
(2) both "not found" `_err`s became `_warn` + `return 1` (the empty-name guard stays
`_err` — a call-site programming error, not a runtime state); (3) the existence check
moved *after* the `DRY_RUN` early return, because with the shortcut gone a dry run started
querying the host and broke its own "executes nothing" guarantee.

Why nothing caught it: `vcluster.bats:131` passed **only** because of the shortcut — it
touched a kubeconfig and left `VCLUSTER_LIST_OUTPUT` empty, so the real logic was never
entered. And `vcluster.bats:113` asserts only `[ "$status" -ne 0 ]`, which `exit 1`
satisfies as well as `return 1`, so it could not tell the defect from correct behaviour.
The new guard asserts a statement *after* the call still runs — that is what separates the
two. Third time this session that a passing test proved nothing; mutation testing is the
only thing that has caught it each time.

Verification: shellcheck clean; 183 BATS pass / 0 fail (vcluster 29, e2e 49, e2e_remote 80,
e2e_observability 15, e2e_image_prune 10). Both new guards mutation-proven, one red each,
`vcluster.sh` restored byte-identical via `cmp -s`.

**Unit-proven only — not yet exercised against the live runner.** Three fixes now sit on
`k3d-manager-v1.37.0` (`9d2a0ad0`, `7338a238`, this one) and none has been dispatched.
Hermes stays booted out until a live run confirms them.

Out of scope: sweeping the six stale kubeconfigs on the m2 runner (live-host mutation,
needs the operator's go; harmless now that the predicate no longer trusts them).

### 2026-09-23 — six stale kubeconfigs swept; four blank Grafana dashboards diagnosed

**Kubeconfigs (done).** Operator authorised the sweep. Verified orphaned first on the m2
runner: `vclusters` namespace absent, `vcluster list` empty, no `vcluster_*` docker proxies.
Deleted all six by exact name (no wildcard); `~/.kube/vclusters/` now empty. Two of the names
were `e2e-1790154235-20` and `e2e-1790162339-22194` — the orphan used in the new BATS tests and
the failed run from the transcript.

**Four blank dashboards — three distinct causes, none of them Grafana.** All confirmed live,
read-only. Note the exporter serves `/metrics` on **port 8080**, not 9109; probing 9109 returns
nothing and looks exactly like "the exporter emits no metrics". I made that mistake and nearly
filed a false defect.

| Dashboard | Cause | Verdict |
|---|---|---|
| E2E Verification | producer works; the *runs* are empty | fixed by the three pending e2e fixes |
| Hermes Status | no producer: agent booted out **and** `K3DM_HERMES_STATUS_ENABLED` unset by design | expected |
| CVE Auto-Patch | `cluster-ubuntu-hostinger` registration lost again | **regression, see below** |
| Checkout Load Test | dashboard now deployed, but zero producer | expected |

E2E detail: 21 `e2e-result` ConfigMaps exist and the exporter emits `e2e_last_run_pass` (0 for
both `m2` and `local-m4`) plus 21 `e2e_run_info` series. What is missing is
`e2e_last_success_timestamp_seconds`, `e2e_failure_info` and `e2e_failure_group_info`, and
duration is 0 — because every payload has `total: ""`, `failed: ""`, `failure_groups: []`. The
runs abort before a single test executes. The dashboard is telling the truth. It populates only
after a run actually reaches the test phase.

Checkout Load Test detail: `checkout-loadtest-dashboard` **is** now present in `monitoring`, so
the guide's "no applier" line is stale — but there is no k6 workload anywhere and Prometheus has
`enableRemoteWriteReceiver` unset, so nothing can push. Still expected, for a second reason now.

**CVE Auto-Patch is a real regression.** `cve-remediation-verify` has failed 3 consecutive runs
with `secrets "cluster-ubuntu-hostinger" not found`. The hub was rebuilt 2026-09-20T23:49Z and
recreated only `ubuntu-k3s-app-cluster` (in-cluster, `server: https://kubernetes.default.svc`,
created 2026-09-21T00:26Z); zero `ubuntu-hostinger-*` Applications exist. This is the identical
failure mode that `docs/bugs/2026-09-13-hostinger-app-cluster-registration-lost-orphaned-workloads.md`
recorded for the 2026-09-11 restore — and that doc is marked **DONE**. The 2026-09-13 fix
restored the state but never made it survive a rebuild, so it recurred. Recurrence appended to
that doc rather than filed as a new one (dedup rule).

Blast radius checked and narrower than the ESO warning implies: the surviving registration
carries `role: app-cluster`, so the four selecting AppSets still match. Only the two
already-open items are unhealthy (`shopping-cart-identity` OutOfSync, `cosign-public-key`
ExternalSecret). No other ExternalSecret unready. Hostinger itself is reachable and Ready.

Not actioned, needs the operator's go: re-registering hostinger (still no registration-only
entry point; `make refresh CLUSTER_PROVIDER=k3s-hostinger` is still the unsafe path and still
not approved), making registration survive a rebuild, and the fact that three consecutive
CronJob failures raised no alert — the detection gap matters more than the blank panel.

### 2026-09-23 — the detection gap root-caused: Alertmanager's root route is default-deny

The `cve-remediation-verify` silence is **not** a missing rule or a missing metric. Measured on
the live hub, every hop works except the last one:

`kube_job_failed{namespace="platform-ops"} 1` → `KubeJobFailed` rule present in
`kube-prometheus-stack-kubernetes-apps` → `ALERTS{...} alertstate="firing"` → active in
Alertmanager, `silencedBy: []`, `inhibitedBy: []` → **matches no child route → root receiver
`'null'` → discarded.**

`scripts/etc/prometheus/alertmanager.yaml.tmpl:9` sets `route.receiver: 'null'`. The only exits
are `severity = critical` (→ `sms-critical`) or the 5-name alertname allowlist in the
`AlertmanagerConfig` CR (→ `cicd/k3dm-analyze/*` webhook). `KubeJobFailed` ships as
`severity: warning` and is on neither, so **every kube-prometheus-stack default rule is
undeliverable**. Currently firing and being dropped: `KubeJobFailed` ×3 (platform-ops and
`identity/keycloak-realm-reconcile` — the awk-127 job already on the list),
`E2EVerificationFailing` ×2 (this repo's own e2e alert has never been deliverable),
`KubeHpaMaxedOut` ×2, `PrometheusDuplicateTimestamps` ×1, `Watchdog` ×1.

`alertmanager_config_secret.bats:26` asserts an alert routes **to** `null` and nothing asserts
any alert reaches a real receiver, so a template where every route ends at `'null'` passes.

Spec filed: `docs/bugs/2026-09-23-alertmanager-null-root-route-silently-drops-warning-alerts.md`
— a `platform-warning` receiver (email to `${ALERTMANAGER_GMAIL_FROM}`, already in both
`envsubst` allowlists at `observability.sh:78` and `:634`, so no new variable), a third child
route placed **after** `severity = critical` so criticals keep SMS, `docs/guides/alerting.md`
(none exists), and a test that an alert reaches a non-`null` receiver. Assigned to Codex.

Side findings, not actioned: `e2e_last_success_timestamp_seconds` has zero series, so
`E2EVerificationStale` can never fire yet; `Watchdog` routing to `'null'` makes it a
dead-man's switch that dies inside the cluster it watches; one 502 from
`webhook.3ai-talk.org/api/v1/cve-remediate` at 2026-09-22T00:49Z, not retried since.

## 2026-09-23 — Alertmanager delivery blackout: FIXED and confirmed live

Codex delivered both specs on `k3d-manager-v1.37.0`. Claude verified each independently.

- `03b875c5` — commit 1: `severity = warning` → `platform-warning` route appended **after** the
  `alertname =~` allowlist (order is load-bearing: Alertmanager takes the first match, so the
  allowlist keeps its faster timing), plus `_observability_assert_alertmanager_delivery` on **both**
  renderers. Guard returns 0 in every state except "CR names a configSecret and that Secret is
  absent", so a transient Vault outage cannot fail a rebuild with a working config.
  Verified: 8/8 pytest, BATS green, and the ordering assertion mutation-proved red.
- `02e3fa76` — commit 2: `_argocd_appset_live_overrides` now prefers the substrate-derived CNI dirs
  and keeps the live value only as a fallback, and refuses to write generic `/etc/cni/net.d` to a
  k3s target. This is why three correct CNI fixes were overwritten on every AppSet reapply.
  Verified: 13/13 BATS, shellcheck 2→2 (no new warnings), M1 mutation red on the asserted k3s dirs.
  `d2c6177f` also updated `argocd_appset_live_overrides.bats` — outside the target list, but a
  correct consequence of the `keeping live` → `resolved overrides` log change, not a weakened gate.
- `114e5c82` — Claude's fix to Codex's probe. The generated Secret's **only** key is
  `alertmanager.yaml.gz` (base64 **and** gzip). The probe read a plain `alertmanager.yaml`, so
  `b64decode("")` → `yaml.safe_load` → `None` → it reported a **total blackout against the healthy
  hub**, which has five working child routes. A missing key is now a hard error. The pytest suite
  could not catch this because it stubs `run`, so the probe never executes — 8 green cases proved
  the sensor's parsing, not the probe's. Also fixed the unparsed default of
  `root_receiver_is_null=false`, which made a blacked-out cluster read as healthier than a working
  one. The spec's S3a carried the same wrong key and was corrected.

Live re-render (`deploy_observability_acg ubuntu-hostinger --confirm`): `alertmanager-smtp-secret`
**created** on hostinger, and the new guard printed its success line on its first production run.
hostinger went from **0 child routes to 4**, now including `platform-warning` on `severity = warning`
in the correct post-allowlist position. The 4-vs-5 gap against the hub is **expected**: the hub's
extra route targets `cicd/k3dm-analyze/*`, AlertmanagerConfig CRs that are hub-only by design.
`KubeDaemonSetRolloutStuck` — the istio-cni alert discarded for 17 days — is active and now routes.
`smtp_smarthost = smtp.gmail.com:587` is set globally, so the blank per-receiver `smarthost` is fine.
Delivery confirmed after the route's `group_wait: 10m`: `notifications_total{integration="email"} 1`,
`notifications_failed_total{integration="email",*} 0` across all five reasons, and
`notification_latency_seconds_count{integration="email"} 1` — Alertmanager records that histogram only
on a completed send, which is what makes this more than an attempt count. The notify log is silent
because info level logs notification *errors*, not successes, so silence is consistent with success
rather than evidence of it; the inbox is the last authority.

## 2026-09-23 — v1.38.0 spec updated from the istio-cni incident

Tonight's work produced real evidence for three claims the v1.38.0 spec had been asserting, so the
spec now cites measurements instead of reasoning.

1. **A five-document near-duplicate cluster the dedup gate provably misses.** One root symptom
   (istio-cni CNI dirs wrong on a k3s substrate) is spread across five bug docs filed over 68 days
   with five disjoint slugs; `ls docs/bugs/*-<slug>.md` returns exactly one match each — itself. Not
   one pair collides. They are causally chained rather than strict duplicates, which is exactly the
   near-duplicate case lexical matching misses. Two share the token `cni`, so the honest WS5 question
   is not "does semantic beat nothing" but "does it beat grep" — the lexical control earns its place.
2. **The gate also fires falsely.** The dedup check for the provider-label slug surfaced
   `2026-06-08-thread-reply-triggers-unknown-command.md`, matched on the word `unknown`, about a
   Slack command parser. Recorded as a **hard negative** pair. Both directions fail today.
3. **WS5 must exercise the real component.** `test_alert_delivery.py` had 8 green cases while the
   probe it consumes was inverted — it read `alertmanager.yaml` from a Secret whose only key is
   `alertmanager.yaml.gz`, and reported a total blackout against a healthy 5-route cluster. The tests
   stubbed `run`, so the probe never executed; they measured the half of the seam that could not
   fail. WS5 now requires the real indexer and scorer over real files, one end-to-end subprocess case,
   mutation-proved recall floors, and stubbing only the network call against a *recorded* response.

Also added to WS4 as empirical support for additive-only: a component that is confidently wrong on
its first live run is the normal case. The probe cried wolf, which is loud; a retriever wired to
suppress filings fails silently and would not have been caught at all.

NOTE for planning: the two v1.38.0 memory-bank entries disagree on whether a vector DB is warranted.
The earlier one concluded no vector database at either phase (brute-force cosine over ~1,360 docs is
microseconds). The later, operator-directed restructure deploys pgvector as a platform component. The
later supersedes, but the earlier reasoning still holds — at this corpus size the store is justified
as platform practice, not by retrieval performance. Say that out loud in the release notes.

## 2026-09-24 — post-`refresh-registration` verification, CVE loop closed, payment root-caused

**`make refresh-registration CLUSTER_PROVIDER=k3s-hostinger` (operator-run) did both jobs.**
`k3d-manager/shopping-cart` flipped `false` -> `"true"` on `cluster-ubuntu-hostinger`, and the
Pushgateway LaunchAgent survived (pid 75822, `localhost:9091/-/healthy` 200) — `492b3cba` stopped
the `rm -f`. Proof the label was load-bearing: all six `ubuntu-hostinger-shopping-cart-*`
Applications were created at **13:03:31Z**, seconds after the flip, and four of the five services
rolled fresh pods. `payment` lives in its own namespace `shopping-cart-payment` (its manifests set
it explicitly, overriding the Application destination `shopping-cart-apps`) — it was never missing.

**CVE auto-patch loop now works end to end — first success in the cronjob's history.**
Manual trigger `app-cve-scan-manual-1790255689` **SUCCEEDED** (13:14:49 -> 13:18:48). It recorded
**four** `promotion_requested` remediation events (frontend, order, payment, product-catalog;
basket had no HIGH/CRITICAL). The CVE Remediation dashboard has data for the first time. Note the
CronJob's own `.status.lastSuccessfulTime` stays `None` — a manually created job is not owned by
the CronJob, so the scheduled 01:00 UTC run is still the one to watch.

**`api/payments.spec.ts` health failure root-caused** — appended to
`docs/bugs/2026-09-16-e2e-assertion-api-payments.md`. `application.yml:65` declares `rabbitmq:` at
the **top level** instead of under `spring:`, so `RabbitAutoConfiguration` never binds it and
defaults to `localhost:5672`. Measured: RabbitMQ reachable from the payment pod (`nc_exit=0`),
`localhost:5672` refused (`nc_exit=1`), and `RabbitHealthIndicator` logs `Connection refused` at the
exact second of each probe. The indicator is in neither the `liveness` nor `readiness` group, so
Kubernetes and ArgoCD both report green while `/actuator/health` returns 503 — the same
"signal disconnected, system fine" shape as the Pushgateway drift. Fix NOT applied: shopping-cart is
spec-then-Codex, and the top-level `rabbitmq.vault.*` subtree is read by the custom
`rabbitmq-client-java`, so this is a careful split, not a move. The other **eight** payments
failures remain unexplained — do not close on the health fix alone.

**Hermes gap identified.** No sensor probes an application's aggregate `/actuator/health`; `argocd`
and `node_pressure` both read green here by design. A sensor comparing aggregate health against
probe-group health would catch this whole class. Not specced yet.

**Open question for the operator:** there is no Makefile target to trigger `app-cve-scan`. The
`/k3dm <target>` allowlist framework SHIPPED (`scripts/lib/webhook/make_targets.py`, 17 targets), so
adding one would be a target plus one allowlist entry.

## 2026-09-24 (later) — both gaps specced and dispatched

The two open questions above are now answered in writing and handed to Codex.

**`3af7b09f` — two specs pushed** on `k3d-manager-v1.37.0`:

- `docs/plans/v1.37.0-app-cve-scan-make-target-and-k3dm.md` — `app_cve_scan_trigger` in
  `observability.sh`, a `make app-cve-scan` target (`CRONJOB=`, `K3DM_CVE_SCAN_WAIT=`), and the
  **18th** `/k3dm` allowlist entry at `min_role: operator`, `timeout: 900`, with `CRONJOB` as an
  anchored two-value alternation because the value reaches `create job --from=cronjob/<value>`.
  Deliberately **no** `confirm:` — a scan is additive. Records that the CronJob's
  `.status.lastSuccessfulTime` stays empty after a manual run and documents it rather than adding an
  `ownerReference`, which the history reaper would then delete.
- `docs/plans/v1.40.0-hermes-app-health-delta-sensor.md` — a Hermes `app_health` sensor for the
  general class, not a RabbitMQ check: **aggregate `/actuator/health` not UP while both probe groups
  are UP**, which is by construction the set of failures no orchestration signal can ever report.
  Reads through the API server's service proxy (`get --raw .../services/<svc>:<port>/proxy/...`) so
  it needs no port-forward — the mechanism that silently broke Pushgateway metrics for 64 days.
  Files bugs by extending `e2e_bugs.py`'s existing `run["source"]` dispatch with a third source,
  reusing its dedup/reopen/worktree/rebase-retry wholesale. **Disabled by default** via
  `K3DM_HERMES_APP_HEALTH_ENABLED`, mirroring `K3DM_HERMES_STATUS_ENABLED`.

Why v1.38.0 for the second one: v1.37.0 already held four plan docs and the cap is five. Splitting
was the rule, not a preference.

**Two traps recorded in the specs so they are not re-derived:**
- `group_slug` (`e2e_triage.py:106-109`) hardcodes an `e2e-` prefix, so the filed doc is
  `*-e2e-health-probe-gap-*.md`. Leave it: `file_bugs` dedups by globbing `*-{slug}.md`, so changing
  the prefix would orphan every open bug doc and file a duplicate of each.
- `record()` truncates `evidence` to 200 chars, so the full delta list must travel in `data`.

**Dispatched:** Codex is running the v1.37.0 CVE-scan task (`scratchpad/handoff-app-cve-scan-k3dm.md`,
session `01a0d39d`). The v1.38.0 sensor task is written but **held** — it targets a different branch
and the same working tree, so it goes after the first one lands and is verified.

### Task 1 landed — `fb6ceb88`; task 2 HELD by decision

`make app-cve-scan` + the 18th `/k3dm` allowlist entry are on `origin/k3d-manager-v1.37.0`.
Verified independently, not on Codex's report: local == origin, diff in scope (10 files, +201/-1,
no refactors), trailers parsed, and all six mutations red with `RESTORE_COMPARE_RC=0` each time.
Gates: focused BATS 6/6, `makefile_platform_ops` 2/2, focused pytest 14, whole pytest 189,
`check-doc-links` 1762 OK, `make -n app-cve-scan` parses, shellcheck 1 → 1 (pre-existing SC2016).

**The spec's guessed label selector was WRONG and the spec's own "verify it yourself" instruction
caught it.** The real selector is `k3dm.k3d.io/cve-remediation-event=true`
(`app-cve-scan.sh:427`), not the guessed `k3dm.k3.io/remediation=promotion_requested`. Note the
domain: `k3dm.k3.io` is used **only** by the Hermes status label; every other selector in the repo,
including this one, is `k3dm.k3d.io`. Never guess a selector — read it from the producer.

Codex could not commit (`.git/index.lock: Operation not permitted` — the known `codex exec`
sandbox wall), so it staged everything and Claude committed. Expected, not a failure.

`make test` reported four `e2e_remote.bats` reds (688, 699, 723, 724). Those were the
**unpushed-HEAD** artifact: `15e73d6b` was local-only at the time. Re-ran the suite after pushing —
**80/80 green, zero reds.** Not a regression.

**Decision (operator, 2026-09-24): task 2 is HELD until v1.37.0 merges.** The Hermes `app_health`
sensor spec (`docs/plans/v1.40.0-hermes-app-health-delta-sensor.md`) and its handoff
(`scratchpad/handoff-hermes-app-health-sensor.md`) are complete and ready. It targets
`k3d-manager-v1.38.0`, which `/post-merge` step 5 cuts from the v1.37.0 merge SHA. Do not cut that
branch early and do not move the work onto v1.37.0 — that would make v1.37.0 a 6-plan-doc release,
the exact condition the max-5 cap exists to prevent.

**Next operator action for the CVE target:** `make app-cve-scan` has never been run — it was
deliberately excluded from the gates because it mutates the live hub. Its first live run is the
operator's.

### Webhook Phase 1 landed — `b6c8a141`; stale status test fixed — `dd8422e7`

Both on `origin/k3d-manager-v1.37.0`, local == origin verified.

**Phase 1 is real but its acceptance criterion is NOT met.** Eleven authz functions moved to
`scripts/lib/webhook/policy.py`, entrypoint 4010 -> 3929, `_POST_ROUTES`/`_GET_ROUTES` added, no
moved name still defined in the entrypoint and no re-export shim (verified by grep, not by report).
Behaviour-neutral and proven so: the 10 static + 3 dynamic `(path, min_role)` pairs are pinned as
literals in `scripts/tests/bin/webhook_policy.py`. All four mutations went red as intended.

BUT the tables' `min_role` is **declarative only** — enforcement still runs through
`_action_policy`, so the table is not the check. The spec's criterion ("no route may reach a
job-spawning call without passing through the table's min_role check") is unmet, and two entries are
misleading: `/api/v1/cluster` declares `reader` while up/down need admin and kill needs operator,
and `/api/v1/make` declares `reader` while its floor comes from `MAKE_TARGETS`. No regression — the
dynamic resolution still governs. **Follow-up:** enforce the table min_role as an ADDITIONAL floor
(behaviour-neutral today, since every table floor is <= its dynamic requirement) and correct those
two entries. Not yet specced.

The fail-open `if action_policy:` branch is preserved deliberately; a None policy still skips both
the role check and the audit write. Nothing reaches privileged work through it today only because
`/api/v1/cluster`'s handler re-validates. Separate decision, not yet taken.

**`dd8422e7` fixes a red I let through.** `492b3cba` correctly changed
`bin/cluster-status-summary`'s `optional={"pushgateway"}` to `optional=set()`, so a dead Pushgateway
now counts as a failure — but it never updated `cluster_status_summary.bats`, whose fixture has TWO
failing services against a hard-coded `services_failed == 1`. That suite had been red on the release
branch since 05:08. Its "make test green" gate did not hold and I accepted the report without
reading the summary line. Now asserts the failed-service SET by name and derives the count.
Mutation-proven red, restored clean.

**Full gate re-run 2026-09-24 08:4x:** `make test-all` -> `EXIT=2`, but **1237 BATS ok / 0 not ok**
and all four unittest files OK (14/2/6/6); the only failure is `make: *** [test-pytest] Error 2`
because that recipe's `python3` is Homebrew 3.14.7 with no pytest. Bare `pytest` -> **189 passed**.
`make test-all` can never exit 0 on this box — read the per-suite counts, never the exit code.

**Webhook restarted** onto the refactored code: PID 43834 (was 37998), listening on 127.0.0.1:7443.
Unauthenticated `/api/v1/health` and an unknown POST route both return 401 — auth is checked before
routing, so no 404 route enumeration for unauthenticated callers. `/k3dm` remains live.

### Phase 1b verified clean — `57ac113d`

Independently verified, not taken from the agent's report.

**Gates, measured on a run that COMPLETED:** `make test-all` -> `EXIT=2` (the expected
`test-pytest` interpreter failure; `python3` is Homebrew 3.14.7 with no pytest), **1237 BATS ok / 0
not ok** — identical to the pre-Phase-1b baseline, so zero regressions. Unittest suites
`webhook_make_targets` 14, `webhook_policy` **7** (was 2), `webhook_redaction` 6,
`webhook_request_hardening` 6, all OK. Bare `pytest` 189 passed. `webhook.bats` 64/64.

**Two measurement traps hit on the way, both worth remembering:**

1. The first run showed `1101 ok / 4 not ok`. All four reds were `e2e_remote.bats` and were the
   documented **unpushed-HEAD** artifact — the v1.39.0 spec commit `5468f38c` was local-only. After
   pushing, that suite is **80/80 green**. See [[reference_e2e_remote_reds_mean_unpushed_head]].
2. `1101 ok` is NOT comparable to the 1237 baseline, because `make test` aborted on the BATS failure
   and never reached `test-bin`/`test-python`. **A truncated run's case count looks like a smaller
   suite, not a stopped one.** Only compare counts from a run that completed — otherwise the obvious
   reading is that ~136 tests were deleted.

**Codex's two caveats both checked out.** `bin/k3dm-webhook:3037` has `-> str | None`, so the file
needs Python **3.10+**; it fails under `/usr/bin/python3` 3.9.6 and imports fine under Homebrew
3.14.7, which is what the LaunchAgent runs. Pre-existing, untouched by the diff, in Phase 3
territory (`_sanitize_question`). Its `make test-all` genuinely died on sandbox `/var/folders`
mktemp permissions, so that gate was unmet and I ran it myself.

Codex again could not commit (`.git/index.lock: Operation not permitted`) and correctly left
everything staged rather than retrying or removing the lock — the handoff now tells it to do exactly
that, and that instruction worked.

**Open, not acted on:** three stray untracked files in the repo root — `.join-failures.38822`,
`.join-failures.55968` (both containing `ubuntu-2`) and an empty `.pub`. Some suite writes to a
RELATIVE path instead of a temp dir, leaking per-PID debris into the working tree. Cosmetic today,
but one `git add -A` from being committed. Not traced yet.

**v1.39.0 spec added — `5468f38c`:** `docs/plans/v1.39.0-test-suite-metrics-and-staleness.md`.
Publishes `make test`/`make test-all` results to the app-cluster Pushgateway and Grafana. Built
around four measured traps: the exit code is a lying metric here so `k3dm_test_cases_failed` is the
health signal; Pushgateway retains the last value forever so the staleness rules are IN SCOPE (there
is currently no staleness rule for any `k3dm_*` metric — the pre-existing `k3dm_deployment_*` gap is
folded in); a failed push is indistinguishable from no run; and `origin` must be in the Pushgateway
grouping URL, not only a label, or CI silently overwrites a local red. `make test`/`make test-all`
recipes stay unchanged — publishing is an opt-in `make test-metrics`.

Plan-doc counts: v1.36.0 **5**, v1.37.0 **5** (both at the cap), v1.38.0 **2**, v1.39.0 **2**.
# 2026-09-24 — webhook Phase 4 lifecycle/status extraction (commit pending)

Implemented the final scoped Phase 4 split on `k3d-manager-v1.37.0`: seven orchestration
functions now live in `scripts/lib/webhook/lifecycle.py`, and four reporting/formatting
functions live in `scripts/lib/webhook/status.py`. Both modules use explicit `__all__` and
runtime injection for entrypoint-owned logging, notifications, metrics, analysis, redaction,
and provider/job hooks. `/k3dm` passes validated argv directly to `make` with its timeout and
repo working directory; no shell command string is constructed. Existing `agent.py`'s
duplicate `_notify_job` was deliberately left alone.

Verification: focused lifecycle/status pytest 10 passed; bare pytest 189 passed; webhook BATS
64/64; webhook_hub_eso BATS 4/4; `make test-all` completed BATS plans `1..1112` and `1..132`,
unittest suites `7 / 6 / 14 / 13 / 6 / 6 / 4`, then exited 2 at the expected missing pytest
dependency under Homebrew Python 3.14.7. Mutation guards M1–M6 each went red and were restored.
Doc links 1765 files OK, repo-root passed, server import printed `OK`, and `_agent_audit` passed.
Entrypoint measured 2957 -> 2226 lines. Commit was attempted with the requested message but
was blocked by `.git/index.lock: Operation not permitted`; no retry, lock removal, hook bypass,
force-push, or PR was attempted. All scoped changes remain staged; no Phase 4 commit SHA exists.

# 2026-09-24 — lib-foundation v0.4.18 credential-test observability LANDED (1bcde41)

Codex implemented the spec correctly but could not deliver it: `.git/index.lock: Operation not
permitted`, its known sandbox limit. Claude verified the working tree independently and made the
commit. `feat/v0.4.18-credential-test-observability` at **1bcde41**, local == origin.

Scope as shipped (four files, exactly the spec's list): each `ACG_SESSION_OK` now carries
`path=existing-session|auto-login|manual-login`; `_reportCredentialState` always writes
`ACG_CREDENTIALS: username=<absent|empty|present> password=<...>` to stderr with no value or
length; `K3DM_ACG_REQUIRE_CREDENTIALS=1` fails closed under its own `ACG_CREDENTIALS_REQUIRED`
marker. Default behavior unchanged when unset.

Gates re-measured by Claude, not taken from the report: jest **7 suites / 32 tests** (baseline
28), disappearance gate `ACG_SESSION_OK\n'` **4 -> 0**, `node --check` clean on both JS files,
`make bats` **138/138 exit 0, no skips**. Codex reported bats case 16 red ("acg credential test
does not restart when aws CLI is missing"); it does NOT reproduce here — that test skips based on
whether `aws` sits in `/usr/bin:/bin`, which differs inside its sandbox. Standalone `acg.bats`
13/13.

No Makefile change was needed: `scripts/lib/acg/cdp.sh:184-190` loads the credentials through the
real `_secret_load_data k3dm-acg-pluralsight username|password` and execs node without `env -i`,
so an exported `K3DM_ACG_REQUIRE_CREDENTIALS` reaches the script. The report is therefore a true
read-back of the two Keychain accounts fixed in `53e96ba7`.

Pending: operator runs the live `credential-test` gate (theirs alone — needs a TTY and the CDP
browser; close the stray Pluralsight "Sign In" tab first), then PR + merge + tag v0.4.18 on the
user's go, then a subtree pull into k3d-manager. Only after that can the Tier 2 preflight in
`scripts/plugins/e2e.sh` swap its Keychain-existence check for the real loader.

# 2026-09-24 — the v0.4.18 instrumentation paid off on its first live run: headless auto-login has NEVER worked

The operator ran `make credential-test` twice (with and without `K3DM_ACG_REQUIRE_CREDENTIALS=1`).
Both runs behaved identically, which also confirms the new gate does not false-positive when
credentials are present. Output, in order: `ACG_CREDENTIALS: username=present password=present`
(the `53e96ba7` Keychain fix is confirmed through the real loader), then the session was NOT
authenticated, so execution reached `path=auto-login` — the branch we had assumed was unreachable
on demand — and then `auto-login error: locator.click: Timeout 30000ms exceeded` on
`input[type="password"]`, `waiting for element to be visible, enabled and stable`.

**Under the old code this printed a bare `ACG_SESSION_EXPIRED` and the only reasonable reading was
"session expired, sign in again." The truth is headless auto-login has never succeeded.** That is
exactly the class of false-green the observability work was built to break.

Bug filed upstream (cap-exempt, dedup cleared — no colliding slug among the 19 existing files):
`lib-foundation/docs/bugs/2026-09-24-acg-pluralsight-login-click-preconditions.md` at **b48ad1c4**,
local == origin. Four defects in `playwright/lib/pluralsight_login.js`: (D1) `fillIfVisible` clicks
a text input before filling it, adding the *stable* + in-viewport preconditions that `fill()` does
not require — that click is the statement that timed out; (D2) `isVisible({timeout})` never waits,
so the 5000 is inert and a still-rendering field is silently "absent"; (D3) both call sites discard
the return value, so the form submits blind and surfaces only a generic `login_failed`; (D4) the
submit click ignores the `_robustClick` dispatch precedent — this is the ONE file in the subsystem
that never received it, after the same defect recurred 3x from narrow per-file fixes.

**Honest limit recorded in the doc: the root cause is NOT reproduced.** A read-only CDP probe found
the field visible, enabled, editable, stable (identical bounding boxes), `pointer-events: auto`,
`animation: none`, `elementFromPoint` returning the input itself — which DISPROVES the "the form
animates so it is never stable" hypothesis. The fix is precondition reduction plus documented
precedent, not a confirmed root cause. Claude cannot verify it: doing so means driving a real login
with the operator's credentials. **Only the operator's `credential-test` re-run is the gate.**

Dispatched to `codex exec` (background, workspace-write + network, launched with `-C` from
lib-foundation, `NPM_CONFIG_CACHE` pre-set for the known `~/.npm` denial). Clean startup confirmed.
Scope: 3 files only (`pluralsight_login.js`, its existing jest suite, `CHANGE.md`). The handoff
makes the mutation check mandatory — each new test must be shown RED against pre-fix source — and
forbids PR/merge/main/force-push/`--no-verify`/`git add -A`. Unifying the two existing
`_robustClick` copies is explicitly OUT of scope: `sandbox.js` swallows errors with
`.catch(() => {})` and `acg_restart.js` does not, so collapsing them would silently change the live
sandbox-provisioning path that cannot be tested without a live sandbox.

Verify on return per the standing rule: SHA on origin, `--stat` scope, jest count risen above 32,
both mutation-check runs, bats 138.

# 2026-09-24 — login fix landed (8a74258); the mutation gate is what made it trustworthy

Codex wrote the change correctly but hit `.git/index.lock: Operation not permitted` again — its
known sandbox limit, now seen twice on this branch. It stopped and reported instead of working
around the lock, which is the required behavior, but that left **three gates unrun**: the mutation
check, `npm run check`, and `make bats`. Claude reviewed the diff and ran all three.

Landed: **`8a74258`** (fix, 3 files: `pluralsight_login.js`, its jest suite, `CHANGE.md`) and
**`a33727c0`** (bug-doc verification table). Local == origin. Source diff matches the spec's F1-F4
exactly; no scope creep, no files outside the three.

Gates measured by Claude, not taken from the report: `node --check` clean x2; jest **7 suites / 36
tests** (up from 32); `npm run check` clean; `make bats` **138 ok, 0 not ok, 0 skips**. The
"missing aws CLI" case did NOT go red here, consistent with the earlier finding that its skip
depends on `aws` being in `/usr/bin:/bin`.

**The mutation check is the gate that mattered and it passed exactly:** swapping the pre-fix source
back in (by FILE COPY — `git stash` is what failed for Codex, from the module dir with a
repo-relative path) produced **4 failed / 32 passed**. Precisely the four new tests go red and all
32 pre-existing ones stay green, so each new test is a real guard and none of the baseline was
disturbed. Given that this bug's whole shape was "a guard that looks present but isn't", tests that
passed either way would have repeated the defect rather than fixed it.

Still NOT confirmed: the fix itself. Jest green means the code matches the spec, not that
auto-login works. Root cause was never reproduced (the CDP probe disproved the "never stable"
hypothesis), so this is precondition reduction plus documented precedent. **Only the operator's
`credential-test` re-run can confirm it** — it needs a TTY and their credentials, so no agent and
not Claude can run it. Recorded in the bug doc as plausible, not confirmed.

Open decision for the user: this fix now sits on the same branch as the approved "Reporting +
require-credentials gate" scope, so the v0.4.18 PR is wider than what was signed off. Claude's
recommendation is one PR (same subsystem, nothing merged yet); the alternative is splitting the
login fix onto its own `fix/` branch before the PR. Awaiting the user's call — no PR created.

Minor residue, deliberately not churned on a verified tree: `_robustClick` is exported but no test
imports it directly. Folded into the `_robustClick` dedup follow-up.

# 2026-09-24 — D5: the REAL root cause, reproduced. EMAIL_SELECTOR never matched (7801ff4)

The operator re-ran `credential-test` after the D1-D4 fix. **The 30s click hang is gone**, and the
new D3 diagnostic immediately earned its keep:

    ACG_CREDENTIALS: username=present password=present
    ACG_LOGIN_FIELDS_MISSING: email=missing password=filled

Password filled, email never matched. A read-only CDP probe of the live signin form:
email field is **`type="text" name="Username" id="Username"`** — PascalCase, an ASP.NET identity
form. Every arm of `input[type="email"], input[name="username"], input[name="email"]` misses:
wrong type; no `email` field; and `[name="username"]` fails because **CSS attribute VALUES are
case-sensitive even though attribute NAMES are not.** That is the trap.

Measured through **Playwright's own** selector engine (checked separately from native
`querySelectorAll`, since Playwright implements its own CSS parser) on the live page:
**OLD count=0, NEW count=1 firstVisible=true.** `count=0` against a fully rendered visible form is
the bug reproduced end to end. Unlike D1-D4 this is a genuine root cause, not precondition
reduction.

Also probed because it would have flipped the verdict: **`ShowCaptcha` is `"False"` with zero
reCAPTCHA iframes** — no captcha armed, so unattended login is actually feasible.

**Key lesson for the record: fixing D1-D4 did not fix login — it REVEALED what was broken.** D2's
non-waiting `isVisible()` returned false for the unmatched email locator and D3 discarded it, so
the form submitted with only a password and died as a generic `login_failed`. The selector bug sat
behind the precondition bugs. The observability work has now converted two successive false
diagnoses ("session expired", then "login failed") into the actual defect.

Fix `7801ff4`, local == origin: EMAIL_SELECTOR gains the ` i` flag on every name/id arm plus an
`[id="username" i]` arm. Gates measured by Claude: jest **39** (from 36); mutation check **3 failed
/ 36 passed** against the old selector; `npm run check` clean; `make bats` **138 ok / 0 not ok / 0
skips**; live probe 0 -> 1.

Honest coverage limit, recorded in the bug doc: jest here has **no DOM** (offline suite, no
`jest-environment-jsdom`), so the 3 new tests assert the selector's SHAPE as disappearance gates,
not CSS matching. Installing jsdom for one test is disproportionate for an offline suite. The
behavioral proof is the live probe, which cannot run in CI because it needs the operator's CDP
browser.

Branch now carries three commits beyond the approved v0.4.18 scope (8a74258, a33727c0, 7801ff4).
The scope decision is still open and still the user's: one PR (Claude's recommendation) vs. split
the login fix onto its own `fix/` branch. No PR created.

NEXT: operator re-runs `make credential-test` a third time. Expect `ACG_SESSION_OK path=auto-login`.
If it fails again the diagnostic will name the new stage — that is now the working pattern.

# 2026-09-24 — CONFIRMED: headless auto-login works for the first time ever (38c64ade)

The operator's third `credential-test` run closed the loop:

    ACG_CREDENTIALS: username=present password=present
    INFO: Session not authenticated — attempting headless Pluralsight login...
    ACG_SESSION_OK path=auto-login
    ... Open Sandbox -> Start Sandbox -> Found 4 copyable inputs
    INFO: AWS credentials written to ~/.aws/credentials [default]
    INFO: AWS credentials validated (sts:GetCallerIdentity OK)

**`path=auto-login` from a signed-out start is the first successful headless Pluralsight login in
this subsystem's history**, and the full chain behind it completed: sandbox start, credential
extraction, live STS validation. All five defects fixed and **CONFIRMED, not merely plausible**.

The `path=` suffix is what makes this legible — a bare `ACG_SESSION_OK` would be
indistinguishable from `path=existing-session`, which never touches the credential store. The
v0.4.18 observability work paid for itself three times over in one day: it exposed the failure,
then named the stage, then proved the fix.

Bug doc `docs/bugs/2026-09-24-acg-pluralsight-login-click-preconditions.md` marked
RESOLVED & OPERATOR-CONFIRMED; both verification tables flipped to confirmed. Commit **38c64ade**,
local == origin.

**Three successive wrong diagnoses, each only reachable after the previous layer was removed
— the reusable lesson:**
| Symptom | Natural reading | Actual state |
| `ACG_SESSION_EXPIRED` | session expired, sign in again | auto-login had NEVER worked |
| `locator.click` 30s timeout | form animates, never stable | DISPROVEN by probe; click was unnecessary |
| generic `login_failed` | wrong password | email field never matched at all |

D1-D4 did not repair login; they exposed D5. The fix that mattered was naming the failing stage.
Rule: when a symptom is generic, instrument the stages before theorizing about any one of them; a
`count=0` locator on a rendered visible form is a wrong selector, never a slow page. Saved as
memory `reference_css_attribute_values_are_case_sensitive.md`.

Branch `feat/v0.4.18-credential-test-observability` state: `1bcde41` (observability), `b48ad1c4`
(bug doc), `8a74258` (D1-D4), `a33727c0` (gate table), `7801ff4` (D5 selector), `38c64ade`
(confirmation). Local == origin. **The live credential-test gate required before a lib-foundation
PR has now PASSED.**

STILL PENDING, user's call only: (1) the scope decision — one PR covering observability + login fix
(Claude's recommendation) vs. splitting the login fix onto its own `fix/` branch; (2) the PR itself
plus merge + tag v0.4.18; then (3) subtree pull into k3d-manager and rewire the Tier 2 preflight in
`scripts/plugins/e2e.sh` from Keychain-existence to the real loader. No PR created.

## 2026-09-25 — v1.37.0 merged

PR #131 (`k3d-manager-v1.37.0` → `main`) merged at **925c43e7675651b9de007346612f2941d47c605a** on 2026-09-25 18:14:11Z. 

**Branch protection:** `enforce_admins` restored to `true` immediately post-merge.

**Next branch created:** `k3d-manager-v1.38.0` at the merge commit; retrospective written and committed at **7e5333b0** (verified on origin).

**Retrospective contents:** v1.37.0 delivered the webhook monolith split (five modules: policy, smoke, agent, lifecycle, status) with authorization hardened (unknown actor → reader, POST enforces floors + policy, every request audited once). Copilot caught two gate defects in this release's own tests (disappearance guard via `rg` was vacuously green; Alertmanager tests had hard PyYAML dependency) — both fixed. Four CodeQL alerts (23/24/26/27, spawn injection) dismissed as false positives with reasoning; alert 25 resolved by renaming `config_secret` → `config_ref`. Live smoke gate reported two failures on healthy cluster — both traced to stale gate defaults, not v1.37.0 regressions. Four findings filed as specs and deferred to v1.38.0.

**Git tag and GitHub release:** **still MISSING** and awaiting the owner's explicit approval. CHANGELOG heading, `docs/releases.md` row and README row already exist on `main`; the downstream step (tag + release) is a hard gate requiring the user's go, not something an agent owns. No tag or release was created.

**v1.38.0 plan-doc count:** starts at 3 (max 5): `v1.40.0-hermes-app-health-delta-sensor.md`, `v1.39.0-vector-store-platform-and-retrieval.md`, and `v1.39.0-slack-smoke-target.md`. Two slots remain.


### Standing-doc audit closed (commit `4ef90a3a`)

`docs/api/functions.md` was current. The other two were not:

- `memory-bank/projectbrief.md` counted the two E2E tiers as one plugin and omitted `hello.sh`,
  leaving its inventory two files short of `scripts/plugins/`. Jenkins now carries the deprecated
  marker CLAUDE.md already applies.
- `.github/copilot-instructions.md` had **no entry for `scripts/lib/webhook/`** — the module set
  v1.37.0 shipped. Copilot reviews against that file, so the modules holding the authorization
  logic were the least-covered code in the repo. Added the three authorization invariants (unknown
  actor role normalizes to `reader`; `min_role` is a strict floor and the effective requirement is
  the stricter of floor and policy; audit exactly once) plus the literal-`cmd[0]` /
  anchored-`fullmatch` invariant the four dismissed CodeQL `posix_spawn` alerts rest on — loosening
  it turns those dismissals into real findings. Eleven plugins had no bullet and are now listed
  with their public functions.

Note `scripts/lib/webhook/` is **eleven** files / 2,662 lines, not the five the retro names; the
five are the extracted feature modules, the rest are `config`/`make_targets`/`proc`/`render`/`auth`.

### Webhook restarted onto post-decomposition code

`make restart-webhook` run by the operator at 11:32 PDT. PID 86204 listening on 127.0.0.1:7443;
the prior instance exited on SIGTERM, which is what `launchctl kickstart -k` does. The agent runs
`bin/k3dm-webhook` straight out of this working tree, so the restart also picked up the
`k3d-manager-v1.38.0` checkout.

**No regression testing was run against the merge** — `make test` was not executed in this session,
so treat the post-merge tree as untested rather than verified.
# 2026-09-26 — vectordb Vault credential seed authored

Implemented the WS1 addendum in the allowed files: `_argocd_seed_vectordb_postgres` generates
the credential inside the Vault pod, skips an existing KV entry, and is called before the
AppProject deployment. Added six source-level BATS gates and the scoped vector-store guide.
Focused BATS is 16/16. Mutation proof produced red gates 11, 12, 13, 14, 15, and 16 and all
mutations were restored. Shellcheck remains at the existing single SC2317 informational warning.
Implementation commit `10dcd995` is pushed to `origin/k3d-manager-v1.39.0`; no PR was created.
