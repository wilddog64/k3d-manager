#!/usr/bin/env bats

setup() {
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
  NODES_FILE="$BATS_TEST_TMPDIR/nodes.json"
  PODS_FILE="$BATS_TEST_TMPDIR/pods.json"
  DELETE_CALLS="$BATS_TEST_TMPDIR/delete-calls"
  : >"$DELETE_CALLS"
  cat >"$STUB_BIN/kubectl" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"get nodes -o json"*) cat "$NODES_FILE" ;;
  *"get pods -A -o json"*) cat "$PODS_FILE" ;;
  *"delete pod"*) printf '%s\n' "$*" >>"$DELETE_CALLS" ;;
  *) exit 2 ;;
esac
STUB
  chmod +x "$STUB_BIN/kubectl"
  export PATH="$STUB_BIN:$PATH" NODES_FILE PODS_FILE DELETE_CALLS
  cat >"$NODES_FILE" <<'JSON'
{"items":[
  {"metadata":{"name":"server-0"},"status":{"addresses":[{"type":"InternalIP","address":".5"}]}},
  {"metadata":{"name":"agent-0"},"status":{"addresses":[{"type":"InternalIP","address":".4"}]}},
  {"metadata":{"name":"agent-1"},"status":{"addresses":[{"type":"InternalIP","address":".3"}]}},
  {"metadata":{"name":"agent-2"},"status":{"addresses":[{"type":"InternalIP","address":".2"}]}}
]}
JSON
}

write_pods() {
  cat >"$PODS_FILE"
}

@test "hostnet drift: json reports exactly the three mismatched node-exporter pods" {
  write_pods <<'JSON'
{"items":[
  {"metadata":{"namespace":"monitoring","name":"node-exporter-server","ownerReferences":[{"kind":"DaemonSet"}]},"spec":{"hostNetwork":true,"nodeName":"server-0"},"status":{"phase":"Running","podIP":".5"}},
  {"metadata":{"namespace":"monitoring","name":"node-exporter-agent-0","ownerReferences":[{"kind":"DaemonSet"}]},"spec":{"hostNetwork":true,"nodeName":"agent-0"},"status":{"phase":"Running","podIP":".3"}},
  {"metadata":{"namespace":"monitoring","name":"node-exporter-agent-1","ownerReferences":[{"kind":"DaemonSet"}]},"spec":{"hostNetwork":true,"nodeName":"agent-1"},"status":{"phase":"Running","podIP":".5"}},
  {"metadata":{"namespace":"monitoring","name":"node-exporter-agent-2","ownerReferences":[{"kind":"DaemonSet"}]},"spec":{"hostNetwork":true,"nodeName":"agent-2"},"status":{"phase":"Running","podIP":".4"}}
]}
JSON
  run bin/k3dm-hostnet-drift --json
  [ "$status" -eq 0 ]
  [ "$(jq '.drifted | length' <<<"$output")" -eq 3 ]
  [[ "$output" == *"node-exporter-agent-0"* ]]
  [[ "$output" == *"node-exporter-agent-1"* ]]
  [[ "$output" == *"node-exporter-agent-2"* ]]
  [[ "$output" != *"node-exporter-server"* ]]
}

@test "hostnet drift: fix deletes DaemonSet pods and skips Deployment and bare pods" {
  write_pods <<'JSON'
{"items":[
  {"metadata":{"namespace":"monitoring","name":"ds-a","ownerReferences":[{"kind":"DaemonSet"}]},"spec":{"hostNetwork":true,"nodeName":"agent-0"},"status":{"phase":"Running","podIP":".3"}},
  {"metadata":{"namespace":"monitoring","name":"ds-b","ownerReferences":[{"kind":"DaemonSet"}]},"spec":{"hostNetwork":true,"nodeName":"agent-1"},"status":{"phase":"Running","podIP":".5"}},
  {"metadata":{"namespace":"monitoring","name":"ds-c","ownerReferences":[{"kind":"DaemonSet"}]},"spec":{"hostNetwork":true,"nodeName":"agent-2"},"status":{"phase":"Running","podIP":".4"}},
  {"metadata":{"namespace":"monitoring","name":"deployment-pod","ownerReferences":[{"kind":"Deployment"}]},"spec":{"hostNetwork":true,"nodeName":"agent-0"},"status":{"phase":"Running","podIP":".3"}},
  {"metadata":{"namespace":"monitoring","name":"bare-pod"},"spec":{"hostNetwork":true,"nodeName":"agent-1"},"status":{"phase":"Running","podIP":".5"}}
]}
JSON
  run bin/k3dm-hostnet-drift --fix
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$DELETE_CALLS" | tr -d ' ')" -eq 3 ]
  [[ "$output" == *"skipping monitoring/deployment-pod"* ]]
  [[ "$output" == *"skipping monitoring/bare-pod"* ]]
  run grep -q 'deployment-pod\|bare-pod' "$DELETE_CALLS"
  [ "$status" -ne 0 ]
}

@test "hostnet drift: no drift makes no delete calls" {
  write_pods <<'JSON'
{"items":[{"metadata":{"namespace":"monitoring","name":"node-exporter","ownerReferences":[{"kind":"DaemonSet"}]},"spec":{"hostNetwork":true,"nodeName":"server-0"},"status":{"phase":"Running","podIP":".5"}}]}
JSON
  run bin/k3dm-hostnet-drift --fix
  [ "$status" -eq 0 ]
  [ ! -s "$DELETE_CALLS" ]
}

@test "hostnet drift: a pod list larger than the per-argument limit is still read" {
  python3 - "$PODS_FILE" <<'PY'
import json, sys
items = [{"metadata": {"namespace": "monitoring", "name": "node-exporter-agent-0",
                       "ownerReferences": [{"kind": "DaemonSet"}]},
          "spec": {"hostNetwork": True, "nodeName": "agent-0"},
          "status": {"phase": "Running", "podIP": ".3"}}]
for i in range(200):
    items.append({"metadata": {"namespace": "apps", "name": f"app-{i}",
                               "managedFields": [{"fieldsV1": {"f:spec": "x" * 2048}}]},
                  "spec": {"nodeName": "agent-1"}, "status": {"phase": "Running", "podIP": "10.42.0.1"}})
json.dump({"items": items}, open(sys.argv[1], "w"))
PY
  [ "$(wc -c <"$PODS_FILE")" -gt 262144 ]
  run bin/k3dm-hostnet-drift --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"pod":"node-exporter-agent-0"'* ]]
  [[ "$output" != *"Argument list too long"* ]]
}
