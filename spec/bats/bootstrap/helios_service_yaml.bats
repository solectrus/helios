load helpers

@test "emits a helios service block" {
  [[ "$(helios_service_yaml)" == *"helios:"* ]]
}

@test "declares ADMIN_PASSWORD and SECRET_KEY_BASE as env vars" {
  yaml="$(helios_service_yaml)"
  [[ "$yaml" == *"ADMIN_PASSWORD"* ]]
  [[ "$yaml" == *"SECRET_KEY_BASE"* ]]
}

# TZ passes the host timezone through to the container; without it HELIOS's OS
# clock runs UTC. Canonical export lists it first (see Export::Services::Helios),
# so the bootstrap block must too — enforced rigorously by the Ruby drift spec.
@test "passes TZ through as an env var" {
  [[ "$(helios_service_yaml)" == *"- TZ"* ]]
}

@test "exposes the web UI on port 3999:3000" {
  [[ "$(helios_service_yaml)" == *"3999:3000"* ]]
}

@test "tags the container with the watchtower scope label" {
  [[ "$(helios_service_yaml)" == *"com.centurylinklabs.watchtower.scope=solectrus"* ]]
}

@test "bind-mounts the host cgroup read-only for HostStats" {
  [[ "$(helios_service_yaml)" == *"/sys/fs/cgroup:/host/sys/fs/cgroup:ro"* ]]
}

@test "honours the HELIOS_IMAGE override" {
  HELIOS_IMAGE="ghcr.io/example/custom:tag" run helios_service_yaml
  [ "$status" -eq 0 ]
  [[ "$output" == *"image: ghcr.io/example/custom:tag"* ]]
}
