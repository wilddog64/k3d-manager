# 2026-06-27 — data-git YAML validation blocked by missing PyYAML

## What was tested / attempted

Spec `docs/bugs/v1.10.0-bugfix-data-layer-volumeclaimtemplates-status-drift.md` requires:

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('scripts/etc/argocd/applicationsets/data-git.yaml'))"
```

Run from repo root on branch `feat/v1.10.0-vault-auth-portable` after applying the `data-git.yaml` and BATS changes.

## Actual output

```text
Traceback (most recent call last):
  File "<string>", line 1, in <module>
    import yaml,sys; yaml.safe_load(open('scripts/etc/argocd/applicationsets/data-git.yaml'))
    ^^^^^^^^^^^^^^^
ModuleNotFoundError: No module named 'yaml'
```

## Root cause

The environment's `python3` does not have the `PyYAML` module installed, so the spec's exact validation command cannot run successfully here.

## Recommended follow-up

Install `PyYAML` for the interpreter used by `python3`, or replace the spec/runtime gate with a repository-local YAML validation method that does not depend on an unpinned host Python module.
