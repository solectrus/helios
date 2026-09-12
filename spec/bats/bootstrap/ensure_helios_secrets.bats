load helpers

setup() { in_tmpdir; }

@test "appends both secrets when .env has neither (collector-only stack)" {
  cat > "$ENV_FILE" <<EOF
TZ=Europe/Berlin
INFLUX_TOKEN=remote
EOF

  ensure_helios_secrets

  grep -qE '^ADMIN_PASSWORD=[0-9a-f]{32}$' "$ENV_FILE"
  grep -qE '^SECRET_KEY_BASE=.{128}$' "$ENV_FILE"
  grep -qE '^TZ=Europe/Berlin$' "$ENV_FILE"
  grep -qE '^INFLUX_TOKEN=remote$' "$ENV_FILE"
}

@test "is idempotent — second run does not change .env" {
  : > "$ENV_FILE"
  ensure_helios_secrets
  before="$(shasum "$ENV_FILE")"

  ensure_helios_secrets
  after="$(shasum "$ENV_FILE")"

  [ "$before" = "$after" ]
}

@test "preserves existing ADMIN_PASSWORD and only fills SECRET_KEY_BASE" {
  printf 'ADMIN_PASSWORD=existing-pw\n' > "$ENV_FILE"

  ensure_helios_secrets

  grep -qE '^ADMIN_PASSWORD=existing-pw$' "$ENV_FILE"
  grep -qE '^SECRET_KEY_BASE=.{128}$' "$ENV_FILE"
  [ "$(grep -cE '^ADMIN_PASSWORD=' "$ENV_FILE")" -eq 1 ]
}

@test "treats empty value as missing and does not keep the key twice" {
  printf 'ADMIN_PASSWORD=\n' > "$ENV_FILE"

  ensure_helios_secrets

  grep -qE '^ADMIN_PASSWORD=[0-9a-f]{32}$' "$ENV_FILE"
  [ "$(grep -cE '^ADMIN_PASSWORD=' "$ENV_FILE")" -eq 1 ]
}

@test "replaces a blank SECRET_KEY_BASE= instead of adding the key twice" {
  printf 'TZ=Europe/Berlin\nSECRET_KEY_BASE=\nINFLUX_TOKEN=abc\n' > "$ENV_FILE"

  ensure_helios_secrets

  [ "$(grep -cE '^SECRET_KEY_BASE=' "$ENV_FILE")" -eq 1 ]
  grep -qE '^SECRET_KEY_BASE=.{128}$' "$ENV_FILE"
  grep -qE '^TZ=Europe/Berlin$' "$ENV_FILE"
  grep -qE '^INFLUX_TOKEN=abc$' "$ENV_FILE"

  # The password must derive from the value just written, not from the blank
  # line (which used to stay in front of it and abort the install).
  secret="$(grep -E '^SECRET_KEY_BASE=' "$ENV_FILE" | cut -d= -f2-)"
  expected="$(printf '%s' "$secret" | openssl dgst -sha256 | awk '{print substr($NF,1,32)}')"
  grep -qE "^ADMIN_PASSWORD=${expected}$" "$ENV_FILE"
}

@test "skips a blank SECRET_KEY_BASE= line in favor of the value below it" {
  printf 'SECRET_KEY_BASE=\nSECRET_KEY_BASE=real-key\n' > "$ENV_FILE"

  ensure_helios_secrets

  expected="$(printf '%s' 'real-key' | openssl dgst -sha256 | awk '{print substr($NF,1,32)}')"
  grep -qE "^ADMIN_PASSWORD=${expected}$" "$ENV_FILE"
}

@test "exposes generated ADMIN_PASSWORD via GENERATED_ADMIN_PASSWORD" {
  : > "$ENV_FILE"

  ensure_helios_secrets

  [ -n "$GENERATED_ADMIN_PASSWORD" ]
  [ "${#GENERATED_ADMIN_PASSWORD}" -eq 32 ]
  grep -qE "^ADMIN_PASSWORD=${GENERATED_ADMIN_PASSWORD}$" "$ENV_FILE"
}

@test "leaves GENERATED_ADMIN_PASSWORD empty when ADMIN_PASSWORD already exists" {
  printf 'ADMIN_PASSWORD=existing-pw\n' > "$ENV_FILE"

  ensure_helios_secrets

  [ -z "$GENERATED_ADMIN_PASSWORD" ]
}

@test "derives ADMIN_PASSWORD deterministically from SECRET_KEY_BASE" {
  printf 'SECRET_KEY_BASE=my-secret-key-base\n' > "$ENV_FILE"

  ensure_helios_secrets

  # sha256("my-secret-key-base") = 9bd31efce3c5edabc8c7f1b4b1b1d6a4ce28e3...
  # The derivation must agree with HELIOS' ConfigSchema::SYSTEM_DEFAULTS so a
  # real adoption and the importer/exporter roundtrip arrive at the same
  # password.
  expected="$(printf '%s' 'my-secret-key-base' | shasum -a 256 | awk '{print substr($1,1,32)}')"
  grep -qE "^ADMIN_PASSWORD=${expected}$" "$ENV_FILE"
}

@test "re-running on identical SECRET_KEY_BASE yields the same ADMIN_PASSWORD" {
  printf 'SECRET_KEY_BASE=stable-key\n' > "$ENV_FILE"
  ensure_helios_secrets
  first_pw="$GENERATED_ADMIN_PASSWORD"

  # Recreate the input verbatim and re-derive — must yield the same password.
  printf 'SECRET_KEY_BASE=stable-key\n' > "$ENV_FILE"
  ensure_helios_secrets
  second_pw="$GENERATED_ADMIN_PASSWORD"

  [ "$first_pw" = "$second_pw" ]
}

@test "a different SECRET_KEY_BASE yields a different ADMIN_PASSWORD" {
  printf 'SECRET_KEY_BASE=key-one\n' > "$ENV_FILE"
  ensure_helios_secrets
  first_pw="$GENERATED_ADMIN_PASSWORD"

  printf 'SECRET_KEY_BASE=key-two\n' > "$ENV_FILE"
  ensure_helios_secrets
  second_pw="$GENERATED_ADMIN_PASSWORD"

  [ "$first_pw" != "$second_pw" ]
}

@test "reads only the first SECRET_KEY_BASE when the file holds several" {
  printf 'SECRET_KEY_BASE=first-key\nSECRET_KEY_BASE=second-key\n' > "$ENV_FILE"

  ensure_helios_secrets

  expected="$(printf '%s' 'first-key' | openssl dgst -sha256 | awk '{print substr($NF,1,32)}')"
  grep -qE "^ADMIN_PASSWORD=${expected}$" "$ENV_FILE"
}

@test "appends cleanly to a .env without a trailing newline" {
  # A .env whose last line has no newline would otherwise get the new
  # assignment glued onto it, corrupting both variables — and leaving
  # SECRET_KEY_BASE unfindable, so the password fell back to sha256("").
  printf 'TZ=Europe/Berlin\nINFLUX_TOKEN=abc' > "$ENV_FILE"

  ensure_helios_secrets

  # sha256("") truncated to 32 chars — the password a lost SECRET_KEY_BASE
  # would produce. It must never appear.
  if grep -qE '^ADMIN_PASSWORD=e3b0c44298fc1c149afbf4c8996fb924$' "$ENV_FILE"; then
    echo "ADMIN_PASSWORD fell back to sha256 of the empty string" >&2
    return 1
  fi

  grep -qE '^INFLUX_TOKEN=abc$' "$ENV_FILE"
  grep -qE '^SECRET_KEY_BASE=.{128}$' "$ENV_FILE"
  grep -qE '^ADMIN_PASSWORD=[0-9a-f]{32}$' "$ENV_FILE"
}

@test "refuses to derive a password from an empty SECRET_KEY_BASE" {
  printf 'SECRET_KEY_BASE=\n' > "$ENV_FILE"

  run derive_admin_password

  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not read SECRET_KEY_BASE"* ]]
}

@test "restricts .env to its owner before the secrets are written" {
  printf 'TZ=Europe/Berlin\n' > "$ENV_FILE"
  chmod 644 "$ENV_FILE"
  # Capture the mode at the moment the first secret is produced, right before
  # it lands in the file. A chmod that ran afterwards would fail this.
  generate_secret() {
    # shellcheck disable=SC2012
    ls -l "$ENV_FILE" | awk 'NR==1 {print substr($1,1,10)}' > mode_at_write
    openssl rand -hex 64
  }

  ensure_helios_secrets

  [ "$(cat mode_at_write)" = "-rw-------" ]
}

@test "restricts .env to 0600 after adding secrets" {
  printf 'TZ=Europe/Berlin\n' > "$ENV_FILE"
  chmod 644 "$ENV_FILE"

  ensure_helios_secrets

  # Field 1 of `ls -l` is the mode string on both GNU and BSD.
  # shellcheck disable=SC2012
  [ "$(ls -l "$ENV_FILE" | awk 'NR==1 {print substr($1,1,10)}')" = "-rw-------" ]
}
