#!/usr/bin/env bats

# m5-air, macOS 26.5.1, [ -x ] capture by Claude over SSH on 2026-11-24.
# /bin/bash /bin/cp /bin/chmod /bin/date /bin/kill /bin/launchctl /bin/ls /bin/mkdir /bin/mv /bin/ps /bin/rm /bin/sleep
# /bin/zsh /usr/bin/head /usr/bin/id /usr/bin/install /usr/bin/mktemp /usr/bin/plutil /usr/bin/shasum /usr/bin/ssh-keygen
# /usr/bin/stat /usr/bin/tee /usr/bin/uname /usr/sbin/netstat /usr/sbin/sshd

_wc_paths() {
  local file
  for file in "$@"; do
    grep -Eho '(^|[[:space:]])/(bin|usr/bin|usr/sbin|sbin|usr/libexec)/[[:alnum:]_.+-]+' "$file" | sed 's/^[[:space:]]//' || true
  done | sort -u | grep -v '^/usr/bin/tmux$' || true
}

@test "[M2] [N1] invoked system tool paths exist on m5-air" {
  local files=("$BATS_TEST_DIRNAME/../../../bin/k3dm-web-console-sshd"
    "$BATS_TEST_DIRNAME/../../../bin/k3dm-web-console-totp"
    "$BATS_TEST_DIRNAME/../../lib/web_console_common.sh")
  local paths count path capture_list
  capture_list=' /bin/bash /bin/cp /bin/chmod /bin/date /bin/kill /bin/launchctl /bin/ls /bin/mkdir /bin/mv /bin/ps /bin/rm /bin/sleep /bin/zsh /usr/bin/head /usr/bin/id /usr/bin/install /usr/bin/mktemp /usr/bin/plutil /usr/bin/shasum /usr/bin/ssh-keygen /usr/bin/stat /usr/bin/tee /usr/bin/uname /usr/sbin/netstat /usr/sbin/sshd '
  paths=$(_wc_paths "${files[@]}")
  count=$(printf '%s\n' "$paths" | sed '/^$/d' | wc -l | tr -d ' ')
  [ "$count" -ge 20 ]
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    case " $capture_list " in *" $path "*) ;; *) printf 'uncaptured system path: %s\n' "$path" >&2; return 1 ;; esac
  done <<EOF
$paths
EOF

  # Positive control: the same scanner reports an injected nonexistent path.
  local injected="$BATS_TEST_TMPDIR/k3dm-web-console-sshd"
  cp "${files[0]}" "$injected"
  printf '\n/bin/doesnotexist\n' >> "$injected"
  paths=$(_wc_paths "$injected")
  printf '%s\n' "$paths" | grep -Fxq /bin/doesnotexist
  case " $capture_list " in *' /bin/doesnotexist '*) return 1 ;; esac
}
