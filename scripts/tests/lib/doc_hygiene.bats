#!/usr/bin/env bats

setup() {
   TEST_DIR="$(mktemp -d)"
   local lib_dir="${BATS_TEST_DIRNAME}/../../lib"
   # shellcheck source=/dev/null
   source "$lib_dir/system.sh"
   # shellcheck source=/dev/null
   source "$lib_dir/doc_hygiene.sh"
}

teardown() {
   rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Check 1 — placeholder GitHub URLs
# ---------------------------------------------------------------------------

@test "placeholder github.com/user/ URL in markdown fails" {
   echo "See [repo](https://github.com/user/myrepo)" > "$TEST_DIR/test.md"
   run _doc_hygiene_check "$TEST_DIR/test.md"
   [ "$status" -eq 1 ]
}

@test "real github.com/wilddog64/ URL in markdown passes" {
   echo "See [repo](https://github.com/wilddog64/myrepo)" > "$TEST_DIR/test.md"
   run _doc_hygiene_check "$TEST_DIR/test.md"
   [ "$status" -eq 0 ]
}

@test "placeholder github.com/user/ URL in YAML fails" {
   printf 'repo: https://github.com/user/myrepo\n' > "$TEST_DIR/test.yaml"
   run _doc_hygiene_check "$TEST_DIR/test.yaml"
   [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Check 2 — bare http:// links in markdown
# ---------------------------------------------------------------------------

@test "bare http:// link in markdown fails" {
   echo "Visit http://example.com for details" > "$TEST_DIR/test.md"
   run _doc_hygiene_check "$TEST_DIR/test.md"
   [ "$status" -eq 1 ]
}

@test "https:// link in markdown passes" {
   echo "Visit https://example.com for details" > "$TEST_DIR/test.md"
   run _doc_hygiene_check "$TEST_DIR/test.md"
   [ "$status" -eq 0 ]
}

@test "bare http:// in YAML does not trigger markdown check" {
   printf 'url: http://example.com\n' > "$TEST_DIR/test.yaml"
   run _doc_hygiene_check "$TEST_DIR/test.yaml"
   [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Check 3 — hardcoded private IPs in YAML (non-blocking)
# ---------------------------------------------------------------------------

@test "hardcoded 10.x.x.x IP in YAML warns but passes" {
   printf 'server: https://10.211.55.14:6443\n' > "$TEST_DIR/test.yaml"
   run _doc_hygiene_check "$TEST_DIR/test.yaml"
   [ "$status" -eq 0 ]
   [[ "$output" == *"hardcoded private IP"* ]]
}

@test "hardcoded 192.168.x.x IP in YAML warns but passes" {
   printf 'host: 192.168.1.100\n' > "$TEST_DIR/test.yaml"
   run _doc_hygiene_check "$TEST_DIR/test.yaml"
   [ "$status" -eq 0 ]
   [[ "$output" == *"hardcoded private IP"* ]]
}

@test "hardcoded 172.16.x.x IP in YAML warns but passes" {
   printf 'host: 172.16.0.1\n' > "$TEST_DIR/test.yaml"
   run _doc_hygiene_check "$TEST_DIR/test.yaml"
   [ "$status" -eq 0 ]
   [[ "$output" == *"hardcoded private IP"* ]]
}

@test "public IP in YAML does not warn" {
   printf 'host: 8.8.8.8\n' > "$TEST_DIR/test.yaml"
   run _doc_hygiene_check "$TEST_DIR/test.yaml"
   [ "$status" -eq 0 ]
   [[ "$output" != *"hardcoded private IP"* ]]
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "clean markdown file passes all checks" {
   cat > "$TEST_DIR/clean.md" <<'EOF'
# My Repo

See [repo](https://github.com/wilddog64/myrepo).
Visit https://example.com for details.
EOF
   run _doc_hygiene_check "$TEST_DIR/clean.md"
   [ "$status" -eq 0 ]
}

@test "non-existent file is skipped" {
   run _doc_hygiene_check "/tmp/does-not-exist-$(date +%s).md"
   [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Staged-content read (_DHC_STAGED path)
# ---------------------------------------------------------------------------

@test "violation in staged content is caught even when working tree is clean" {
   git -C "$TEST_DIR" init -q
   git -C "$TEST_DIR" config user.email "test@test.com"
   git -C "$TEST_DIR" config user.name "Test"
   # Stage a file with a placeholder URL
   echo "See [repo](https://github.com/user/myrepo)" > "$TEST_DIR/staged.md"
   git -C "$TEST_DIR" add staged.md
   # Fix the working-tree copy AFTER staging — staged content still has violation
   echo "See [repo](https://github.com/wilddog64/myrepo)" > "$TEST_DIR/staged.md"
   # Run with no args from inside the repo — staged mode, should FAIL (index has violation)
   local prev_dir="$PWD"
   cd "$TEST_DIR"
   run _doc_hygiene_check
   cd "$prev_dir"
   [ "$status" -eq 1 ]
   [[ "$output" == *"placeholder URL"* ]]
}

@test "explicit file path uses working-tree content not index" {
   echo "See [repo](https://github.com/wilddog64/myrepo)" > "$TEST_DIR/clean.md"
   run _doc_hygiene_check "$TEST_DIR/clean.md"
   [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Check 2 — code-fence exclusion
# ---------------------------------------------------------------------------

@test "bare http:// inside fenced code block does not trigger Check 2" {
   cat > "$TEST_DIR/test.md" <<'EOF'
# Example

```
url: http://internal.example.com
```
EOF
   run _doc_hygiene_check "$TEST_DIR/test.md"
   [ "$status" -eq 0 ]
}

@test "bare http:// outside fenced code block still triggers Check 2" {
   cat > "$TEST_DIR/test.md" <<'EOF'
Visit http://example.com for details.

```
echo ok
```
EOF
   run _doc_hygiene_check "$TEST_DIR/test.md"
   [ "$status" -eq 1 ]
}

@test "bare http:// inside tilde fenced block does not trigger Check 2" {
   cat > "$TEST_DIR/test.md" <<'EOF'
# Example

~~~bash
url: http://internal.example.com
~~~
EOF
   run _doc_hygiene_check "$TEST_DIR/test.md"
   [ "$status" -eq 0 ]
}

@test "bare http:// inside indented fenced code block does not trigger Check 2" {
   cat > "$TEST_DIR/test.md" <<'EOF'
- item

   ```bash
   url: http://internal.example.com
   ```
EOF
   run _doc_hygiene_check "$TEST_DIR/test.md"
   [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Check 4 — hardcoded internal CoreDNS names in YAML (non-blocking)
# ---------------------------------------------------------------------------

@test "FQDN svc.cluster.local in YAML warns but passes" {
   printf 'url: https://my-service.default.svc.cluster.local:8080\n' > "$TEST_DIR/test.yaml"
   run _doc_hygiene_check "$TEST_DIR/test.yaml"
   [ "$status" -eq 0 ]
   [[ "$output" == *"hardcoded internal CoreDNS name"* ]]
}

@test "short svc name in YAML warns but passes" {
   printf 'host: my-service.default.svc\n' > "$TEST_DIR/test.yaml"
   run _doc_hygiene_check "$TEST_DIR/test.yaml"
   [ "$status" -eq 0 ]
   [[ "$output" == *"hardcoded internal CoreDNS name"* ]]
}

@test "public DNS name in YAML does not warn" {
   printf 'host: api.example.com\n' > "$TEST_DIR/test.yaml"
   run _doc_hygiene_check "$TEST_DIR/test.yaml"
   [ "$status" -eq 0 ]
   [[ "$output" != *"hardcoded internal CoreDNS name"* ]]
}

@test "CoreDNS check does not apply to markdown" {
   printf 'See my-service.default.svc.cluster.local for details.\n' > "$TEST_DIR/test.md"
   run _doc_hygiene_check "$TEST_DIR/test.md"
   [ "$status" -eq 0 ]
   [[ "$output" != *"hardcoded internal CoreDNS name"* ]]
}
