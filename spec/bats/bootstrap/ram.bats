load helpers

setup() { in_tmpdir; }

@test "total_ram_mb returns 0 on systems without /proc/meminfo" {
  if [ -r /proc/meminfo ]; then
    skip "needs a system without /proc/meminfo (macOS, BSD)"
  fi

  result="$(total_ram_mb)"
  [ "$result" = "0" ]
}

@test "total_ram_mb returns a positive integer on Linux" {
  if [ ! -r /proc/meminfo ]; then
    skip "needs /proc/meminfo to read MemTotal"
  fi

  result="$(total_ram_mb)"
  [[ "$result" =~ ^[0-9]+$ ]]
  [ "$result" -gt 0 ]
}

@test "ensure_ram prints a green check on pass" {
  total_ram_mb() { echo 4096; }
  run ensure_ram
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓"* ]]
  [[ "$output" == *"4096 MB"* ]]
}

@test "ensure_ram is silent when /proc/meminfo is unreadable (returns 0)" {
  total_ram_mb() { echo 0; }
  run ensure_ram
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ensure_ram warns and continues when user accepts" {
  total_ram_mb() { echo 1500; }
  prompt_yn() { return 0; }
  run ensure_ram
  [ "$status" -eq 0 ]
  [[ "$output" == *"⚠"* ]]
  [[ "$output" == *"MB"* ]]
}

@test "ensure_ram exits cleanly when user declines warning" {
  total_ram_mb() { echo 1500; }
  prompt_yn() { return 1; }
  run ensure_ram
  [ "$status" -eq 0 ]
  [[ "$output" == *"⚠"* ]]
  [[ "$output" == *"Aborted"* ]]
}

@test "ensure_ram passes at exactly the recommended threshold" {
  total_ram_mb() { echo "$RECOMMENDED_RAM_MB"; }
  run ensure_ram
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓"* ]]
}

@test "ensure_ram dies hard below the abort threshold" {
  total_ram_mb() { echo 512; }
  run ensure_ram
  [ "$status" -ne 0 ]
  [[ "$output" == *"✗"* ]]
  [[ "$output" == *"Add more RAM"* ]]
}
