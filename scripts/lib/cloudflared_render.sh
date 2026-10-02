function _hub_recovery_render_cloudflared_config() {
  local provider="$1" in_file="$2" table="$3"
  awk -v provider="$provider" -v table="$table" '
    BEGIN {
      while ((getline line < table) > 0) {
        if (line ~ /^#/ || line == "") continue
        split(line, f, "\\t")
        if (f[2] == provider) origin[f[1]] = f[3]
      }
    }
    /^[[:space:]]*-[[:space:]]*hostname:/ { host = $NF; print; next }
    /^[[:space:]]*service:/ {
      if (host != "" && (host in origin)) sub(/service:.*/, "service: " origin[host])
      host = ""; print; next
    }
    { print }
  ' "$in_file"
}
