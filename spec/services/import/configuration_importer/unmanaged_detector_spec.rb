RSpec.describe Import::ConfigurationImporter::UnmanagedDetector do
  subject(:detected) { described_class.new(reader).detect }

  let(:compose) { { 'services' => services } }
  let(:env_vars) { {} }
  let(:reader) do
    instance_double(Import::StackReader, raw_compose: compose, raw_env: env_vars, services: services)
  end

  before { with_config_yaml }

  # docker compose accepts `environment:` as a mapping as well as a list, and
  # an imported stack may use either.
  context 'with a service whose environment is a mapping' do
    let(:services) do
      {
        'dozzle' => {
          'image' => 'amir20/dozzle:latest',
          'environment' => { 'DOZZLE_LEVEL' => 'debug', 'DOZZLE_BASE' => '${BASE_PATH}' },
        },
      }
    end
    let(:env_vars) { { 'BASE_PATH' => '/logs' } }

    it 'keeps the declared entries and resolves the interpolated one from .env' do
      service = detected.dig('services', 'dozzle')

      expect(service['environment']).to include('DOZZLE_LEVEL=debug')
      expect(service['env_values']).to include('BASE_PATH' => '/logs')
    end
  end

  # A hand-edited compose can put a mapping inside the list form; every name
  # in it still counts as declared and as referenced.
  context 'with a mapping nested in the environment list' do
    let(:services) do
      {
        'dozzle' => {
          'image' => 'amir20/dozzle:latest',
          'environment' => [{ 'DOZZLE_LEVEL' => 'debug', 'DOZZLE_BASE' => '${BASE_PATH}' }],
        },
      }
    end
    let(:env_vars) { { 'BASE_PATH' => '/logs' } }

    it 'reads the names out of the mapping' do
      service = detected.dig('services', 'dozzle')

      expect(service['env_values']).to include('BASE_PATH' => '/logs')
      expect(detected['env_vars']).to be_nil
    end
  end

  # `env_file: .env` hands the service every variable in .env, so the orphans
  # nothing else claims belong to it after the import too.
  context 'with a service reading the whole .env file' do
    let(:services) do
      {
        'dozzle' => { 'image' => 'amir20/dozzle:latest', 'env_file' => ['.env'] },
      }
    end
    let(:env_vars) { { 'DOZZLE_LEVEL' => 'debug' } }

    it 'adopts the orphaned variables and drops the env_file reference' do
      service = detected.dig('services', 'dozzle')

      expect(service).not_to have_key('env_file')
      expect(service['environment']).to include('DOZZLE_LEVEL')
      expect(service['env_values']).to include('DOZZLE_LEVEL' => 'debug')
    end

    it 'does not list them a second time as orphans' do
      expect(detected['env_vars']).to be_nil
    end
  end

  context 'with a service naming its env file as a mapping' do
    let(:services) do
      {
        'dozzle' => { 'image' => 'amir20/dozzle:latest', 'env_file' => [{ 'path' => '.env' }] },
      }
    end
    let(:env_vars) { { 'DOZZLE_LEVEL' => 'debug' } }

    it 'reads it the same way' do
      expect(detected.dig('services', 'dozzle')).not_to have_key('env_file')
    end
  end

  context 'with a service naming an env file of its own' do
    let(:services) do
      {
        'dozzle' => { 'image' => 'amir20/dozzle:latest', 'env_file' => ['dozzle.env'] },
      }
    end
    let(:env_vars) { { 'DOZZLE_LEVEL' => 'debug' } }

    it 'keeps the reference' do
      expect(detected.dig('services', 'dozzle', 'env_file')).to eq(['dozzle.env'])
    end
  end

  # The environment list is sorted so the exported compose stays readable:
  # TZ first, then INFLUX_*, then the mappings by index, then the rest.
  context 'with an unmanaged collector carrying indexed mapping variables' do
    let(:services) do
      {
        'legacy-collector' => {
          'image' => 'example/legacy:latest',
          'environment' => %w[MAPPING_10_TOPIC LEGACY_INTERVAL MAPPING_2_TOPIC INFLUX_ORG TZ],
        },
      }
    end

    it 'orders the mappings numerically, not alphabetically' do
      expect(detected.dig('services', 'legacy-collector', 'environment'))
        .to eq(%w[TZ INFLUX_ORG MAPPING_2_TOPIC MAPPING_10_TOPIC LEGACY_INTERVAL])
    end
  end
end
