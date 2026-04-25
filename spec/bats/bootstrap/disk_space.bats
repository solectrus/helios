load helpers

setup() { in_tmpdir; }

# free_gb is exercised against an actual df call here — we only assert
# it returns a non-negative integer for an existing path. The threshold
# logic is covered against ensure_disk_space using a stubbed free_gb.

@test "free_gb returns a non-negative integer for an existing path" {
  result="$(free_gb "$(pwd)")"
  [[ "$result" =~ ^[0-9]+$ ]]
}

@test "free_gb returns 0 for a nonexistent path" {
  result="$(free_gb "/this/path/does/not/exist/$RANDOM$RANDOM")"
  [ "$result" = "0" ]
}

@test "ensure_disk_space prints a green check on pass" {
  free_gb() { echo 100; }
  run ensure_disk_space
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓"* ]]
  [[ "$output" == *"100 GB free"* ]]
}

@test "ensure_disk_space passes at exactly the minimum threshold" {
  free_gb() { echo "$MIN_DISK_GB"; }
  run ensure_disk_space
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓"* ]]
}

@test "ensure_disk_space dies hard below the abort threshold" {
  free_gb() { echo 3; }
  run ensure_disk_space
  [ "$status" -ne 0 ]
  [[ "$output" == *"✗"* ]]
  [[ "$output" == *"Free up disk space"* ]]
}

@test "ensure_disk_space picks the tighter filesystem when /var/lib/docker is smaller" {
  if [ ! -d /var/lib/docker ]; then
    skip "needs /var/lib/docker present to exercise the cross-filesystem branch"
  fi

  free_gb() {
    case "$1" in
      /var/lib/docker) echo 4 ;;
      *) echo 50 ;;
    esac
  }

  run ensure_disk_space
  [ "$status" -ne 0 ]
  [[ "$output" == *"4 GB free at /var/lib/docker"* ]]
}
