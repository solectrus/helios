load helpers

setup() { in_tmpdir; }

@test "wait_for_helios reports success once the endpoint answers" {
  # Stubbing curl() also makes `command -v curl` succeed, so the guard passes.
  curl() { return 0; }
  run wait_for_helios
  [ "$status" -eq 0 ]
  [[ "$output" == *"up and reachable"* ]]
}

@test "wait_for_helios warns but does not fail when the endpoint never answers" {
  curl() { return 1; }
  sleep() { :; } # don't actually wait out the poll loop
  run wait_for_helios
  [ "$status" -eq 0 ]
  [[ "$output" == *"still starting"* ]]
}

@test "wait_for_helios is a no-op without curl" {
  # Hide curl from `command -v` by stubbing the builtin used to detect it.
  command() { return 1; }
  run wait_for_helios
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "wait_for_helios probes the advertised URL, not localhost" {
  helios_url() { printf 'http://192.0.2.7:3999'; }
  curl() { printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/curl-args"; return 0; }
  wait_for_helios >/dev/null
  grep -q 'http://192.0.2.7:3999/up' "$BATS_TEST_TMPDIR/curl-args"
  ! grep -q localhost "$BATS_TEST_TMPDIR/curl-args"
}

@test "wait_for_helios falls back to the loopback when the host is unknown" {
  helios_url() { printf 'http://<your-host>:3999'; }
  curl() { printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/curl-args"; return 0; }
  wait_for_helios >/dev/null
  grep -q 'http://localhost:3999/up' "$BATS_TEST_TMPDIR/curl-args"
}
