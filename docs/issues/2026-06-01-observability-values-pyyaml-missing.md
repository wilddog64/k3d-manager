# Observability values YAML validation: PyYAML unavailable

## What I tested

- `shellcheck scripts/plugins/observability.sh`
- `python3 -c "import yaml,sys; yaml.safe_load(sys.stdin)" < scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml`
- `python3 -c "import yaml,sys; yaml.safe_load(sys.stdin)" < scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`
- `ruby -e 'require "yaml"; YAML.safe_load(STDIN.read); puts "OK"' < scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml`
- `ruby -e 'require "yaml"; YAML.safe_load(STDIN.read); puts "OK"' < scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`

## Actual output

```text
Traceback (most recent call last):
  File "<string>", line 1, in <module>
    import yaml,sys; yaml.safe_load(sys.stdin)
    ^^^^^^^^^^^^^^^
ModuleNotFoundError: No module named 'yaml'
```

Ruby YAML parsing output:

```text
OK
OK
```

## Root cause

The environment does not have the `yaml` Python module installed, so the spec-required `python3 -c "import yaml,sys; ..."` validation cannot run here.

## Recommended follow-up

- Install PyYAML in the local environment or CI image so the spec-mandated validation command can run.
- Keep the Ruby parser check as a fallback verification for local development until PyYAML is available.
