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

@test "treats empty value as missing and appends a derived secret" {
  printf 'ADMIN_PASSWORD=\n' > "$ENV_FILE"

  ensure_helios_secrets

  grep -qE '^ADMIN_PASSWORD=[0-9a-f]{32}$' "$ENV_FILE"
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
