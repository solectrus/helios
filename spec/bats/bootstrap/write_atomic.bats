load helpers

setup() { in_tmpdir; }

@test "write_atomic puts the producer's output in the target" {
  write_atomic target.txt printf 'hello\n'
  [ "$(cat target.txt)" = "hello" ]
}

@test "write_atomic gives a new file the mode a plain redirect would" {
  umask 022
  write_atomic target.txt printf 'x\n'
  [ "$(file_mode target.txt)" = "644" ]
}

@test "write_atomic keeps the mode of an existing file" {
  printf 'old\n' > target.txt
  chmod 600 target.txt
  write_atomic target.txt printf 'new\n'
  [ "$(file_mode target.txt)" = "600" ]
  [ "$(cat target.txt)" = "new" ]
}

@test "write_atomic leaves no temporary file behind" {
  write_atomic target.txt printf 'x\n'
  run ls -A .
  [[ "$output" != *".helios-tmp"* ]]
}

# The predictable `${COMPOSE_FILE}.tmp` this replaced could be pre-created as a
# symlink by anyone able to write the install directory, redirecting the write
# to a file of their choosing.
@test "write_atomic ignores a symlink planted under the old temp name" {
  printf 'secret\n' > elsewhere.txt
  ln -s elsewhere.txt target.txt.tmp
  write_atomic target.txt printf 'new\n'
  [ "$(cat target.txt)" = "new" ]
  [ "$(cat elsewhere.txt)" = "secret" ]
}

# The reason the content comes from a command and not from stdin: a failing
# producer must abort before the rename, leaving the previous file in place.
@test "write_atomic leaves the target untouched when the producer fails" {
  printf 'original\n' > target.txt
  run write_atomic target.txt cat missing-file
  [ "$status" -ne 0 ]
  [[ "$output" == *"unchanged"* ]]
  [ "$(cat target.txt)" = "original" ]
  run ls -A .
  [[ "$output" != *".helios-tmp"* ]]
}
