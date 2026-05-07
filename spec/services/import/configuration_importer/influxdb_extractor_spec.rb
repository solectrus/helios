RSpec.describe 'Import::ConfigurationImporter InfluxDB tokens' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:services) do
    {
      'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
      'influxdb' => { 'image' => 'influxdb:2.7-alpine' },
    }
  end
  let(:stack_reader) do
    instance_double(
      Import::StackReader,
      raw_env: raw_env,
      raw_compose: { 'services' => services },
      services: services,
      stack_dir: '/srv/solectrus',
    ).tap { |double| allow(double).to receive(:service) { |name| services[name] } }
  end

  context 'with admin/write/read tokens (user8 shape)' do
    let(:raw_env) do
      {
        'INFLUX_ADMIN_TOKEN' => 'admin-secret',
        'INFLUX_TOKEN_WRITE' => 'write-secret',
        'INFLUX_TOKEN_READ' => 'read-secret',
      }
    end

    # No explicit readwrite token in donor: it falls back to admin so
    # power-splitter still has both read+write privileges after re-export.
    it 'maps each role and promotes admin into the readwrite slot' do
      expect(importer.result[:influxdb]).to include(
        'token_admin' => 'admin-secret',
        'token_readwrite' => 'admin-secret',
        'token_write' => 'write-secret',
        'token_read' => 'read-secret',
      )
    end
  end

  context 'with a single INFLUX_TOKEN (canonical SOLECTRUS shape)' do
    let(:raw_env) { { 'INFLUX_TOKEN' => 'shared-secret' } }

    it 'fans the token out to all four roles' do
      expect(importer.result[:influxdb]).to include(
        'token_admin' => 'shared-secret',
        'token_readwrite' => 'shared-secret',
        'token_write' => 'shared-secret',
        'token_read' => 'shared-secret',
      )
    end
  end

  context 'with INFLUX_TOKEN_READWRITE present (user5 shape)' do
    let(:raw_env) do
      {
        'INFLUX_TOKEN_READWRITE' => 'rw-secret',
        'INFLUX_TOKEN_WRITE' => 'write-secret',
        'INFLUX_TOKEN_READ' => 'read-secret',
      }
    end

    # Donor has no canonical admin token. The readwrite token lands in its
    # own slot, while admin falls back through the strongest available
    # privilege (readwrite > write > read) for a deterministic round-trip.
    it 'preserves readwrite in its own slot and promotes it into admin' do
      expect(importer.result[:influxdb]).to include(
        'token_admin' => 'rw-secret',
        'token_readwrite' => 'rw-secret',
        'token_write' => 'write-secret',
        'token_read' => 'read-secret',
      )
    end
  end
end
