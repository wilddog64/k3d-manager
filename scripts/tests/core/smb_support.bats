#!/usr/bin/env bats

load '../test_helpers.bash'

setup() {
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
}

@test "_ensure_smb_secret applies manifest with encoded values" {
  SMB_SECRET_NAME=test-credentials
  SMB_SECRET_NAMESPACE=jenkins
  SMB_USERNAME='svcUser'
  SMB_PASSWORD='P@ss w0rd!'
  SMB_DOMAIN='PACIFIC'
  export SMB_SECRET_NAME SMB_SECRET_NAMESPACE SMB_USERNAME SMB_PASSWORD SMB_DOMAIN

  SECRET_MANIFEST="$BATS_TMPDIR/secret.yaml"
  _kubectl() {
    if [[ "$1" == "apply" && "$2" == "-f" ]]; then
      cp "$3" "$SECRET_MANIFEST"
    fi
    echo "$*" >>"$KUBECTL_LOG"
    return 0
  }
  export -f _kubectl

  run _ensure_smb_secret
  [ "$status" -eq 0 ]
  grep -q 'apply -f ' "$KUBECTL_LOG"
  [ -f "$SECRET_MANIFEST" ]
  grep -q 'name: test-credentials' "$SECRET_MANIFEST"
  grep -q 'namespace: jenkins' "$SECRET_MANIFEST"
  grep -q 'username: c3ZjVXNlcg==' "$SECRET_MANIFEST"
  grep -q 'password: UEBzcyB3MHJkIQ==' "$SECRET_MANIFEST"
  grep -q 'domain: UEFDSUZJQw==' "$SECRET_MANIFEST"
}

@test "_ensure_smb_secret skips when credentials missing" {
  unset SMB_USERNAME SMB_PASSWORD
  run _ensure_smb_secret
  [ "$status" -eq 1 ]
  [[ "$output" == *"SMB_USERNAME/SMB_PASSWORD not set"* ]]
}

@test "_ensure_smb_storage_class applies manifest with defaults" {
  SMB_SECRET_NAME=test-credentials
  SMB_SECRET_NAMESPACE=jenkins
  SMB_SOURCE='//server/share'
  SMB_STORAGE_CLASS_NAME=my-smb
  SMB_STORAGE_RECLAIM_POLICY=Delete
  SMB_ALLOW_EXPANSION=false
  SMB_DIR_MODE=0755
  SMB_FILE_MODE=0644
  SMB_MOUNT_OPTIONS='mfsymlinks,actimeo=1'
  export SMB_SECRET_NAME SMB_SECRET_NAMESPACE SMB_SOURCE SMB_STORAGE_CLASS_NAME
  export SMB_STORAGE_RECLAIM_POLICY SMB_ALLOW_EXPANSION SMB_DIR_MODE SMB_FILE_MODE SMB_MOUNT_OPTIONS

  STORAGE_MANIFEST="$BATS_TMPDIR/storage.yaml"
  _kubectl() {
    if [[ "$1" == "apply" && "$2" == "-f" ]]; then
      cp "$3" "$STORAGE_MANIFEST"
    fi
    echo "$*" >>"$KUBECTL_LOG"
    return 0
  }
  export -f _kubectl

  run _ensure_smb_storage_class
  [ "$status" -eq 0 ]
  grep -q 'apply -f ' "$KUBECTL_LOG"
  [ -f "$STORAGE_MANIFEST" ]
  grep -q 'name: my-smb' "$STORAGE_MANIFEST"
  grep -q 'source: //server/share' "$STORAGE_MANIFEST"
  grep -q 'node-stage-secret-name: test-credentials' "$STORAGE_MANIFEST"
  grep -q 'node-stage-secret-namespace: jenkins' "$STORAGE_MANIFEST"
  grep -q 'reclaimPolicy: Delete' "$STORAGE_MANIFEST"
  grep -q 'allowVolumeExpansion: false' "$STORAGE_MANIFEST"
  grep -q 'dir_mode=0755' "$STORAGE_MANIFEST"
  grep -q 'file_mode=0644' "$STORAGE_MANIFEST"
  grep -q 'cache=strict' "$STORAGE_MANIFEST"
  grep -q 'nosharesock' "$STORAGE_MANIFEST"
  grep -q 'mfsymlinks' "$STORAGE_MANIFEST"
  grep -q 'actimeo=1' "$STORAGE_MANIFEST"
}

@test "_ensure_smb_storage_class warns when source missing" {
  unset SMB_SOURCE SMB_SERVER SMB_SHARE
  run _ensure_smb_storage_class
  [ "$status" -eq 1 ]
  [[ "$output" == *"SMB_SOURCE (or SMB_SERVER/SMB_SHARE) not set"* ]]
}

@test "test_cifs skips when disabled" {
  K3D_ENABLE_CIFS=0
  export K3D_ENABLE_CIFS
  run test_cifs 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping SMB smoke test (CIFS disabled)"* ]]
}

@test "test_cifs skips when smoke test not requested" {
  K3D_ENABLE_CIFS=1
  export K3D_ENABLE_CIFS
  _kubectl() {
    while [[ "$1" == "--quiet" ]]; do shift; done
    echo "$*" >>"$KUBECTL_LOG"
    if [[ "$1" == "get" && "$2" == "storageclass" ]]; then
      return 0
    fi
    return 0
  }
  export -f _kubectl

  run test_cifs 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping SMB smoke test (set SMB_SMOKE_TEST=1 to run)"* ]]
}

@test "test_cifs succeeds when wait conditions pass" {
  K3D_ENABLE_CIFS=1
  SMB_SMOKE_TEST=1
  export K3D_ENABLE_CIFS SMB_SMOKE_TEST
  SMOKE_MANIFEST="$BATS_TMPDIR/smoke.yaml"
  _kubectl() {
    while [[ "$1" == "--quiet" ]]; do shift; done
    while [[ "$1" == "-n" || "$1" == "--namespace" ]]; do
      shift 2 || break
    done
    echo "$*" >>"$KUBECTL_LOG"
    case "$1" in
      get)
        if [[ "$2" == "storageclass" ]]; then
          return 0
        fi
        ;;
      apply)
        cp "$3" "$SMOKE_MANIFEST"
        return 0
        ;;
      wait)
        return 0
        ;;
      delete)
        return 0
        ;;
    esac
    return 0
  }
  export -f _kubectl

  run test_cifs 0
  [ "$status" -eq 0 ]
  [ -f "$SMOKE_MANIFEST" ]
  grep -q 'PersistentVolumeClaim' "$SMOKE_MANIFEST"
  grep -q 'Pod' "$SMOKE_MANIFEST"
  wait_count=$(grep -c '^wait ' "$KUBECTL_LOG")
  [ "$wait_count" -eq 2 ]
  [[ "$output" == *"SMB smoke test pod became Ready using storage class 'smb-csi'."* ]]
}

@test "test_cifs handles failure gracefully" {
  K3D_ENABLE_CIFS=1
  SMB_SMOKE_TEST=1
  SMB_SMOKE_EXPECT=failure
  export K3D_ENABLE_CIFS SMB_SMOKE_TEST SMB_SMOKE_EXPECT
  _kubectl() {
    while [[ "$1" == "--quiet" ]]; do shift; done
    while [[ "$1" == "-n" || "$1" == "--namespace" ]]; do
      shift 2 || break
    done
    echo "$*" >>"$KUBECTL_LOG"
    case "$1" in
      get)
        return 0
        ;;
      apply)
        return 0
        ;;
      wait)
        return 1
        ;;
      delete)
        return 0
        ;;
    esac
    return 0
  }
  export -f _kubectl

  run test_cifs 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"SMB smoke test failure matches expected outcome."* ]]
}
