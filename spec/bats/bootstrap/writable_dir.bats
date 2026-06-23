load helpers

setup() { in_tmpdir; }

@test "ensure_writable_dir prints a green check for a writable directory" {
  run ensure_writable_dir
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓"* ]]
  [[ "$output" == *"writable"* ]]
}

@test "ensure_writable_dir leaves no probe file behind" {
  run ensure_writable_dir
  [ "$status" -eq 0 ]
  run ls -A .
  [[ "$output" != *".helios-write-test"* ]]
}

@test "ensure_writable_dir fails and steers to an owned directory when not writable" {
  [ "$(id -u)" -ne 0 ] || skip "root bypasses directory write permissions"
  local ro="$BATS_TEST_TMPDIR/readonly"
  mkdir "$ro"
  chmod a-w "$ro"
  cd "$ro"
  run ensure_writable_dir
  chmod u+w "$ro" # restore so bats can clean up
  [ "$status" -ne 0 ]
  [[ "$output" == *"✗"* ]]
  [[ "$output" == *"not writable"* ]]
  [[ "$output" == *"mkdir ~/solectrus"* ]] # steer toward an owned directory
  [[ "$output" != *"sudo"* ]]              # never advise running as root
}
