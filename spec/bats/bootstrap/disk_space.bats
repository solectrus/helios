load helpers

setup() { in_tmpdir; }

# free_mb is exercised against an actual df call here — we only assert
# it returns a non-negative integer for an existing path. The threshold
# logic is covered against ensure_disk_space using a stubbed free_mb
# (which returns megabytes).

@test "free_mb returns a non-negative integer for an existing path" {
  result="$(free_mb "$(pwd)")"
  [[ "$result" =~ ^[0-9]+$ ]]
}

@test "free_mb returns 0 for a nonexistent path" {
  result="$(free_mb "/this/path/does/not/exist/$RANDOM$RANDOM")"
  [ "$result" = "0" ]
}

@test "format_space stays in MB below 1 GB" {
  [ "$(format_space 492)" = "492 MB" ]
  [ "$(format_space 1023)" = "1023 MB" ]
}

@test "format_space switches to GB at or above 1 GB" {
  [ "$(format_space 1024)" = "1 GB" ]
  [ "$(format_space 5120)" = "5 GB" ]
}

@test "ensure_disk_space prints a green check on pass" {
  free_mb() { echo $((100 * 1024)); }
  run ensure_disk_space
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓"* ]]
  [[ "$output" == *"100 GB free"* ]]
}

@test "ensure_disk_space passes at exactly the recommended threshold" {
  free_mb() { echo $((RECOMMENDED_DISK_GB * 1024)); }
  run ensure_disk_space
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓"* ]]
}

@test "ensure_disk_space warns and continues when user accepts (fresh)" {
  free_mb() { echo $((MIN_DISK_GB * 1024)); }
  prompt_yn() { return 0; }
  run ensure_disk_space fresh
  [ "$status" -eq 0 ]
  [[ "$output" == *"⚠"* ]]
  [[ "$output" == *"recommended"* ]]
}

@test "ensure_disk_space exits cleanly when user declines warning (fresh)" {
  free_mb() { echo $((MIN_DISK_GB * 1024)); }
  prompt_yn() { return 1; }
  run ensure_disk_space fresh
  [ "$status" -eq 0 ]
  [[ "$output" == *"⚠"* ]]
  [[ "$output" == *"Aborted"* ]]
}

@test "ensure_disk_space passes silently between MIN and RECOMMENDED in existing mode" {
  free_mb() { echo $((MIN_DISK_GB * 1024)); }
  run ensure_disk_space existing
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓"* ]]
  [[ "$output" != *"⚠"* ]]
}

@test "ensure_disk_space dies hard below the abort threshold" {
  free_mb() { echo 0; }
  run ensure_disk_space
  [ "$status" -ne 0 ]
  [[ "$output" == *"✗"* ]]
  [[ "$output" == *"Free up disk space"* ]]
}

@test "ensure_disk_space reports sub-GB free space in MB, not a misleading 0 GB" {
  free_mb() { echo 492; }
  run ensure_disk_space
  [ "$status" -ne 0 ]
  [[ "$output" == *"✗"* ]]
  [[ "$output" == *"492 MB free"* ]]
  [[ "$output" != *"0 GB free"* ]]
}

@test "ensure_disk_space picks the tighter filesystem when the Docker root is smaller" {
  docker_root_dir() { echo /volume1/@docker; }

  free_mb() {
    case "$1" in
      /volume1/@docker) echo 0 ;;
      *) echo $((50 * 1024)) ;;
    esac
  }

  run ensure_disk_space
  [ "$status" -ne 0 ]
  [[ "$output" == *"0 MB free at /volume1/@docker"* ]]
}

@test "ensure_disk_space ignores the Docker root when it cannot be determined" {
  docker_root_dir() { return 1; }
  free_mb() { echo $((50 * 1024)); }

  run ensure_disk_space
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓"* ]]
  [[ "$output" == *"50 GB free at $(pwd)"* ]]
}

@test "docker_root_dir reports the path the daemon actually uses" {
  docker() { echo "$PWD"; }

  result="$(docker_root_dir)"
  [ "$result" = "$PWD" ]
}

@test "docker_root_dir fails when the reported path does not exist here" {
  docker() { echo "/this/path/does/not/exist/$RANDOM$RANDOM"; }

  run docker_root_dir
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "docker_root_dir fails when docker reports nothing" {
  docker() { return 1; }

  run docker_root_dir
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}
