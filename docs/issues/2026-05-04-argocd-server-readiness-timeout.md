# Argo CD server readiness timeout in `make up`

## What was tested
- `make up` on the local `k3d-k3d-cluster`
- `kubectl -n cicd wait --for=condition=available --timeout=180s deployment/argocd-server`
- Live cluster inspection after the failure

## Actual output
```text
kubectl -n cicd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

(You should delete the initial secret afterwards as suggested by the Getting Started Guide: https://argo-cd.readthedocs.io/en/stable/getting_started/#4-login-using-the-cli)
error: timed out waiting for the condition on deployments/argocd-server
kubectl command failed (1): kubectl -n cicd wait --for=condition=available --timeout=180s deployment/argocd-server
ERROR: failed to execute kubectl -n cicd wait --for=condition=available --timeout=180s deployment/argocd-server: 1
make: *** [up] Error 1
```

Live cluster state after the failure:

```text
NAME                                                READY   STATUS    RESTARTS   AGE   IP          NODE                       NOMINATED NODE   READINESS GATES
argocd-application-controller-0                     1/1     Running   0          12m   10.42.2.7   k3d-k3d-cluster-agent-0    <none>           <none>
argocd-applicationset-controller-57f6d87946-jkdk2   1/1     Running   0          12m   10.42.1.7   k3d-k3d-cluster-agent-2    <none>           <none>
argocd-dex-server-644db76c7c-lfqnh                  1/1     Running   0          12m   10.42.3.7   k3d-k3d-cluster-agent-1    <none>           <none>
argocd-notifications-controller-c4fd74969-gjphm     1/1     Running   0          12m   10.42.1.6   k3d-k3d-cluster-agent-2    <none>           <none>
argocd-redis-67cc88978d-dqz2z                       1/1     Running   0          12m   10.42.0.7   k3d-k3d-cluster-server-0   <none>           <none>
argocd-repo-server-758db67d7d-dzzxt                 1/1     Running   0          12m   10.42.0.6   k3d-k3d-cluster-server-0   <none>           <none>
argocd-server-b84dc4b65-5mmn9                       1/1     Running   0          12m   10.42.3.8   k3d-k3d-cluster-agent-1    <none>           <none>
```

Deployment describe excerpt:

```text
Conditions:
  Type           Status  Reason
  ----           ------  ------
  Available      True    MinimumReplicasAvailable
  Progressing    True    NewReplicaSetAvailable
Events:
  Type    Reason             Age   From                   Message
  ----    ------             ----  ----                   -------
  Normal  ScalingReplicaSet  12m   deployment-controller  Scaled up replica set argocd-server-b84dc4b65 to 1
```

## Root cause
- The bootstrap waits only 180 seconds for `deployment/argocd-server` to become Available.
- On this machine, the local Argo CD images are cold-pulled and the server does not become available until well after that window, so the fixed timeout is too short for the current startup path.

## Recommended follow-up
- Keep the Argo CD wait timeout configurable so slower local starts can be accommodated without changing the deployment logic.
- Use a longer default timeout for `argocd-server` startup in `deploy_argocd`.
