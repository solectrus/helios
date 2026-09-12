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

# --- volumes across the project rename ---------------------------------------

# A stack in ~/mydir without `name:`: Compose derives the project name from
# the directory and prefixes every unnamed volume with it (and the default
# network, which holds no data), while an external or explicitly named volume
# keeps its name. The mock returns the canonical config the real CLI prints.
@test "refuses the rename when a volume name derives from the project name" {
  printf 'services:\n  db:\n    image: x\n' > "$COMPOSE_FILE"
  docker() {
    case "$*" in
      *" ps "*) return 0 ;;
      *) printf 'name: mydir\nnetworks:\n  default:\n    name: mydir_default\nvolumes:\n  ext:\n    name: keep\n    external: true\n  pg:\n    name: mydir_pg\n' ;;
    esac
  }

  run ensure_project_name

  [ "$status" -ne 0 ]
  [[ "$output" == *"mydir_pg"* ]]
  [[ "$output" != *"keep"* ]]
  [[ "$output" != *"mydir_default"* ]]
  run head -n1 "$COMPOSE_FILE"
  [ "$output" = "services:" ]
}

@test "renames when every volume is external or carries its own name" {
  printf 'services:\n  db:\n    image: x\n' > "$COMPOSE_FILE"
  docker() {
    case "$*" in
      *" ps "*) return 0 ;;
      *) printf 'name: mydir\nnetworks:\n  default:\n    name: mydir_default\nvolumes:\n  ext:\n    name: keep\n    external: true\n' ;;
    esac
  }

  run ensure_project_name

  [ "$status" -eq 0 ]
  run head -n1 "$COMPOSE_FILE"
  [ "$output" = "name: solectrus" ]
}

# --- compose.yaml rewrites ---------------------------------------------------

# Field 1 of `ls -l` is the mode string on both GNU and BSD.
file_mode() {
  # shellcheck disable=SC2012
  ls -l "$1" | awk 'NR==1 {print substr($1,1,10)}'
}

@test "a rewritten compose.yaml has the mode a fresh install writes" {
  printf 'services:\n  dashboard:\n    image: x\n' > "$COMPOSE_FILE"
  chmod 644 "$COMPOSE_FILE"
  docker() { printf 'name: solectrus\n'; }

  ensure_project_name
  adopted_mode="$(file_mode "$COMPOSE_FILE")"

  rm -f "$COMPOSE_FILE"
  write_compose_fresh

  [ "$adopted_mode" = "$(file_mode "$COMPOSE_FILE")" ]
}

@test "a rewrite leaves no temp file behind" {
  printf 'services:\n  dashboard:\n    image: x\n' > "$COMPOSE_FILE"
  docker() { printf 'name: solectrus\n'; }

  ensure_project_name

  [ ! -e "${COMPOSE_FILE}.tmp" ]
}
