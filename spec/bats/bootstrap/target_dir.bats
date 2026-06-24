load helpers

setup() { in_tmpdir; }

# --- dir_creatable -----------------------------------------------------------

@test "dir_creatable accepts an existing writable directory" {
  run dir_creatable "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
}

@test "dir_creatable accepts a missing dir under a writable ancestor" {
  run dir_creatable "$BATS_TEST_TMPDIR/does/not/exist/yet"
  [ "$status" -eq 0 ]
}

@test "dir_creatable rejects a regular file" {
  touch "$BATS_TEST_TMPDIR/afile"
  run dir_creatable "$BATS_TEST_TMPDIR/afile"
  [ "$status" -ne 0 ]
}

@test "dir_creatable rejects a target whose nearest ancestor is not writable" {
  [ "$(id -u)" -ne 0 ] || skip "root bypasses directory write permissions"
  local ro="$BATS_TEST_TMPDIR/readonly"
  mkdir "$ro"
  chmod a-w "$ro"
  run dir_creatable "$ro/sub"
  chmod u+w "$ro" # restore so bats can clean up
  [ "$status" -ne 0 ]
}

# --- choose_target_dir (non-interactive branches) ----------------------------

@test "choose_target_dir extends an existing stack in place without prompting" {
  touch compose.yaml .env
  # Spy: if stack detection regressed and we fell through to the interactive
  # menu (reachable when bats runs under a real terminal), this stub fires and
  # picks option 3. Asserting it was never called keeps the short-circuit
  # honest — a plain TARGET_DIR=$PWD check passes for several branches.
  prompted=0
  prompt_line() {
    prompted=1
    printf '3'
  }
  choose_target_dir
  [ "$TARGET_DIR" = "$PWD" ]
  [ "$prompted" -eq 0 ]
}

@test "choose_target_dir uses the current dir when non-interactive" {
  HELIOS_ASSUME_YES=1
  # No SOLECTRUS stack running elsewhere (stub out detection so a real dev stack
  # on the host machine can't leak into this assertion).
  detect_running_solectrus_dir() { return 0; }
  choose_target_dir
  [ "$TARGET_DIR" = "$PWD" ]
}

# --- detect_running_solectrus_dir --------------------------------------------

@test "detect_running_solectrus_dir picks the working_dir of a solectrus image" {
  # Stub docker to emit one solectrus and one third-party container sharing the
  # same working_dir, plus an unrelated stack.
  docker() {
    cat <<'PS'
ghcr.io/solectrus/solectrus:latest|/opt/solectrus
influxdb:2.7|/opt/solectrus
ghcr.io/other/app:latest|/srv/other
PS
  }
  run detect_running_solectrus_dir
  [ "$status" -eq 0 ]
  [ "$output" = "/opt/solectrus" ]
}

@test "detect_running_solectrus_dir ignores a non-solectrus prefix" {
  docker() { printf '%s\n' "registry/mysolectrus/app:latest|/srv/foo"; }
  run detect_running_solectrus_dir
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- helios_running_in_dir ---------------------------------------------------

@test "helios_running_in_dir matches a running helios container by working_dir" {
  docker() {
    cat <<'PS'
ghcr.io/solectrus/helios:latest|/opt/solectrus
influxdb:2.7|/opt/solectrus
PS
  }
  run helios_running_in_dir "/opt/solectrus"
  [ "$status" -eq 0 ]
}

@test "helios_running_in_dir is false for a different dir" {
  docker() { printf '%s\n' "ghcr.io/solectrus/helios:latest|/opt/solectrus"; }
  run helios_running_in_dir "/srv/other"
  [ "$status" -ne 0 ]
}

@test "helios_running_in_dir is false when only non-helios solectrus images run" {
  docker() { printf '%s\n' "ghcr.io/solectrus/solectrus:latest|/opt/solectrus"; }
  run helios_running_in_dir "/opt/solectrus"
  [ "$status" -ne 0 ]
}

@test "helios_running_in_dir does not match a helios-foo sibling image" {
  docker() { printf '%s\n' "ghcr.io/solectrus/helios-foo:latest|/opt/solectrus"; }
  run helios_running_in_dir "/opt/solectrus"
  [ "$status" -ne 0 ]
}

# --- adopt_running_stack -----------------------------------------------------

@test "adopt_running_stack aborts unattended with guidance" {
  HELIOS_ASSUME_YES=1
  run adopt_running_stack "/opt/solectrus"
  [ "$status" -ne 0 ]
  [[ "$output" == *"/opt/solectrus"* ]]
  [[ "$output" == *"unattended"* ]]
}

@test "adopt_running_stack aborts on multiple running stacks" {
  HELIOS_ASSUME_YES=1
  run adopt_running_stack "$(printf '/opt/a\n/opt/b')"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Multiple"* ]]
}

@test "adopt_running_stack continues in place when already in the stack dir" {
  adopt_running_stack "$PWD"
  [ "$TARGET_DIR" = "$PWD" ]
}

@test "adopt_running_stack relocates without prompting when HELIOS already runs there" {
  helios_running_in_dir() { return 0; }
  # Spy: a prompt here would mean we misleadingly asked to "add" HELIOS to a
  # stack that already has it. It must never fire on this path.
  prompted=0
  prompt_yn() { prompted=1; return 0; }
  adopt_running_stack "/opt/solectrus"
  [ "$TARGET_DIR" = "/opt/solectrus" ]
  [ "$prompted" -eq 0 ]
}

@test "choose_target_dir adopts a running stack found elsewhere (non-interactive aborts)" {
  HELIOS_ASSUME_YES=1
  detect_running_solectrus_dir() { printf '%s\n' "/opt/solectrus"; }
  # Stack has no HELIOS yet, so adoption (not a short-circuit) is the path.
  helios_running_in_dir() { return 1; }
  run choose_target_dir
  [ "$status" -ne 0 ]
  [[ "$output" == *"/opt/solectrus"* ]]
}

# --- dir_menu_line -----------------------------------------------------------

@test "dir_menu_line marks the recommended entry" {
  run dir_menu_line 2 "$BATS_TEST_TMPDIR" recommended
  [ "$status" -eq 0 ]
  [[ "$output" == *"recommended"* ]]
}

@test "dir_menu_line flags an unavailable target needing root" {
  [ "$(id -u)" -ne 0 ] || skip "root bypasses directory write permissions"
  local ro="$BATS_TEST_TMPDIR/readonly"
  mkdir "$ro"
  chmod a-w "$ro"
  run dir_menu_line 1 "$ro/sub" recommended
  chmod u+w "$ro"
  [[ "$output" == *"unavailable"* ]]
}
