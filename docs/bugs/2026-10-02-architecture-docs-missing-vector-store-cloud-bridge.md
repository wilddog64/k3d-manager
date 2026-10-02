# Docs gap: no architecture page or diagram for the vector store or the cloud bridge

**Status:** FIXED (this commit)
**Branch:** `k3d-manager-v1.40.0`
**Type:** documentation defect (filed under `docs/bugs/` — v1.40.0 is at the 5-plan cap, and this
is missing release-DoD documentation for v1.38.0 and v1.39.0, not new scope)

## Gap

The cloud bridge (v1.38.0) and the pgvector store (v1.39.0) each appear only as a single node
in the README overview diagram. Their how-to and guide pages
(`docs/howto/cloud-session-requests.md`, `docs/guides/vector-store.md`) contain no diagram, and
`docs/architecture/` has no page for either. The bridge's trust boundary — the core of its
security argument — is described only in prose.

## Deliverables

Create two new files, following the style of `docs/architecture/cloudflare-slack-relay.md`
(heading layout, Mermaid fences, short prose between diagrams):

### A — `docs/architecture/cloud-bridge.md`

Sections, in order:
1. **Purpose** — 3–5 sentences: why a pull model (a cloud agent has GitHub access only; nothing
   inbound reaches the laptop).
2. **Components** — `flowchart` Mermaid: cloud agent → `cloud-requests` branch on GitHub;
   `bin/k3dm-cloud-bridge` (launchd `com.k3d-manager.cloud-bridge`) polling via its bare clone;
   allowlist validation (`scripts/lib/webhook/cloud_actions.py`, `policy.py`); webhook `:7443`
   over loopback with the **reader** token from Keychain `k3dm-webhook-token-reader`; response
   (and artifacts, if `docs/plans/v1.40.0-cloud-request-artifacts.md` is implemented in code —
   check the source, do not describe unimplemented behaviour) written back to the branch.
3. **One request, end to end** — `sequenceDiagram` from request commit to response commit,
   including the reject path for a non-allowlisted action.
4. **Trust boundaries** — a table: boundary | what crosses it | what enforces it | source file.
   Must cover: untrusted branch content, the allowlist, credential-bound role (a header can only
   narrow it), loopback-only webhook, what the agent can never do.
5. **Operations** — `make init-cloud-requests`, `make install-cloud-bridge`,
   `make restart-cloud-bridge`, `make uninstall-cloud-bridge`, where logs go; link to
   `docs/howto/cloud-session-requests.md` for the action table (do not duplicate it).

### B — `docs/architecture/vector-store.md`

Sections, in order:
1. **Purpose** — similarity search over `docs/bugs`, `docs/issues`, `docs/plans`, `docs/retro`
   for dedup; advisory everywhere; the store is a rebuildable cache.
2. **Components** — `flowchart`: the doc trees → `scripts/index-docs.py` (`make index-docs`) →
   Gemini embeddings API → pgvector StatefulSet in namespace `vectordb`
   (`scripts/etc/argocd/vectordb/*`, AppSet `scripts/etc/argocd/applicationsets/vectordb.yaml`);
   query side: `scripts/find-similar-docs.py` (`make find-similar-docs`), Hermes
   `scripts/lib/hermes/prior_art.py`, Slack / cloud bridge entry points (check
   `scripts/lib/webhook/make_targets.py` and `cloud_actions.py` for which are actually wired);
   observability: `bin/k3dm-vectordb-metrics`, `bin/k3dm-vectordb-status`,
   `scripts/etc/prometheus/rules/vectordb.yaml`, `grafana-dashboard-vectordb.yaml`.
3. **Index run** — `sequenceDiagram`: hash of the embedded text → skip unchanged → embed →
   per-batch commit → final prune transaction; include the 429 / quota branch.
4. **Credential resolution** — a small flowchart of the embeddings-key preference order (env →
   Keychain → hub Vault via ESO, as the code actually orders it — read the source).
5. **Failure modes** — table: symptom | meaning | where documented (link sections of
   `docs/guides/vector-store.md`; do not copy them).

### C — links

- `README.md`, `### Architecture` list: add two bullets after the Trivy Operator Observability
  bullet, matching the existing bullet format:
  - `- **[Cloud Bridge](docs/architecture/cloud-bridge.md)** — Pull-model bridge that lets a cloud agent read cluster state: components, request sequence, and trust boundaries`
  - `- **[Vector Store](docs/architecture/vector-store.md)** — pgvector prior-art index: components, index-run sequence, credential resolution, failure modes`
- `docs/howto/cloud-session-requests.md`: one line near the top —
  `Architecture and trust boundaries: [docs/architecture/cloud-bridge.md](../architecture/cloud-bridge.md).`
- `docs/guides/vector-store.md`: one line near the top —
  `Architecture diagrams: [docs/architecture/vector-store.md](../architecture/vector-store.md).`

## Accuracy rules (the reason this is a spec, not a free-write)

- **Every component, file, make target, Keychain item, namespace and port named in the pages
  must exist in the tree.** Read the source files listed above before drawing anything.
- **Describe only behaviour present in code.** If a v1.40.0 plan is not implemented yet, either
  omit it or mark it `(planned, v1.40.0)` — never present it as live.
- No secret values, no token prefixes beyond item names.
- Mermaid must render on GitHub: no `<br>` inside `sequenceDiagram` participant aliases, quote
  labels containing `:` `(` `/`.

## Verification (paste output)

- `make check-doc-links` — passes.
- For each name in the pages that looks like a path: `git ls-files <path>` non-empty (paste a
  loop over them). For each make target: `grep -n '^<target>:' Makefile`.
- Mermaid syntax: if `npx -y @mermaid-js/mermaid-cli` is unavailable offline, say so; do not
  claim it rendered.

## Definition of Done

- [ ] Files A and B created; the three link edits in C applied
- [ ] Verification output pasted
- [ ] Status line set to `FIXED (<short sha>)`
- [ ] Commit message: `docs(architecture): cloud bridge and vector store pages with diagrams`
- [ ] Pushed to `origin/k3d-manager-v1.40.0`; report `git rev-parse origin/k3d-manager-v1.40.0`

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files other than: the two new pages, `README.md`,
  `docs/howto/cloud-session-requests.md`, `docs/guides/vector-store.md`, this doc
- Do NOT edit the README overview diagram
- Do NOT commit to `main`
