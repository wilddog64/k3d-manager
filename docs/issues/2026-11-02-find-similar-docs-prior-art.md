# Vector search for cluster-up CA trust prior art

On 2026-11-02, `make find-similar-docs` on M5 returned relevant historical CA-trust plans and bugs, and a timeout query returned the orphaned CloudFormation stack bug. The search results informed the dispatch scope; three targeted queries do not establish whether vector search is better than alternatives.

On M4, three local searches returned exit 0 but printed the following diagnostic and returned no retrieval results:

```text
find-similar-docs: retrieval unavailable — no embeddings credential. $K3DM_EMBEDDINGS_API_KEY is unset or empty; k3dm-embeddings-api-key: rc 44 — security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain.; gemini-cli-api-key: rc 44 — security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain.; hub Vault: cannot read vault-root: Unable to connect to the server: dial tcp 127.0.0.1:55730: connect: operation not permitted
find-similar-docs: falling back to the exact-slug glob is still correct.
```

An attempt to repeat the successful M5 queries from the restricted environment failed for each query with:

```text
ssh: Could not resolve hostname m5-air.local: nodename nor servname provided, or not known
```

M4 lacked the embedding credentials available to this process and the sandbox prevented the attempted local Vault connection; the later restricted SSH environment could not resolve M5. Follow up by restoring an appropriate credential source and testing retrieval against a representative set of known documents and a keyword-search baseline. A zero exit status alone does not prove vector retrieval took place.
