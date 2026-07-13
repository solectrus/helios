# Contract test between the exporters and the services they configure.
#
# Bugs where HELIOS wrote one name and the service read another (a hardcoded
# INFLUX_MEASUREMENT_SENEC that senec-collector never reads, sensor mappings
# under names csv-importer ignores, a missing MQTT_PORT) were all invisible
# drift: nothing failed loudly, the services just fell back to their defaults.
#
# So check the exported compose.yaml of every import scenario against
# spec/fixtures/service_env_contract.yml, which records the variables each
# service actually reads — taken from its source, not its documentation.
RSpec.describe 'Service env contract' do
  # The exporter's own output, one compose.yaml per scenario — a far wider set
  # of configurations than a hand-built one would cover.
  def self.scenarios
    Pathname.glob(Rails.root.join('spec/fixtures/import_scenarios/**/compose.yaml')).sort
  end

  def self.scenario_name(compose_path)
    compose_path.dirname.relative_path_from(Rails.root.join('spec/fixtures/import_scenarios'))
  end

  let(:contract) { YAML.safe_load_file(Rails.root.join('spec/fixtures/service_env_contract.yml')) }

  # Only HELIOS-generated services. Everything else in a scenario's compose.yaml
  # is an unmanaged service passed through verbatim from the user's stack
  # (tibber-collector, nginx, …) — not ours to contract-check.
  let(:managed_names) { Export::Compose::SERVICE_ORDER.map(&:service_name) }

  def managed_services(compose_path)
    services = YAML.safe_load_file(compose_path, aliases: true)['services'] || {}
    services.slice(*managed_names)
  end

  def emitted_vars(service_config)
    Array(service_config['environment']).map { |entry| entry.to_s.split('=', 2).first }
  end

  # Variables an entry resolves against .env: a bare `- FOO`, or the reference
  # in `- FOO=${BAR}`. Inline literals (`- FOO=influxdb`) need no .env entry.
  def referenced_vars(service_config)
    Array(service_config['environment']).flat_map do |entry|
      name, value = entry.to_s.split('=', 2)
      next [name] if value.nil?

      value.scan(/\$\{([A-Z_][A-Z0-9_]*)\}/).flatten
    end
  end

  def read_by?(service, var)
    entry = contract.fetch(service)
    return true if Array(entry['reads']).include?(var)
    return true if Array(entry['tolerated']).include?(var)

    Array(entry['patterns']).any? { |pattern| File.fnmatch?(pattern, var) }
  end

  def env_vars(compose_path)
    compose_path.dirname.join('.env').readlines.filter_map do |line|
      line.split('=', 2).first&.strip if line.match?(/\A[A-Z_][A-Z0-9_]*=/)
    end
  end

  it 'covers every managed service' do
    expect(managed_names - contract.keys).to be_empty,
                                             'Managed service without a contract entry — add it to ' \
                                             'spec/fixtures/service_env_contract.yml'
  end

  describe 'every variable an exporter emits is one the service reads' do
    scenarios.each do |compose_path|
      it "holds for #{scenario_name(compose_path)}" do
        unknown = managed_services(compose_path).flat_map do |name, config|
          emitted_vars(config).reject { |var| read_by?(name, var) }.map { |var| "#{name}: #{var}" }
        end

        expect(unknown).to be_empty,
                           "Exported variables the service never reads (renamed, or a typo):\n" \
                           "#{unknown.join("\n")}"
      end
    end
  end

  describe 'every variable a service requires is emitted' do
    scenarios.each do |compose_path|
      it "holds for #{scenario_name(compose_path)}" do
        missing = managed_services(compose_path).flat_map do |name, config|
          required = Array(contract.fetch(name)['requires'])
          (required - emitted_vars(config)).map { |var| "#{name}: #{var}" }
        end

        expect(missing).to be_empty,
                           "Required variables the service never receives:\n#{missing.join("\n")}"
      end
    end
  end

  # The other half: compose.yaml only names the variables, the values live in
  # .env. A bare `- MQTT_PORT` that .env never defines reaches the container
  # unset — which is exactly how the missing port crash-looped mqtt-collector.
  describe 'every variable compose references is defined in .env' do
    scenarios.each do |compose_path|
      it "holds for #{scenario_name(compose_path)}" do
        defined_vars = env_vars(compose_path)

        undefined = managed_services(compose_path).flat_map do |name, config|
          referenced_vars(config)
            .reject { |var| defined_vars.include?(var) }
            .map { |var| "#{name}: #{var}" }
        end

        expect(undefined).to be_empty,
                             'compose.yaml references variables .env never defines ' \
                             "(they reach the container unset):\n#{undefined.join("\n")}"
      end
    end
  end

  # csv-importer runs via `docker run -e`, not compose, so it is contracted
  # against the runner's key lists instead of a compose.yaml.
  describe 'csv-importer' do
    let(:reads) { contract.fetch('csv-importer')['reads'] }

    it 'is handed sensor mappings under names the importer reads' do
      expect(CsvImportRunner::SENSOR_MAPPING_KEYS - reads).to be_empty
    end

    it 'is handed influx credentials under names the importer reads' do
      expect(CsvImportRunner::REQUIRED_INFLUX_KEYS - reads).to be_empty
    end
  end
end
