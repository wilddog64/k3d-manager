# Codex Task: Fix Frontend k8s Manifests (2026-03-21)

## Context

The `shopping-cart-frontend` pod is in CrashLoopBackOff on the ubuntu-k3s cluster. Root cause
confirmed by Gemini: every manual `kubectl patch` was reverted by ArgoCD auto-sync. The fix must
go through Git.

Three problems in the manifests:
1. `containerPort: 8080` — nginx listens on port 80 by default, not 8080
2. Readiness/liveness probes check `/health` on port `8080` — wrong port AND wrong path (nginx
   serves static files, no `/health` endpoint; correct path is `/`)
3. `service.yaml` has `targetPort: 8080` — must match the corrected container port

Secondary: nginx entrypoint script tries to write to `/etc/nginx/conf.d/default.conf` but runs as
user 101 (non-root) which lacks write permission. Add an `emptyDir` volume at `/etc/nginx/conf.d`
to allow the script to write there.

---

## Before You Start

```
Branch (all work repos): fix/frontend-manifest-port-probe
First: git pull origin main in shopping-cart-frontend repo
Then: read this spec in full before touching anything
```

Confirm you are working in: `shopping-cart-frontend`
Do NOT touch: `k3d-manager`, any other repo

---

## Target Files

1. `k8s/base/deployment.yaml`
2. `k8s/base/service.yaml`

---

## Changes

### k8s/base/deployment.yaml

**Change 1 — container port:**
```yaml
# Before:
          ports:
            - containerPort: 8080
              protocol: TCP
```
```yaml
# After:
          ports:
            - containerPort: 80
              protocol: TCP
```

**Change 2 — liveness probe:**
```yaml
# Before:
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
```
```yaml
# After:
          livenessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
```

**Change 3 — readiness probe:**
```yaml
# Before:
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 3
```
```yaml
# After:
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 3
```

**Change 4 — emptyDir volume for nginx conf.d (add after `securityContext` block, before end of container spec):**

Add to `spec.template.spec.containers[0].volumeMounts`:
```yaml
          volumeMounts:
            - name: nginx-conf-d
              mountPath: /etc/nginx/conf.d
```

Add to `spec.template.spec.volumes`:
```yaml
      volumes:
        - name: nginx-conf-d
          emptyDir: {}
```

---

### k8s/base/service.yaml

**Change — targetPort:**
```yaml
# Before:
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
      name: http
```
```yaml
# After:
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
      name: http
```

---

## Rules

- No other files may be touched
- No memory-bank updates
- No reformatting of unchanged lines
- LF line endings only
- Run `yamllint k8s/base/deployment.yaml k8s/base/service.yaml` if available

---

## Definition of Done

- [ ] `k8s/base/deployment.yaml` — containerPort 80, probes on port 80 path `/`, emptyDir volume added
- [ ] `k8s/base/service.yaml` — targetPort 80
- [ ] Committed on branch `fix/frontend-manifest-port-probe` with message:
      `fix(k8s): correct frontend port 8080→80, probe path /health→/, add nginx conf.d emptyDir`
- [ ] Report back: commit SHA only — do NOT update memory-bank, do NOT create a PR

## What NOT to Do

- Do NOT update `memory-bank/` — Claude will do that after verifying the SHA
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside `k8s/base/deployment.yaml` and `k8s/base/service.yaml`
- Do NOT commit to `main` — branch is `fix/frontend-manifest-port-probe`
- Do NOT change resource limits, replicas, labels, or any other fields
