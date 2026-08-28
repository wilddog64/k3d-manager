# Stage C cosign signing fails on every post-merge main build

**Filed:** 2026-08-28
**Milestone:** v1.27.0 image-signing / CVE-loop closure (Stage C follow-up)
**Status:** OPEN — blocks Stage D (Kyverno Audit→Enforce would reject unsigned images)
**Severity:** high — all shopping-cart images are pushed to GHCR **unsigned**

## Summary

All 6 Stage C PRs merged (infra #94, frontend #99, basket #39, order #72,
product-catalog #51, payment #63), but the cosign **sign** step fails on the
post-merge `push`-to-`main` build of **every image-building caller**. Images are
built, scanned, and pushed — then signing fails, so nothing is signed.

Verified 2026-08-28 via `gh run view --log-failed`:

| Repo | Build workflow | Sign result | Error |
|------|----------------|-------------|-------|
| shopping-cart-basket | Go CI → `Publish / build-push` | ❌ | `getting signer: reading key: invalid pem block` |
| shopping-cart-order | `build-push` | ❌ | `invalid pem block` |
| shopping-cart-product-catalog | `Build, Scan & Push / build-push` | ❌ | `invalid pem block` (digest `sha256:53e6…`) |
| shopping-cart-payment | `build-push` | ❌ | `invalid pem block` |
| shopping-cart-frontend | `publish` (direct wf) | ❌ | `cosign: command not found` (exit 127) |
| shopping-cart-infra | manifests only | n/a | infra builds no app image (Kustomize/YAML/Kubeconform only) |

## Root cause 1 — malformed `COSIGN_KEY` secret (basket, order, product-catalog, payment; also affects frontend once RC2 is fixed)

The reusable workflow installs cosign fine (`cosign-installer@v3.7.0`) and reaches
`cosign sign --yes --key env://COSIGN_KEY`, which fails with **`invalid pem block`** —
cosign cannot parse the secret value as a PEM.

The cosign private key itself is **valid**. Verified 2026-08-28: the Keychain backup
(`security find-generic-password -s k3d-manager-signing -a k3dm-cosign-key -w`) decodes
(via `xxd -r -p`) to a clean 11-line PEM:
`-----BEGIN ENCRYPTED SIGSTORE PRIVATE KEY-----` … `-----END ENCRYPTED SIGSTORE PRIVATE KEY-----`.

The corruption happened at **CI-secret seeding time**: macOS `security … -w` emits the
value as a **hexadecimal string** whenever the stored data contains newlines (which a
multi-line PEM always does). If the Stage-C secret seeding piped `security -w`'s output
straight into `gh secret set COSIGN_KEY`, the GH secret holds the **hex encoding of the
PEM**, not the PEM — so cosign sees hex gibberish → `invalid pem block`. Same failure-mode
family as [[reference_gh_contents_put_trailing_newline]] (byte-fidelity lost in transit).

### Fix (RC1)
Re-seed `COSIGN_KEY` in every image-building caller from the **true PEM bytes**, using a
**file** end-to-end (never `--body "$(security -w …)"`), and never exposing the key in argv:

```bash
# recover true PEM bytes to a 0600 temp file
umask 077; f=$(mktemp)
security find-generic-password -s k3d-manager-signing -a k3dm-cosign-key -w \
  | xxd -r -p > "$f"                        # decode the hex → real PEM
head -1 "$f"                                 # sanity: -----BEGIN ENCRYPTED SIGSTORE PRIVATE KEY-----
for r in shopping-cart-frontend shopping-cart-basket shopping-cart-order \
         shopping-cart-product-catalog shopping-cart-payment; do
  gh secret set COSIGN_KEY --repo "wilddog64/$r" < "$f"    # file → exact bytes
done
rm -f "$f"
```

Canonical source alternative: pull `cosign.key` from Vault `secret/cosign/signing` (raw PEM
string) instead of the Keychain hex. Verify `COSIGN_PASSWORD` too (single-line base64 — but
re-seed it from Keychain `k3dm-cosign-password` if in doubt; `security -w` returns it verbatim
because it has no newline).

> **`security -w` hex trap:** whenever the item value contains a newline, `security
> find-generic-password -w` prints hex, not the raw bytes. Decode with `xxd -r -p`, or store/
> read the material through Vault, before handing it to any consumer that expects raw PEM.

## Root cause 2 — frontend `publish` job missing job-level `env.COSIGN_KEY` (frontend only)

frontend uses a **direct** workflow (`.github/workflows/ci.yml`), not the infra reusable one.
Observed: `Install cosign` **skipped**, `Sign image by digest` **ran** then failed
`cosign: command not found`.

Cause: the job-level `env: COSIGN_KEY: ${{ secrets.COSIGN_KEY }}` is declared on the **`docker`**
job, not on the **`publish`** job. In `publish`:
- `Install cosign` — `if: env.COSIGN_KEY != ''` sees no job/workflow-level `COSIGN_KEY` → empty
  → **skipped**.
- `Sign image by digest` — has its **own step-level** `env.COSIGN_KEY`, which IS visible to that
  step's own `if` → **runs** → but cosign was never installed → exit 127.

### Fix (RC2)
Add a job-level `env` to the `publish` job so the install gate matches the sign gate:

```yaml
  publish:
    name: Build, Scan, Push & Deploy
    needs: [build]
    if: github.ref == 'refs/heads/main' && github.event_name == 'push' && !startsWith(github.event.head_commit.message, 'ci(deploy):')
    runs-on: ubuntu-latest
    env:
      COSIGN_KEY: ${{ secrets.COSIGN_KEY }}    # <-- add: makes Install-cosign gate fire
    permissions:
      …
```

(Equivalent alternatives: give the `Install cosign` step its own step-level `env.COSIGN_KEY`,
or drop the `if` and always install cosign. Job-level env is the minimal, symmetric fix and
matches the `docker` job.) frontend still needs RC1 too — after install is fixed it will hit
`invalid pem block` until the secret is re-seeded.

## Verification plan

1. Apply RC1 (re-seed `COSIGN_KEY` in all 5 image callers from true PEM via file).
2. Apply RC2 (frontend `publish` job-level env) on a branch → PR → merge (gated).
3. Re-trigger each caller's main build (empty commit or `gh run rerun`); confirm the
   `Sign image by digest` step is **success**.
4. Prove signatures exist: `cosign verify --key <cosign.pub> ghcr.io/wilddog64/<repo>@<digest>`
   (public key = ESO `cosign-public-key` secret / Vault `cosign.pub`), or check GHCR for the
   `sha256-<digest>.sig` tag.
5. Only then proceed to Stage D (Kyverno install + ClusterPolicy Audit→Enforce + promoter
   `cosign verify` gate) — Enforce must not go live until images actually carry signatures.

## Notes
- Do NOT print the private key or the `COSIGN_KEY`/`COSIGN_PASSWORD` values in logs, argv, or
  CI output. File-redirect / stdin only (OWASP A02 secret hygiene, per CLAUDE.md).
- Re-seeding is a live, outward-facing change across 5 repos — gate on explicit user go.
- Related durable improvement: teach `signing.sh` a `signing_seed_ci_secrets` helper that reads
  the PEM from Vault and `gh secret set … < file` across the caller repos, so this is never done
  by hand (and never via `security -w`) again.
