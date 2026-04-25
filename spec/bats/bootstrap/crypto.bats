load helpers

@test "generate_password produces 32 alphanumeric characters" {
  pw="$(generate_password)"
  [ "${#pw}" -eq 32 ]
  [[ "$pw" =~ ^[A-Za-z0-9]+$ ]]
}

@test "generate_password yields different output across calls" {
  [ "$(generate_password)" != "$(generate_password)" ]
}

@test "generate_secret produces 128 lowercase hex characters" {
  sk="$(generate_secret)"
  [ "${#sk}" -eq 128 ]
  [[ "$sk" =~ ^[0-9a-f]+$ ]]
}

@test "generate_secret yields different output across calls" {
  [ "$(generate_secret)" != "$(generate_secret)" ]
}
