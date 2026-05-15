#!/usr/bin/env bash

# show PVs bound to jenkins-test namespaces
# kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.claimRef.namespace}{"\t"}{.status.phase}{"\n"}{end}' \
# | awk '$2 ~ /^jenkins-test-/{print $1,$2,$3}'
#
# # delete them
# kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.claimRef.namespace}{"\n"}{end}' \
# | awk '$2 ~ /^jenkins-test-/{print $1}' | xargs -r kubectl delete pv

# example
# kubectl patch pv pvc-xxxxxxxx-xxxx -p '{"metadata":{"finalizers":[]}}' --type=merge

# quick view
# kubectl get pvc -A --no-headers \
#   -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase,SC:.spec.storageClassName | awk '$3!="Bound"{print}'


# loop through every PVC whose phase != Bound
while read -r ns name; do
  echo "Cleaning PVC $ns/$name"
    kubectl -n "$ns" patch pvc "$name" --type=merge -p '{"metadata":{"finalizers":null}}' || true
    kubectl -n "$ns" delete pvc "$name" --grace-period=0 --force || true
done < <(kubectl get pvc -A -o jsonpath='{range .items[?(@.status.phase!="Bound")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}')

