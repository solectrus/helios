load helpers

setup() { in_tmpdir; }

@test "appends both secrets when .env has neither (collector-only stack)" {
  cat > "$ENV_FILE" <<EOF
TZ=Europe/Berlin
INFLUX_TOKEN=remote
EOF

  ensure_helios_secrets

  grep -qE '^ADMIN_PASSWORD=.{32}$' "$ENV_FILE"
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

@test "treats empty value as missing and appends a fresh secret" {
  printf 'ADMIN_PASSWORD=\n' > "$ENV_FILE"

  ensure_helios_secrets

  grep -qE '^ADMIN_PASSWORD=.{32}$' "$ENV_FILE"
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
