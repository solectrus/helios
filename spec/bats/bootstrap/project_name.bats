load helpers

setup() {
  in_tmpdir
  COMPOSE_FILE="compose.yaml"
}

@test "ensure_project_name reports why 'docker compose config' failed" {
  docker() {
    echo "yaml: line 3: mapping values are not allowed in this context" >&2
    return 1
  }
  run ensure_project_name
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not be parsed"* ]]
  [[ "$output" == *"mapping values are not allowed"* ]]
  [[ "$output" == *"Fix compose.yaml manually"* ]]
}

@test "ensure_project_name ignores Compose warnings on stderr" {
  docker() {
    echo 'WARN[0000] the attribute `version` is obsolete' >&2
    printf 'name: solectrus\nservices:\n  app:\n    image: busybox\n'
  }
  printf 'name: solectrus\nservices:\n  app:\n    image: busybox\n' > "$COMPOSE_FILE"
  run ensure_project_name
  [ "$status" -eq 0 ]
}

@test "ensure_project_name rejects a foreign top-level name" {
  docker() { printf 'name: myproject\nservices:\n  app:\n    image: busybox\n'; }
  printf 'name: myproject\nservices:\n  app:\n    image: busybox\n' > "$COMPOSE_FILE"
  run ensure_project_name
  [ "$status" -ne 0 ]
  [[ "$output" == *"HELIOS requires 'solectrus'"* ]]
}

@test "ensure_project_name prepends the project name when absent" {
  # No top-level `name:` in the file — Compose falls back to the directory name.
  printf 'services:\n  app:\n    image: busybox\n' > "$COMPOSE_FILE"
  docker() {
    case "$*" in
      *" ps "*) return 0 ;;
      *) printf 'name: solectrus\nservices:\n  app:\n    image: busybox\n' ;;
    esac
  }
  run ensure_project_name
  [ "$status" -eq 0 ]
  run head -n1 "$COMPOSE_FILE"
  [ "$output" = "name: solectrus" ]
}
