load helpers

# Source the installer in a clean shell and print the resolved ref and image.
resolve() {
  env -u HELIOS_REF -u HELIOS_IMAGE "$@" \
    bash -c "source '$REPO_ROOT/bootstrap/install.sh'; echo \"\$HELIOS_REF \$HELIOS_IMAGE\""
}

@test "the stable channel follows main and the latest image" {
  run resolve -u HELIOS_CHANNEL
  [ "$output" = "main ghcr.io/solectrus/helios:latest" ]
}

@test "the develop channel follows develop and the develop image" {
  run resolve HELIOS_CHANNEL=develop
  [ "$output" = "develop ghcr.io/solectrus/helios:develop" ]
}

@test "HELIOS_REF and HELIOS_IMAGE override the channel" {
  run resolve HELIOS_CHANNEL=develop HELIOS_REF=feature HELIOS_IMAGE=example/helios:tag
  [ "$output" = "feature example/helios:tag" ]
}
