load helpers

setup() { in_tmpdir; }

@test "ensure_compose_v2 accepts a v2 plugin" {
  docker() { echo "2.29.1"; }
  run ensure_compose_v2
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓"* ]]
  [[ "$output" == *"2.29.1"* ]]
}

@test "ensure_compose_v2 accepts a version prefixed with 'v'" {
  docker() { echo "v2.0.0"; }
  run ensure_compose_v2
  [ "$status" -eq 0 ]
  [[ "$output" == *"2.0.0"* ]]
  [[ "$output" != *"vv"* ]]
}

@test "ensure_compose_v2 rejects a v1 plugin" {
  docker() { echo "1.29.2"; }
  run ensure_compose_v2
  [ "$status" -ne 0 ]
  [[ "$output" == *"✗"* ]]
  [[ "$output" == *"docker-compose-plugin"* ]]
}

@test "ensure_compose_v2 aborts when 'docker compose' is missing" {
  docker() {
    echo "docker: 'compose' is not a docker command." >&2
    return 1
  }
  run ensure_compose_v2
  [ "$status" -ne 0 ]
  [[ "$output" == *"Compose v2"* ]]
  [[ "$output" == *"docs.docker.com/compose/install"* ]]
}

@test "ensure_compose_v2 aborts on unparseable version output" {
  docker() { echo "unknown"; }
  run ensure_compose_v2
  [ "$status" -ne 0 ]
  [[ "$output" != *"✓"* ]]
}
