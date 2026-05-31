# Validation note: PyYAML missing for platform project YAML check

## Context

While validating the `v1.5.0-bugfix-platform-project-missing-cicd-ubuntu-k3s` change,
the spec-required Python YAML validation command failed in this environment because the
`yaml` module is not installed for `python3`.

## Attempted command

```text
python3 -c "import sys,yaml; yaml.safe_load(sys.stdin)" < scripts/etc/argocd/projects/platform.yaml.tmpl && echo OK
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

`python3` is installed, but PyYAML is not available in this sandboxed environment.
The validation step therefore cannot run exactly as written in the spec.

## Follow-up

- Keep the spec command in the docs as-is.
- Use an available YAML parser locally when validating if PyYAML is absent.
- Install PyYAML in the validation environment if the exact command must run verbatim.
