# 05 — External Secrets Operator (ESO)

**Topic:** *External Secrets Operator*
**Status:** Shipping. Source: `scripts/plugins/eso.sh`
(`deploy_eso`, `_eso_apply_vault_cluster_store`, `_eso_configure_remote_vault`).

---

## The one-liner

> "Secrets live in Vault, never in git. External Secrets Operator watches for
> `ExternalSecret` resources and *projects* the real secret from Vault into a native
> Kubernetes Secret in the right namespace, authenticating to Vault with the
> workload's own service account. So the git repo declares 'this app needs the LDAP
> bind password' without the password ever appearing anywhere in git or a manifest."

## The problem it solves

GitOps has one hole: **you can't commit secrets to git.** But GitOps says everything
that defines the cluster *should* be in git. ESO resolves the contradiction:

- **In git:** an `ExternalSecret` — a *pointer* that says "fetch key `bind-password`
  from Vault path `secret/ldap` and materialize it as Secret `ldap-creds`."
- **Not in git:** the actual value. ESO fetches it from Vault at runtime and writes
  the Kubernetes Secret.

You get declarative, reviewable secret *wiring* with the actual material staying in a
proper secrets manager.

## What it is (fundamentals — the CRDs)

- **`SecretStore` / `ClusterSecretStore`** — *where* secrets come from and *how* to
  authenticate. `ClusterSecretStore` is cluster-wide; `SecretStore` is
  namespace-scoped. In this repo the provider is Vault (KV v2), authenticated via
  **Kubernetes auth** — ESO presents a service-account token, Vault validates it and
  returns a scoped token.
- **`ExternalSecret`** — *what* to fetch and *what* Kubernetes Secret to create from
  it. This is the piece that lives in git.

## How it works in k3d-manager

`deploy_eso` installs the operator (pinned Helm chart, waits for CRDs +
webhook endpoint), then wires up stores:

1. **Local Vault store** (`_eso_apply_vault_cluster_store`) — a `ClusterSecretStore`
   named `vault-backend` pointing at the in-cluster Vault
   (`http://vault.secrets.svc:8200`), KV v2, authenticating via **Kubernetes auth**:
   a Vault role (`eso-ldap-directory`) bound to a specific service account
   (`eso-ldap-sa`) in a specific namespace (`identity`). Vault only issues a token to
   *that* SA in *that* namespace.

2. **Remote/app-cluster Vault store** (`_eso_configure_remote_vault`) — the harder,
   more interesting case. The **app cluster** (where shopping-cart workloads run) is a
   *different* cluster from the **hub** (where Vault lives). ESO in the app cluster
   points at a remote Vault address (`REMOTE_VAULT_ADDR`) and authenticates on a
   **per-cluster Kubernetes auth mount** (`kubernetes-app`, resolved by context via
   `_vault_app_auth_mount`). This is the "Vault endpoint is the open seam" problem —
   every cluster needs its own auth mount and role so one central Vault can serve many
   clusters without them sharing an identity.

The auth model is the point: **no static Vault token is stored anywhere.** ESO proves
its identity with a Kubernetes service-account token that Vault independently
validates. Kill the pod, the token's gone.

## Why it matters

- **Closes the GitOps secret gap** without SealedSecrets-style ciphertext-in-git or
  hand-managed Secrets. The material stays in Vault, the wiring stays in git.
- **Identity, not shared secrets.** Kubernetes-auth means each consumer authenticates
  as *itself* (its SA), scoped to a Vault role with least-privilege paths. There's no
  long-lived Vault token to leak.
- **Rotation is transparent.** Rotate the value in Vault; ESO re-syncs the Kubernetes
  Secret. The consuming workload sees a Secret update, not a redeploy. This is how the
  LDAP/Grafana credential rotations in this repo work end to end.
- **Multi-cluster is a first-class concern.** The remote-store path shows secrets
  crossing a cluster boundary securely — a hub Vault serving app clusters via
  per-cluster auth mounts, which is exactly the portability seam that made this
  non-trivial.

## Common questions

**Q: ESO vs. Sealed Secrets vs. SOPS?**
> Sealed Secrets and SOPS put *encrypted* secrets in git — you still commit
> ciphertext and manage decryption keys. ESO keeps the secret *out* of git entirely:
> only a pointer is committed, and the value is fetched from a real secrets manager at
> runtime. I prefer ESO because the source of truth is Vault, which I already operate,
> back up, and rotate.

**Q: How does ESO authenticate to Vault — where's the token?**
> There is no stored token. ESO uses Vault's Kubernetes auth: it presents its service
> account's projected token, Vault validates it against the cluster and checks the SA
> is bound to the role, then returns a short-lived scoped token. Identity comes from
> the pod, not a secret at rest.

**Q: A workload in a different cluster needs a secret from the hub Vault. How?**
> ESO in the app cluster points at the remote Vault address and authenticates on a
> per-cluster Kubernetes auth mount — each cluster gets its own mount and role, so one
> central Vault serves many clusters without them sharing an identity. The Vault
> endpoint and per-cluster auth mount are the seam I had to design around.

**Q: How do secret rotations propagate?**
> Rotate the value in Vault; ESO re-syncs on its refresh interval and updates the
> Kubernetes Secret in place. Whether the app picks it up live or needs a restart
> depends on how it consumes the Secret — but the *distribution* is automatic.

## How ESO + Vault PKI + the CVE loop fit together

- **Vault** is the trust root: PKI issues certs (guide 04), KV holds credentials.
- **ESO** is the *distribution layer* — it's how Vault material reaches namespaces
  without touching git.
- In the **planned** signing work (guide 06), ESO is what projects the cosign
  **public key** into the admission-controller namespace, so the verifier reads it
  from a Secret without ever touching Vault directly. Same pattern, new payload.
