# ACG observability ApplicationSet investigation

**Investigated:** 2026-10-21 (read-only)
**Related bug:** `docs/bugs/2026-10-20-acg-expiry-leaves-observability-appset-degraded.md`
**Scope:** Live Argo CD hub state, cluster registration metadata, AWS CloudFormation state, and repository lifecycle ownership. No live resources were changed.

## Findings

### Current state does not confirm an expired sandbox

AWS credentials were valid for account `591706807878` in `us-west-2`. The expected ACG stack, `k3d-manager-cluster`, currently exists as `CREATE_COMPLETE`, created at `2026-10-21T20:27:50Z`. A read-only EC2 query found three running instances tagged to that stack. This is positive evidence that the sandbox is present now; it cannot establish what happened to the earlier sandbox or prove the lifecycle history that led to the screenshot.

The Argo CD ApplicationSet condition last transitioned at `2026-10-21T20:02:51Z`, before the current stack's creation time. The present evidence therefore fits a later sandbox provision that did not restore the expected Argo CD registration, but does not prove that causal sequence. No stack deletion or expiry is established by the current AWS state.

### The immediate reason the ApplicationSet is degraded is a missing Argo CD cluster name

The live `cicd/observability-acg` ApplicationSet reports:

```text
application destination spec is invalid: there are no clusters with this name: ubuntu-k3s (and 2 more)
```

Its destination is `ubuntu-k3s`. The only app-cluster-looking Secret found in the hub namespace is `ubuntu-k3s-app-cluster`, but its Argo CD cluster identity is internally `k3d-cluster`, with server `https://kubernetes.default.svc`; its labels also identify provider `k3d`, not `k3s-aws`. The expected `cluster-ubuntu-k3s` registration is absent. Thus the error is not simply an API timeout against a registered but unreachable `ubuntu-k3s`: Argo CD has no cluster registered under the destination name. The local Kubernetes context `k3d-k3d-cluster` is reachable, which is consistent with the Secret pointing to the hub's in-cluster API endpoint, not the ACG API.

Argo CD CLI RPC reads could not be used because the saved CLI session token was rejected as invalid. Kubernetes reads against the hub supplied the live ApplicationSet, Applications, and Secret metadata; the AWS provider queries were independently successful.

### Ownership and lifecycle paths

- The source of truth for this ApplicationSet is `scripts/etc/argocd/applicationsets/observability-acg.yaml`. It renders destination `APP_CLUSTER_NAME` (the live value is `ubuntu-k3s`) and defines three children: Prometheus, Loki, and Trivy Operator. The template has no parent `Application` source or owner reference.
- The live ApplicationSet carries `managed-by=k3d-manager` and `app-type=observability`, but has no Kubernetes owner reference or finalizer. Its in-cluster last-applied configuration identifies the repo template and release branch. `deploy_argocd_applicationsets` applies repo ApplicationSet manifests by rollout stage; this is a direct apply workflow, so no parent Argo CD Application was observed to recreate this set.
- `bin/cluster-up` registers the app cluster using `register_app_cluster`, restarts the Argo CD application controller, waits for an `ubuntu-k3s`/tunnel registration, and then reconciles other app-cluster registrations additively. This is the provision/re-registration owner.
- `bin/cluster-down` invokes `_k3s_aws_deregister_cluster`. That provider helper deletes `cluster-ubuntu-k3s` and Applications whose destination name or server matches the ACG context. It does not remove `observability-acg` itself.
- `bin/cleanup-stale-sandbox` is local cleanup only: it stops selected LaunchAgents and removes the local kube context. It does not inspect AWS expiry and does not clean hub Argo CD resources.
- `bin/cleanup-stale-clusters` is a separate, confirmed-only hub cleanup path. It considers only explicitly managed registration Secrets labeled `k3d-manager/managed=true`, requires expiry metadata plus a continuing API failure grace period, then deletes the registration and matching Applications. The observed `ubuntu-k3s-app-cluster` Secret is labeled `k3d-manager/managed=false` and has no expiry or sandbox identity, so it is outside that cleanup path.

### Other ACG state and remediation ownership

The read-only hub inventory found only `observability-acg` degraded among the inspected ACG/app-cluster ApplicationSets. No generated Applications targeting `ubuntu-k3s` were present; the invalid destination prevents successful generation. `observability-acg` uses automated prune/self-heal, so once a correctly named cluster registration exists Argo CD can regenerate its three Applications from the still-present ApplicationSet.

The immediate repair owner is the ACG provision/re-registration path (`bin/cluster-up` and `register_app_cluster`), which should be checked for why it did not leave a `cluster-ubuntu-k3s` Secret with the expected `data.name`, server, and `k3s-aws` metadata. The cleanup owner is `bin/cluster-down` for explicit teardown, with `bin/cleanup-stale-clusters` as a separate gated stale-registration path. An expiry alert or ApplicationSet degradation should remain a verification signal, not permission to delete. Before any cleanup change, correlate a sandbox identity to authoritative CloudFormation state and ensure the target registration belongs to that identity; the current unmanaged Secret has no identity metadata to support safe automated expiry cleanup.

No sync, refresh annotation, deletion, prune, apply, registration change, provisioning, or AWS mutation was performed. No alert-to-verification integration was triggered or tested during this read-only investigation.

## Source-path follow-up (2026-10-21)

The source defect is in the successful bring-up invariant. `bin/cluster-up` calls `register_app_cluster`, which applies the configured Secret, then proceeds without reading back its identity. Its later `argocd cluster list` loop accepts substring matches for `ubuntu-k3s` or the tunnel host, and after 120 seconds it warns and continues. Therefore it does not guarantee the exact registration required by `observability-acg` before deploying the ApplicationSet. The current `register_app_cluster` defaults and `bin/cluster-up` provider assignment produce the expected defaults (`cluster-ubuntu-k3s`, `ubuntu-k3s`, `k3s-aws`), but an apply can leave an absent or mismatched Secret without a local fail-closed diagnostic.

The observed `ubuntu-k3s-app-cluster` Secret (`data.name=k3d-cluster`, provider `k3d`, server `https://kubernetes.default.svc`) is consistent with a separate hub/in-cluster registration. It does not prove how the expected registration disappeared or whether the live state came from the current bring-up path. The narrow source correction adds exact post-apply verification of secret name, cluster name, provider, and server before later setup continues. A mismatch now fails with the expected and observed fields in the diagnostic. Regression coverage includes the expected ACG registration and the observed mismatching registration shape.

Remaining safe live observation: during the next operator-approved fresh ACG bring-up, record the `register_app_cluster` apply and immediate readback for `cicd/cluster-ubuntu-k3s` (Secret name, decoded `.data.name`, decoded `.data.server`, and `k3d-manager/provider`), then confirm Argo CD lists the exact `ubuntu-k3s` destination. If readback passes but the cluster is subsequently absent, capture the time and any teardown/reconcile activity around its removal. This distinguishes a bring-up registration defect from later runtime deletion without performing a mutation for this investigation.

The code-path verification does not establish that sandbox expiry caused the observed state. No live infrastructure or Argo CD mutation was performed.

## Evidence captured

Commands below were read-only. Relevant output is preserved verbatim; the AWS caller identity was reduced to account ID to avoid retaining unnecessary identity detail.

```text
$ kubectl config current-context
k3d-k3d-cluster

$ kubectl get applicationsets.argoproj.io -A -o wide
NAMESPACE   NAME                             AGE
cicd        data-git                         5d20h
cicd        demo-rollout                     5d20h
cicd        eso                              5d20h
cicd        grafana-dashboards-acg           5d20h
cicd        grafana-dashboards-hub           5d20h
cicd        hostinger-cve-inventory-reader   5d20h
cicd        istio-ambient                    5d20h
cicd        observability                    5d20h
cicd        observability-acg                5d20h
cicd        platform-helm                    5d20h
cicd        platform-ops                     5d20h
cicd        services-git                     5d20h
cicd        vectordb                         5d20h

$ kubectl get applications.argoproj.io -A -o wide
NAMESPACE   NAME                                             SYNC STATUS   HEALTH STATUS   REVISION                                   PROJECT
cicd        blackbox-exporter                                Synced        Healthy                                                    platform
cicd        hub-grafana-dashboards                           Synced        Healthy                                                    platform
cicd        hub-loki                                         Synced        Healthy                                                    platform
cicd        hub-platform-ops                                 Synced        Healthy         b9fa8b9d6439fa6c3869a50671adbbcee5421dfb   platform
cicd        hub-pushgateway                                  Synced        Healthy                                                    platform
cicd        hub-vectordb                                     Synced        Healthy                                                    platform
cicd        istio-base-ubuntu-hostinger                      Synced        Healthy         1.24.2                                     platform
cicd        istio-cni-ubuntu-hostinger                       Synced        Healthy         1.24.2                                     platform
cicd        istiod-ubuntu-hostinger                          Synced        Healthy         1.24.2                                     platform
cicd        k3d-cluster-eso                                  Synced        Healthy         1.0.0                                      platform
cicd        k3d-cluster-grafana-dashboards                   Synced        Healthy         b9fa8b9d6439fa6c3869a50671adbbcee5421dfb   platform
cicd        kube-prometheus-stack                            Synced        Healthy                                                    platform
cicd        rollout-demo-default                             Synced        Healthy         a8909477a96bb67e3f33caa73b0b8260f85d8b25   platform
cicd        rollout-demo-staging                             Synced        Healthy         a8909477a96bb67e3f33caa73b0b8260f85d8b25   platform
cicd        shopping-cart-apps                               Synced        Healthy         542bb0116dbbbd3b18cd83256759bc60404e1c49   shopping-cart
cicd        shopping-cart-identity                           Synced        Healthy                                                    shopping-cart
cicd        shopping-cart-networking                         Synced        Healthy         542bb0116dbbbd3b18cd83256759bc60404e1c49   shopping-cart
cicd        trivy-operator                                   Synced        Healthy                                                    platform
cicd        ubuntu-hostinger-cve-inventory-reader            Synced        Healthy         b9fa8b9d6439fa6c3869a50671adbbcee5421dfb   platform
cicd        ubuntu-hostinger-data-layer                      Synced        Healthy         542bb0116dbbbd3b18cd83256759bc60404e1c49   shopping-cart
cicd        ubuntu-hostinger-eso                             Synced        Healthy         1.0.0                                      platform
cicd        ubuntu-hostinger-grafana-dashboards              Synced        Healthy         b9fa8b9d6439fa6c3869a50671adbbcee5421dfb   platform
cicd        ubuntu-hostinger-platform                        Synced        Healthy         7.8.1                                      platform
cicd        ubuntu-hostinger-shopping-cart-basket            Synced        Healthy         b9fa8b9d6439fa6c3869a50671adbbcee5421dfb   shopping-cart
cicd        ubuntu-hostinger-shopping-cart-frontend          Synced        Healthy         b9fa8b9d6439fa6c3869a50671adbbcee5421dfb   shopping-cart
cicd        ubuntu-hostinger-shopping-cart-namespace         Synced        Healthy         b9fa8b9d6439fa6c3869a50671adbbcee5421dfb   shopping-cart
cicd        ubuntu-hostinger-shopping-cart-order             Synced        Healthy         b9fa8b9d6439fa6c3869a50671adbbcee5421dfb   shopping-cart
cicd        ubuntu-hostinger-shopping-cart-payment           Synced        Healthy         542bb0116dbbbd3b18cd83256759bc60404e1c49   shopping-cart
cicd        ubuntu-hostinger-shopping-cart-product-catalog   Synced        Healthy         b9fa8b9d6439fa6c3869a50671adbbcee5421dfb   shopping-cart
cicd        ztunnel-ubuntu-hostinger                         Synced        Healthy         1.24.2                                     platform

$ kubectl get secret ubuntu-k3s-app-cluster -n cicd -o json | jq '{name:.metadata.name,labels:.metadata.labels,annotations:.metadata.annotations,created:.metadata.creationTimestamp,decoded:{name:(.data.name|@base64d),server:(.data.server|@base64d)}}'
{
  "name": "ubuntu-k3s-app-cluster",
  "labels": {
    "argocd.argoproj.io/cluster-name": "k3d-cluster",
    "argocd.argoproj.io/secret-type": "cluster",
    "k3d-manager/managed": "false",
    "k3d-manager/provider": "k3d",
    "k3d-manager/release": "unknown",
    "k3d-manager/role": "app-cluster",
    "k3d-manager/shopping-cart": "false"
  },
  "annotations": {
    "k3d-manager/expires-at": "",
    "k3d-manager/registered-at": "2026-10-16T02:15:59Z",
    "k3d-manager/sandbox-id": ""
  },
  "created": "2026-10-16T02:15:59Z",
  "decoded": {
    "name": "k3d-cluster",
    "server": "https://kubernetes.default.svc"
  }
}

$ kubectl get applicationset observability-acg -n cicd -o json | jq '{creationTimestamp:.metadata.creationTimestamp,ownerReferences:.metadata.ownerReferences,finalizers:.metadata.finalizers,labels:.metadata.labels,destination:.spec.template.spec.destination,status:.status}'
{
  "creationTimestamp": "2026-10-16T02:12:32Z",
  "ownerReferences": null,
  "finalizers": null,
  "labels": {
    "app-type": "observability",
    "k3dm.k3d.io/rollout-stage": "app-cluster",
    "managed-by": "k3d-manager"
  },
  "destination": {
    "name": "ubuntu-k3s",
    "namespace": "{{.namespace}}"
  },
  "status": {
    "conditions": [
      {
        "lastTransitionTime": "2026-10-21T20:02:51Z",
        "message": "application destination spec is invalid: there are no clusters with this name: ubuntu-k3s (and 2 more)",
        "reason": "ApplicationValidationError",
        "status": "True",
        "type": "ErrorOccurred"
      },
      {
        "lastTransitionTime": "2026-10-16T02:12:32Z",
        "message": "Successfully generated parameters for all Applications",
        "reason": "ParametersGenerated",
        "status": "True",
        "type": "ParametersGenerated"
      },
      {
        "lastTransitionTime": "2026-10-21T20:02:51Z",
        "message": "application destination spec is invalid: there are no clusters with this name: ubuntu-k3s (and 2 more)",
        "reason": "ErrorOccurred",
        "status": "False",
        "type": "ResourcesUpToDate"
      }
    ],
    "health": {
      "message": "application destination spec is invalid: there are no clusters with this name: ubuntu-k3s (and 2 more)",
      "status": "Degraded"
    }
  }
}

$ aws sts get-caller-identity --query '{Account:Account}' --output json
{
    "Account": "591706807878"
}

$ aws cloudformation describe-stacks --region us-west-2 --stack-name k3d-manager-cluster --query 'Stacks[0].{StackName:StackName,StackId:StackId,Status:StackStatus,CreationTime:CreationTime,LastUpdatedTime:LastUpdatedTime,DeletionTime:DeletionTime}' --output json
{
    "StackName": "k3d-manager-cluster",
    "StackId": "arn:aws:cloudformation:us-west-2:591706807878:stack/k3d-manager-cluster/e3038ea0-cd8d-11f1-84cf-0affd11b62c1",
    "Status": "CREATE_COMPLETE",
    "CreationTime": "2026-10-21T20:27:50.847000+00:00",
    "LastUpdatedTime": "2026-10-21T20:27:56.384000+00:00",
    "DeletionTime": null
}

$ aws ec2 describe-instances --region us-west-2 --filters 'Name=tag:aws:cloudformation:stack-name,Values=k3d-manager-cluster' --query 'Reservations[].Instances[].{Id:InstanceId,State:State.Name,Name:Tags[?Key==`Name`]|[0].Value,LaunchTime:LaunchTime}' --output table
|                                   DescribeInstances                                   |
+---------------------+-----------------------------+------------------------+----------+
|         Id          |         LaunchTime          |         Name           |  State   |
+---------------------+-----------------------------+------------------------+----------+
|  i-0efd47411e2ad5ee8|  2026-10-21T20:28:22+00:00  |  k3d-manager-ubuntu    |  running |
|  i-0b6f1701bc8fea512|  2026-10-21T20:28:21+00:00  |  k3d-manager-ubuntu-1  |  running |
|  i-0283d8fc4da388176|  2026-10-21T20:28:21+00:00  |  k3d-manager-ubuntu-2  |  running |
+---------------------+-----------------------------+------------------------+----------+
```

## Rules gates (2026-10-21 source-path follow-up)

```text
$ bats scripts/tests/bin/cluster_up.bats
1..67
66 passed; test 66 failed because the sandbox denied the test fixture's loopback bind:
PermissionError: [Errno 1] Operation not permitted
```

```text
$ bats scripts/tests/plugins/argocd.bats
1..39
39 passed
```

```text
$ shellcheck bin/cluster-up scripts/plugins/argocd.sh
exit=1
ShellCheck reported existing SC1091, SC2015, SC2016 and SC2029 diagnostics in bin/cluster-up; no diagnostics were reported in the changed plugin helper.
$ shellcheck -x scripts/plugins/argocd.sh
exit=0
```

```text
$ git diff --check
exit=0
$ bash -c 'source scripts/lib/foundation/scripts/lib/agent_rigor.sh; _agent_audit'
exit=0
```

The standalone `_agent_audit` command is a Bash function, so it was invoked after sourcing its repository definition under Bash (direct invocation from the provided zsh shell fails because `status` is a readonly zsh variable). No live infrastructure or Argo CD mutations were performed.
