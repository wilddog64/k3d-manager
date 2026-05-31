# PyYAML missing during shopping-cart PrometheusRule validation

## What I tested

Spec-mandated YAML validation for the new shopping-cart PrometheusRule manifest:

```bash
python3 -c "import yaml,sys; yaml.safe_load(sys.stdin)" < /Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-infra/monitoring/rules/shopping-cart-apps.yaml
```

## Actual Output

```text
Traceback (most recent call last):
  File "<string>", line 1, in <module>
    import yaml,sys; yaml.safe_load(sys.stdin)
    ^^^^^^^^^^^^^^^
ModuleNotFoundError: No module named 'yaml'
```

## Root Cause

This environment does not have the PyYAML module installed, so the spec-required
`python3 -c "import yaml,sys; ..."` validation command cannot run here.

## Follow-up

Use a Python environment with PyYAML installed for the spec-required check, or
install PyYAML in this workspace before rerunning the validation command.
