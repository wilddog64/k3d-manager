# Existing ESO wiring test uses removed Python loader API

The curated batch run failed smoke-test ESO wiring. Independent focused rerun:

```text
1..6
ok 1 hub ESO rows use the hub context and prefix
ok 2 app ESO rows keep legacy names
ok 3 absent ESO CRD is skipped rather than failed
ok 4 kubeconfig error is not reported as not installed
ok 5 absent ESO CRD still reports not installed
not ok 6 smoke test ESO wiring samples app and hub through helper
# (in test file scripts/tests/lib/webhook_hub_eso.bats, line 155)
#   `[ "$status" -eq 0 ]' failed
# Last output:
# Traceback (most recent call last):
#   File "<stdin>", line 7, in <module>
# AttributeError: 'SourceFileLoader' object has no attribute 'load_module'. Did you mean '.exec_module' instead of '.load_module'?
```

The test calls SourceFileLoader.load_module(), which is unavailable in the
current Python runtime. These batch fixes did not touch the ESO test or its
production module. Recommended separate test-only follow-up: use
spec_from_loader/module_from_spec/exec_module, matching current repository
helpers. No production ESO fault is established by this failure. No live
cluster checks were performed and the out-of-scope file was not modified.
