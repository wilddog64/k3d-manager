# Jenkins JCasC local admin block rendered with empty credentials

**Date:** 2026-02-27
**Status:** FIXED (needs redeploy confirmation)

## Summary

When running `deploy_jenkins --enable-vault` in "no directory service" mode, the
`scripts/etc/jenkins/values-default.yaml.tmpl` file is processed with `envsubst`. The template relies
on `${JENKINS_ADMIN_USER}` and `${JENKINS_ADMIN_PASS}` placeholders inside
`01-security.yaml`, but the deploy script never exported those environment variables. `envsubst`
therefore replaced them with empty strings, so the rendered JCasC ConfigMap contained:

```
users:
  - id: ""
    password: ""
permissions:
  - "Overall/Read:"
  - "Overall/Administer:"
```

Jenkins still booted, but there was no usable local admin, which in turn blocked the linux/kaniko
job upload scripts that rely on `jenkins-admin` credentials.

## Impact

- `_jenkins_run_smoke_test` fails to authenticate when it falls back to local auth.
- Job DSL uploads (`bin/upload-jenkins-test-jobs.sh`) cannot log in, so no regression jobs land.

## Fix

Before calling `envsubst`, `_deploy_jenkins` now ensures both variables stay as literal placeholders
when unset:

```bash
if [[ -z "${JENKINS_ADMIN_USER:-}" ]]; then
  printf -v JENKINS_ADMIN_USER '%s' '${JENKINS_ADMIN_USER}'
fi
```

This preserves the `${JENKINS_ADMIN_USER}` / `${JENKINS_ADMIN_PASS}` strings in the rendered values,
allowing Jenkins to resolve them at runtime from `controller.containerEnv`.

## Validation

- Redeploy Jenkins and confirm `/var/jenkins_home/casc_configs/01-security.yaml` contains the
  literal placeholders (no empty strings).
- Run `bin/smoke-test-jenkins.sh` to ensure it can log in with creds from the
  `jenkins-admin` secret.
