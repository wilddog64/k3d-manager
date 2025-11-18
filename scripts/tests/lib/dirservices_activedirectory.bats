#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"

  # Source system library for helper functions
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export SCRIPT_DIR

  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/lib/system.sh"

  # Source AD provider
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/lib/dirservices/activedirectory.sh"

  # Set up test environment variables
  export AD_DOMAIN="corp.example.com"
  export AD_SERVERS="dc1.corp.example.com,dc2.corp.example.com"
  export AD_BASE_DN="DC=corp,DC=example,DC=com"
  export AD_BIND_DN="CN=svc-jenkins,OU=ServiceAccounts,DC=corp,DC=example,DC=com"
  export AD_BIND_PASSWORD="test-password"
  export AD_USER_SEARCH_BASE="OU=Users,DC=corp,DC=example,DC=com"
  export AD_GROUP_SEARCH_BASE="OU=Groups,DC=corp,DC=example,DC=com"
  export AD_PORT="636"
  export AD_USE_SSL="1"
  export AD_VAULT_SECRET_PATH="ad/service-accounts/jenkins-admin"
  export AD_VAULT_KV_MOUNT="secret"
  export AD_TEST_MODE="1"  # Enable test mode to skip actual connectivity checks

  # Create log file
  LDAPSEARCH_LOG="$BATS_TEST_TMPDIR/ldapsearch.log"
  export LDAPSEARCH_LOG
  : > "$LDAPSEARCH_LOG"
}

# =============================================================================
# Test: _dirservice_activedirectory_config
# =============================================================================

@test "_dirservice_activedirectory_config displays configuration" {
  run _dirservice_activedirectory_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"Domain: corp.example.com"* ]]
  [[ "$output" == *"Servers: dc1.corp.example.com,dc2.corp.example.com"* ]]
  [[ "$output" == *"Base DN: DC=corp,DC=example,DC=com"* ]]
}

# =============================================================================
# Test: _dirservice_activedirectory_validate_config
# =============================================================================

@test "_dirservice_activedirectory_validate_config succeeds in test mode" {
  export AD_TEST_MODE=1
  run _dirservice_activedirectory_validate_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"test mode enabled - skipping connectivity validation"* ]]
}

@test "_dirservice_activedirectory_validate_config fails when AD_DOMAIN not set" {
  unset AD_DOMAIN
  export AD_TEST_MODE=0
  run _dirservice_activedirectory_validate_config
  [ "$status" -eq 1 ]
  [[ "$output" == *"AD_DOMAIN not set"* ]]
}

@test "_dirservice_activedirectory_validate_config fails when AD_SERVERS not set" {
  unset AD_SERVERS
  export AD_TEST_MODE=0
  run _dirservice_activedirectory_validate_config
  [ "$status" -eq 1 ]
  [[ "$output" == *"AD_SERVERS not set"* ]]
}

@test "_dirservice_activedirectory_validate_config fails when AD_BIND_DN not set" {
  unset AD_BIND_DN
  export AD_TEST_MODE=0
  run _dirservice_activedirectory_validate_config
  [ "$status" -eq 1 ]
  [[ "$output" == *"AD_BIND_DN not set"* ]]
}

@test "_dirservice_activedirectory_validate_config fails when AD_BIND_PASSWORD not set" {
  unset AD_BIND_PASSWORD
  export AD_TEST_MODE=0
  run _dirservice_activedirectory_validate_config
  [ "$status" -eq 1 ]
  [[ "$output" == *"AD_BIND_PASSWORD not set"* ]]
}

@test "_dirservice_activedirectory_validate_config skips check when ldapsearch unavailable" {
  export AD_TEST_MODE=0
  command() {
    if [[ "$1" == "-v" && "$2" == "ldapsearch" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command

  run _dirservice_activedirectory_validate_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"ldapsearch not available - skipping connectivity test"* ]]
}

# =============================================================================
# Test: _dirservice_activedirectory_generate_jcasc
# =============================================================================

@test "_dirservice_activedirectory_generate_jcasc creates valid YAML" {
  local output_file="$BATS_TEST_TMPDIR/jcasc.yaml"
  export AD_DOMAIN="test.example.com"
  export AD_CACHE_SIZE=100
  export AD_CACHE_TTL=7200
  export AD_GROUP_LOOKUP_STRATEGY="TOKENGROUPS"
  export AD_REMOVE_IRRELEVANT_GROUPS="true"
  export AD_TLS_CONFIG="JDK_TRUSTSTORE"

  run _dirservice_activedirectory_generate_jcasc "jenkins" "ad-secret" "$output_file"
  [ "$status" -eq 0 ]
  [ -f "$output_file" ]

  # Verify YAML structure
  grep -q "securityRealm:" "$output_file"
  grep -q "activeDirectory:" "$output_file"
  grep -q "name: \"test.example.com\"" "$output_file"
  grep -q "size: 100" "$output_file"
  grep -q "ttl: 7200" "$output_file"
  grep -q "groupLookupStrategy: \"TOKENGROUPS\"" "$output_file"
  grep -q "removeIrrelevantGroups: true" "$output_file"
  grep -q "tlsConfiguration: \"JDK_TRUSTSTORE\"" "$output_file"
}

@test "_dirservice_activedirectory_generate_jcasc requires namespace argument" {
  run _dirservice_activedirectory_generate_jcasc
  [ "$status" -ne 0 ]
  [[ "$output" == *"namespace required"* ]]
}

@test "_dirservice_activedirectory_generate_jcasc requires secret_name argument" {
  run _dirservice_activedirectory_generate_jcasc "jenkins"
  [ "$status" -ne 0 ]
  [[ "$output" == *"secret name required"* ]]
}

@test "_dirservice_activedirectory_generate_jcasc requires output_file argument" {
  run _dirservice_activedirectory_generate_jcasc "jenkins" "ad-secret"
  [ "$status" -ne 0 ]
  [[ "$output" == *"output file required"* ]]
}

# =============================================================================
# Test: _dirservice_activedirectory_generate_env_vars
# =============================================================================

@test "_dirservice_activedirectory_generate_env_vars creates output file" {
  local output_file="$BATS_TEST_TMPDIR/env_vars.yaml"

  run _dirservice_activedirectory_generate_env_vars "ad-secret" "$output_file"
  [ "$status" -eq 0 ]
  [ -f "$output_file" ]

  # Verify comment about Vault Agent file mounts
  grep -q "Vault Agent file mounts" "$output_file"
}

@test "_dirservice_activedirectory_generate_env_vars requires secret_name argument" {
  run _dirservice_activedirectory_generate_env_vars
  [ "$status" -ne 0 ]
  [[ "$output" == *"secret name required"* ]]
}

@test "_dirservice_activedirectory_generate_env_vars requires output_file argument" {
  run _dirservice_activedirectory_generate_env_vars "ad-secret"
  [ "$status" -ne 0 ]
  [[ "$output" == *"output file required"* ]]
}

# =============================================================================
# Test: _dirservice_activedirectory_generate_authz
# =============================================================================

@test "_dirservice_activedirectory_generate_authz creates valid authorization config" {
  local output_file="$BATS_TEST_TMPDIR/authz.yaml"

  run _dirservice_activedirectory_generate_authz "$output_file"
  [ "$status" -eq 0 ]
  [ -f "$output_file" ]

  # Verify YAML structure
  grep -q "authorizationStrategy:" "$output_file"
  grep -q "projectMatrix:" "$output_file"
  grep -q "permissions:" "$output_file"
  grep -q "Overall/Read:authenticated" "$output_file"
  grep -q "Overall/Administer:\${JENKINS_ADMIN_USER}" "$output_file"
}

@test "_dirservice_activedirectory_generate_authz includes custom permissions from env var" {
  local output_file="$BATS_TEST_TMPDIR/authz.yaml"
  export JENKINS_AUTHZ_PERMISSIONS="Job/Build:developers,Job/Read:users"

  run _dirservice_activedirectory_generate_authz "$output_file" "JENKINS_AUTHZ_PERMISSIONS"
  [ "$status" -eq 0 ]

  grep -q "Job/Build:developers" "$output_file"
  grep -q "Job/Read:users" "$output_file"
}

@test "_dirservice_activedirectory_generate_authz requires output_file argument" {
  run _dirservice_activedirectory_generate_authz
  [ "$status" -ne 0 ]
  [[ "$output" == *"output file required"* ]]
}

# =============================================================================
# Test: _dirservice_activedirectory_get_groups
# =============================================================================

@test "_dirservice_activedirectory_get_groups returns test groups in test mode" {
  export AD_TEST_MODE=1

  run _dirservice_activedirectory_get_groups "testuser"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CN=Jenkins Admins,OU=Groups,DC=corp,DC=example,DC=com"* ]]
  [[ "$output" == *"CN=IT Developers,OU=Groups,DC=corp,DC=example,DC=com"* ]]
}

@test "_dirservice_activedirectory_get_groups requires username argument" {
  run _dirservice_activedirectory_get_groups
  [ "$status" -ne 0 ]
  [[ "$output" == *"username required"* ]]
}

@test "_dirservice_activedirectory_get_groups fails when ldapsearch unavailable" {
  export AD_TEST_MODE=0
  command() {
    if [[ "$1" == "-v" && "$2" == "ldapsearch" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command

  run _dirservice_activedirectory_get_groups "testuser"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ldapsearch command not found"* ]]
}

# =============================================================================
# Test: _dirservice_activedirectory_create_credentials
# =============================================================================

@test "_dirservice_activedirectory_create_credentials validates AD_BIND_DN is set" {
  unset AD_BIND_DN

  run _dirservice_activedirectory_create_credentials "vault" "test/path" "vault" "vault"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AD_BIND_DN not set"* ]]
}

@test "_dirservice_activedirectory_create_credentials validates AD_BIND_PASSWORD is set" {
  unset AD_BIND_PASSWORD

  run _dirservice_activedirectory_create_credentials "vault" "test/path" "vault" "vault"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AD_BIND_PASSWORD not set"* ]]
}

@test "_dirservice_activedirectory_create_credentials fails when secret_backend_put unavailable" {
  run _dirservice_activedirectory_create_credentials "vault" "test/path" "vault" "vault"
  [ "$status" -eq 1 ]
  [[ "$output" == *"secret_backend_put function not available"* ]]
}

@test "_dirservice_activedirectory_create_credentials calls secret_backend_put when available" {
  # Mock secret_backend_put function
  secret_backend_put() {
    echo "secret_backend_put $*" >&2
    return 0
  }
  export -f secret_backend_put

  export AD_USERNAME_KEY="username"
  export AD_PASSWORD_KEY="password"
  export AD_DOMAIN_KEY="domain"
  export AD_SERVERS_KEY="servers"

  run _dirservice_activedirectory_create_credentials "vault" "ad/test" "vault" "vault"
  [ "$status" -eq 0 ]
  [[ "$output" == *"credentials stored successfully"* ]]
}

# =============================================================================
# Test: _dirservice_activedirectory_init
# =============================================================================

@test "_dirservice_activedirectory_init runs validation" {
  export AD_TEST_MODE=1

  # Mock secret_backend_put to avoid failure
  secret_backend_put() { return 0; }
  export -f secret_backend_put

  run _dirservice_activedirectory_init "jenkins" "jenkins" "vault" "vault"
  [ "$status" -eq 0 ]
  [[ "$output" == *"initializing for jenkins/jenkins"* ]]
  [[ "$output" == *"initialization complete"* ]]
}

@test "_dirservice_activedirectory_init fails when validation fails" {
  unset AD_DOMAIN
  export AD_TEST_MODE=0

  run _dirservice_activedirectory_init "jenkins" "jenkins" "vault" "vault"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AD_DOMAIN not set"* ]]
}

@test "_dirservice_activedirectory_init fails when credential storage fails" {
  export AD_TEST_MODE=1

  # Mock secret_backend_put to fail
  secret_backend_put() { return 1; }
  export -f secret_backend_put

  run _dirservice_activedirectory_init "jenkins" "jenkins" "vault" "vault"
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to store credentials"* ]]
}

# =============================================================================
# Test: _dirservice_activedirectory_smoke_test_login
# =============================================================================

@test "_dirservice_activedirectory_smoke_test_login requires jenkins_url argument" {
  run _dirservice_activedirectory_smoke_test_login
  [ "$status" -ne 0 ]
  [[ "$output" == *"Jenkins URL required"* ]]
}

@test "_dirservice_activedirectory_smoke_test_login requires test_user argument" {
  run _dirservice_activedirectory_smoke_test_login "http://jenkins.example.com"
  [ "$status" -ne 0 ]
  [[ "$output" == *"test user required"* ]]
}

@test "_dirservice_activedirectory_smoke_test_login requires test_password argument" {
  run _dirservice_activedirectory_smoke_test_login "http://jenkins.example.com" "testuser"
  [ "$status" -ne 0 ]
  [[ "$output" == *"test password required"* ]]
}

@test "_dirservice_activedirectory_smoke_test_login fails when curl unavailable" {
  command() {
    if [[ "$1" == "-v" && "$2" == "curl" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command

  run _dirservice_activedirectory_smoke_test_login "http://jenkins.example.com" "user" "pass"
  [ "$status" -eq 1 ]
  [[ "$output" == *"curl command not found"* ]]
}

@test "_dirservice_activedirectory_smoke_test_login fails when authentication fails" {
  # Mock curl to return empty crumb (authentication failure)
  curl() {
    echo '{"status":"error"}'
    return 0
  }
  export -f curl

  run _dirservice_activedirectory_smoke_test_login "http://jenkins.example.com" "user" "pass"
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to authenticate user"* ]]
}

@test "_dirservice_activedirectory_smoke_test_login succeeds with valid credentials" {
  # Mock curl to simulate successful authentication
  curl() {
    if [[ "$*" == *"crumbIssuer"* ]]; then
      echo '{"crumb":"test-crumb-value"}'
    elif [[ "$*" == *"me/api/json"* ]]; then
      echo '{"id":"testuser","fullName":"Test User"}'
    fi
    return 0
  }
  grep() {
    if [[ "$*" == *"crumb"* ]]; then
      echo '"crumb":"test-crumb-value"'
    elif [[ "$*" == *"id"* ]]; then
      echo '"id":"testuser"'
    fi
    return 0
  }
  cut() {
    if [[ "$*" == *"-f4"* ]]; then
      echo "testuser"
    else
      echo "test-crumb-value"
    fi
    return 0
  }
  export -f curl grep cut

  run _dirservice_activedirectory_smoke_test_login "http://jenkins.example.com" "testuser" "password"
  [ "$status" -eq 0 ]
  [[ "$output" == *"authenticated successfully"* ]]
}

# =============================================================================
# Test: Configuration Variable Defaults
# =============================================================================

@test "AD_BASE_DN auto-detection from AD_DOMAIN" {
  unset AD_BASE_DN
  export AD_DOMAIN="test.example.com"

  # Re-source to trigger auto-detection
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/etc/ad/vars.sh"

  [ "$AD_BASE_DN" = "DC=test,DC=example,DC=com" ]
}

@test "AD_USER_SEARCH_BASE uses AD_BASE_DN" {
  # Unset to allow fresh initialization
  unset AD_USER_SEARCH_BASE AD_BASE_DN
  export AD_BASE_DN="DC=custom,DC=domain,DC=com"

  # Re-source to get updated search base
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/etc/ad/vars.sh"

  [[ "$AD_USER_SEARCH_BASE" == *"DC=custom,DC=domain,DC=com"* ]]
}

@test "AD_GROUP_SEARCH_BASE uses AD_BASE_DN" {
  # Unset to allow fresh initialization
  unset AD_GROUP_SEARCH_BASE AD_BASE_DN
  export AD_BASE_DN="DC=custom,DC=domain,DC=com"

  # Re-source to get updated search base
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/etc/ad/vars.sh"

  [[ "$AD_GROUP_SEARCH_BASE" == *"DC=custom,DC=domain,DC=com"* ]]
}
