#!/usr/bin/env bash

k3dm_promtool() {
  local candidate
  if [[ -n "${PROMTOOL:-}" && -x "${PROMTOOL}" ]]; then
    candidate="$PROMTOOL"
  elif [[ -x "$HOME/.local/bin/promtool" ]]; then
    candidate="$HOME/.local/bin/promtool"
  elif candidate="$(command -v promtool 2>/dev/null)"; then
    :
  else
    printf '%s\n' 'promtool not found; run make machine-setup (installs promtool 3.1.0)' >&2
    return 1
  fi
  "$candidate" "$@"
}
