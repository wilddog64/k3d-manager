# Spec validation note: PyYAML missing for ApplicationSet checks

## Context

While validating the `v1.5.0-platform-helm-argocd-multi-env` and
`v1.5.0-bugfix-services-git-externalsecret-refreshinterval-drift` changes, the
spec-required Python YAML validation command failed in this environment because
the `yaml` module is not installed for `python3`.

## Attempted commands

```text
ARGOCD_NAMESPACE=cicd envsubst '$ARGOCD_NAMESPACE' < scripts/etc/argocd/applicationsets/platform-helm.yaml | python3 -c "import sys,yaml; yaml.safe_load(sys.stdin)" && echo OK
python3 -c "import sys,yaml; yaml.safe_load(sys.stdin)" < scripts/etc/argocd/applicationsets/services-git.yaml && echo OK
```

## Actual output

```text
Traceback (most recent call last):
  File "<string>", line 1, in <module>
    import sys,yaml; yaml.safe_load(sys.stdin)
    ^^^^^^^^^^^^^^^
ModuleNotFoundError: No module named 'yaml'
```

## Root cause

`python3` is available, but PyYAML is not installed in this sandboxed environment.
The YAML parse step therefore cannot run as written in the specs.

## Follow-up

- Keep the spec command in the docs as-is.
- Use an available YAML parser in this environment when validating locally.
- Install PyYAML in the validation environment if the spec command must be used verbatim.
