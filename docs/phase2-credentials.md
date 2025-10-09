
---

## 📄 `docs/phase2-credentials.md`

```markdown
# Phase 2 — Credentials Migration

Once pilot jobs are stable, migrate or recreate credentials needed by the next batch of jobs.

---

## 1️⃣ Option A — Direct Key & File Copy

Copy these from old `$JENKINS_HOME`:

* secrets/master.key
* secrets/hudson.util.Secret
* credentials.xml


To `/var/jenkins_home` on the new controller **before startup**.

Helm initContainer example:
```yaml
controller:
  initContainers:
    - name: creds-seed
      image: busybox:1.36
      command: ["/bin/sh","-c"]
      args:
        - |
          set -e
          mkdir -p /var/jenkins_home/secrets
          cp /seed/credentials.xml /var/jenkins_home/
          cp /seed/master.key /var/jenkins_home/secrets/
          cp /seed/hudson.util.Secret /var/jenkins_home/secrets/
          chown -R 1000:1000 /var/jenkins_home
      volumeMounts:
        - { name: jenkins-home, mountPath: /var/jenkins_home }
        - { name: cred-seed, mountPath: /seed, readOnly: true }
  volumes:
    - name: cred-seed
      secret:
        secretName: jenkins-cred-migration

