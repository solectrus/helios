load helpers

@test "emits a helios service block" {
  [[ "$(helios_service_yaml)" == *"helios:"* ]]
}

@test "declares ADMIN_PASSWORD and SECRET_KEY_BASE as env vars" {
  yaml="$(helios_service_yaml)"
  [[ "$yaml" == *"ADMIN_PASSWORD"* ]]
  [[ "$yaml" == *"SECRET_KEY_BASE"* ]]
}

@test "exposes the web UI on port 3999:3000" {
  [[ "$(helios_service_yaml)" == *"3999:3000"* ]]
}

@test "tags the container with the watchtower scope label" {
  [[ "$(helios_service_yaml)" == *"com.centurylinklabs.watchtower.scope=solectrus"* ]]
}

@test "honours the HELIOS_IMAGE override" {
  HELIOS_IMAGE="ghcr.io/example/custom:tag" run helios_service_yaml
  [ "$status" -eq 0 ]
  [[ "$output" == *"image: ghcr.io/example/custom:tag"* ]]
}
