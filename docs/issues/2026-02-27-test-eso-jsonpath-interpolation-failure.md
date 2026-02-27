# Issue: `test_eso` failure — `jsonpath` interpolation failure

## Date
2026-02-27

## Environment
- Hostname: `m4-air.local`
- OS: Darwin (macOS)
- Cluster Provider: `orbstack`

## Symptoms
`test_eso` fails when verifying the synced secret value:

```
error: error parsing jsonpath {.data.${secret_key}}, unrecognized character in action: U+007B '{'
kubectl command failed (1): kubectl -n eso-ns-1772154364-26197 get secret eso-test-1772154364-2526 -o jsonpath=\{.data.\$\{secret_key\}\} 
ERROR: failed to execute kubectl -n eso-ns-1772154364-26197 get secret eso-test-1772154364-2526 -o jsonpath={.data.${secret_key}}: 1
ERROR: Secret value mismatch: expected 'swordfish', got ''
```

## Root Cause
In `scripts/lib/test.sh` (line 634), the `kubectl get secret` command uses single quotes for the `-o jsonpath` argument:

```bash
synced=$(_kubectl -n "$es_ns" get secret "$es_name" -o jsonpath='{.data.${secret_key}}' | base64 -d)
```

The single quotes prevent the shell from expanding `${secret_key}`, so `kubectl` receives the literal string `{.data.${secret_key}}`, which is invalid `jsonpath`.

## Resolution
**FIXED (2026-02-27)** — Changed single quotes to double quotes so the shell expands `${secret_key}` before passing the argument to `kubectl`:

```bash
synced=$(_kubectl -n "$es_ns" get secret "$es_name" -o jsonpath="{.data.${secret_key}}" | base64 -d)
```

Locally validated: `PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager test_eso` passes.

## Evidence
The error message explicitly shows `unrecognized character in action: U+007B '{'`, which confirms that `${...}` was not expanded.
