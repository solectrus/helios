load helpers

setup() { in_tmpdir; }

@test "ensure_engine_version accepts a current engine" {
  docker() { echo "28.1.1"; }
  run ensure_engine_version
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓"* ]]
  [[ "$output" == *"28.1.1"* ]]
}

@test "ensure_engine_version accepts exactly the minimum" {
  docker() { echo "24.0.7"; }
  run ensure_engine_version
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓"* ]]
}

@test "ensure_engine_version rejects the Synology DSM 7.1 engine" {
  docker() { echo "20.10.3"; }
  run ensure_engine_version
  [ "$status" -ne 0 ]
  [[ "$output" == *"20.10.3 is too old"* ]]
  [[ "$output" == *"Container Manager"* ]]
}

@test "ensure_engine_version rejects a too-old minor within the same major" {
  MIN_ENGINE_VERSION="24.5"
  docker() { echo "24.2.0"; }
  run ensure_engine_version
  [ "$status" -ne 0 ]
  [[ "$output" == *"too old"* ]]
}

@test "ensure_engine_version passes when the version is unreadable" {
  docker() { return 1; }
  run ensure_engine_version
  [ "$status" -eq 0 ]
  [[ "$output" != *"✓"* ]]
}

@test "ensure_engine_version passes on a non-numeric version string" {
  docker() { echo "dev-build"; }
  run ensure_engine_version
  [ "$status" -eq 0 ]
  [[ "$output" != *"too old"* ]]
}
