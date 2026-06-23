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
  choose_target_dir
  [ "$TARGET_DIR" = "$PWD" ]
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
