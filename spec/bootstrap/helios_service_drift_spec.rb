# The bootstrap installer (bootstrap/install.sh) hard-codes the `helios` service
# block as static YAML — a curl|bash installer can't run Ruby. HELIOS's own
# Export::Compose generates the same block from Export::Services::Helios. The two
# must stay in sync (modulo YAML key order): if they drift, a freshly bootstrapped
# compose.yaml gets rewritten on HELIOS's first export, and any fix made on the
# Ruby side (timezone passthrough, labels, image, logging) silently never reaches
# fresh installs. This spec is the guard that keeps both definitions aligned.
RSpec.describe 'bootstrap installer ↔ Export::Compose drift' do # rubocop:disable RSpec/DescribeClass
  # The `helios:` block the installer would write, parsed into a Hash. Sourced in
  # a clean shell with HELIOS_IMAGE unset so we exercise the shipped default, not
  # whatever happens to be in this process's environment.
  let(:bootstrap_service) do
    yaml = bootstrap_eval('helios_service_yaml', env: 'unset HELIOS_IMAGE')
    YAML.safe_load(yaml).fetch('helios')
  end

  # The canonical `helios:` block HELIOS itself exports in plain-port mode — the
  # exact deployment shape the bootstrap installer creates (no Traefik, plain
  # host port). Helios is enabled outside development, so it renders under test.
  let(:canonical_service) do
    with_config_yaml
    config = Configuration.current
    config.update('system', { 'installation_date' => '2024-01-15', 'timezone' => 'Europe/Berlin' })
    raise 'expected plain-port (no Traefik) mode for this comparison' if Export::Services::Traefik.enabled?(config)

    YAML.safe_load(Export::Compose.new(config).to_yaml).fetch('services').fetch('helios')
  end

  it 'ships the same default image the export recommends' do
    expect(bootstrap_service.fetch('image')).to eq(DockerImages.current(:HELIOS))
  end

  it 'matches the canonical helios service block exactly' do
    # Hash equality ignores key order but compares array order (environment,
    # volumes, labels), so a reordered env var or a missing TZ entry fails here.
    expect(bootstrap_service).to eq(canonical_service)
  end
end
