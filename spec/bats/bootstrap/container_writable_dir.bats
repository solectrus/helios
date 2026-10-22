load helpers

setup() { in_tmpdir; }

@test "ensure_container_writable_dir prints a green check when a container can write" {
  docker() { return 0; }
  run ensure_container_writable_dir
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓"* ]]
  [[ "$output" == *"Services can write"* ]]
}

@test "ensure_container_writable_dir pulls the image, then mounts the probe folder itself" {
  docker() { echo "$*" >> "$BATS_TEST_TMPDIR/docker.args"; }
  run ensure_container_writable_dir
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$BATS_TEST_TMPDIR/docker.args")" = "pull $HELIOS_IMAGE" ]
  grep -q -- "-v $PWD/.helios-write-probe.*:/probe " "$BATS_TEST_TMPDIR/docker.args"
}

@test "ensure_container_writable_dir explains the ACL and continues when the user accepts" {
  docker() {
    [ "$1" = pull ] && return 0
    echo "mkdir: can't create directory '/probe/x': Permission denied"
    return 1
  }
  prompt_yn() { return 0; }
  run ensure_container_writable_dir
  [ "$status" -eq 0 ]
  [[ "$output" == *"⚠"* ]]
  [[ "$output" == *"shared folder"* ]]
  [[ "$output" == *"Permission denied"* ]]
}

@test "ensure_container_writable_dir exits cleanly and leaves no probe folder when the user declines" {
  docker() { [ "$1" = pull ]; }
  prompt_yn() { return 1; }
  run ensure_container_writable_dir
  [ "$status" -eq 0 ]
  [[ "$output" == *"Aborted"* ]]
  [ -z "$(ls -A .)" ]
}
