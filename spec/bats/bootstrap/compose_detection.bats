load helpers

setup() { in_tmpdir; }

@test "prefers compose.yaml over docker-compose.yml" {
  touch docker-compose.yml compose.yaml
  [ "$(detect_compose_file)" = "compose.yaml" ]
}

@test "falls through to compose.yml when compose.yaml is absent" {
  touch compose.yml docker-compose.yaml
  [ "$(detect_compose_file)" = "compose.yml" ]
}

@test "falls through to docker-compose.yaml" {
  touch docker-compose.yaml docker-compose.yml
  [ "$(detect_compose_file)" = "docker-compose.yaml" ]
}

@test "falls through to docker-compose.yml as last resort" {
  touch docker-compose.yml
  [ "$(detect_compose_file)" = "docker-compose.yml" ]
}

@test "exits non-zero with no output when no candidate exists" {
  run detect_compose_file
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}
