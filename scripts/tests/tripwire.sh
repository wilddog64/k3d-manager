#!/usr/bin/env bash
# Run an offline test command with cluster, cloud and host-credential tools replaced by shims.
#
# Usage: scripts/tests/tripwire.sh <command> [args...]
#
# Every tool in TRIPWIRE_TOOLS resolves to a shim for the duration of the command. A shim passes a
# short list of offline subcommands (`kubectl kustomize`, `helm template`, `* version`) through to
# the real binary; any other call is logged, never executed, and returns 97. A test that stubs a
# tool itself still wins, because its stub directory is prepended after this one.
#
# After the command, blocked calls are summarized on stderr. A blocked call that is not a known
# read (see _tripwire_is_read) fails the run even when the command passed: a test that tries to
# create, delete or change something on the host must stub it, not rely on it failing.
set -euo pipefail

TRIPWIRE_TOOLS=(
  kubectl helm k3d k3s vcluster argocd docker colima orb orbctl kind multipass
  aws gcloud az terraform vault cosign cloudflared wrangler
  security launchctl ssh scp autossh gh
  agy gemini codex claude
)

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <command> [args...]" >&2
  exit 2
fi

_tripwire_is_read() {
  local tool="$1" args="$2"
  case "$tool" in
    kubectl)
      [[ " $args " =~ \ (exec|apply|create|delete|patch|replace|scale|edit|label|annotate|drain|cordon|uncordon|taint|rollout|cp|run|set|port-forward|proxy)\  ]] && return 1
      [[ " $args " =~ \ get\ (secret|secrets)([\ /]|$) ]] && return 1
      [[ " $args " =~ \ (get|describe|logs|top|explain|api-resources|api-versions|cluster-info|wait|config\ (view|get-contexts|current-context))\  ]]
      ;;
    helm)
      [[ " $args " =~ \ (install|upgrade|uninstall|delete|rollback|push|repo\ (add|update|remove)|registry|plugin)\  ]] && return 1
      [[ " $args " =~ \ (list|ls|status|get|history|show|search|repo\ list)\  ]]
      ;;
    k3d) [[ " $args " =~ \ (cluster\ (list|get)|kubeconfig\ get|node\ list|registry\ list)\  ]] ;;
    docker)
      [[ " $args " =~ \ (run|rm|rmi|kill|stop|start|restart|exec|push|pull|build|create|prune|network\ (create|rm)|volume\ (create|rm))\  ]] && return 1
      [[ " $args " =~ \ (ps|inspect|images|info|logs|context\ (ls|show))\  ]]
      ;;
    aws) [[ " $args " =~ \ (describe-[a-z-]+|get-[a-z-]+|list-[a-z-]+)\  ]] ;;
    security) [[ " $args " =~ ^\ (find-generic-password|find-internet-password|show-keychain-info)\  ]] ;;
    launchctl) [[ " $args " =~ ^\ (list|print)\  ]] ;;
    gh) [[ " $args " =~ ^\ (auth\ (token|status)|(pr|run|repo|release)\ (view|list))\  ]] ;;
    *) return 1 ;;
  esac
}

_tripwire_dir="$(mktemp -d "${TMPDIR:-/tmp}/k3dm-tripwire.XXXXXX")"
trap 'rm -rf "$_tripwire_dir"' EXIT
_tripwire_bin="$_tripwire_dir/bin"
_tripwire_log="$_tripwire_dir/blocked.log"
mkdir -p "$_tripwire_bin"
: > "$_tripwire_log"

for _tool in "${TRIPWIRE_TOOLS[@]}"; do
  cat > "$_tripwire_bin/$_tool" <<SHIM
#!/usr/bin/env bash
case "$_tool \${1:-} \${2:-}" in
  "kubectl kustomize "*|"kubectl version "*|"helm template "*|"helm version "*|"helm lint "*|"$_tool version "*|"$_tool --version "*)
    PATH=$(printf '%q' "$PATH") exec $_tool "\$@" ;;
esac
printf '%s\t%s\n' "$_tool" "\$*" >> $(printf '%q' "$_tripwire_log")
exit 97
SHIM
  chmod +x "$_tripwire_bin/$_tool"
done

set +e
PATH="$_tripwire_bin:$PATH" "$@"
_rc=$?
set -e

if [[ -s "$_tripwire_log" ]]; then
  _unsafe=0
  while IFS=$'\t' read -r _tool _args; do
    _tripwire_is_read "$_tool" "$_args" || _unsafe=$((_unsafe + 1))
  done < "$_tripwire_log"
  {
    echo "[tripwire] blocked $(wc -l < "$_tripwire_log" | tr -d ' ') call(s) to host tools; none reached a real binary:"
    sort "$_tripwire_log" | uniq -c | sort -rn | head -20
  } >&2
  if (( _unsafe > 0 )); then
    echo "[tripwire] FAIL: ${_unsafe} blocked call(s) were not reads — stub them in the test." >&2
    [[ $_rc -eq 0 ]] && _rc=1
  fi
fi
exit "$_rc"
