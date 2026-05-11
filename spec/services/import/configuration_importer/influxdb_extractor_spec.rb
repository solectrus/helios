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

  describe 'publish_port' do
    let(:raw_env) { { 'INFLUX_TOKEN' => 'shared-secret' } }

    context 'when the donor publishes 8086:8086 (short form)' do
      let(:services) do
        {
          'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
          'influxdb' => { 'image' => 'influxdb:2.7-alpine', 'ports' => ['8086:8086'] },
        }
      end

      it 'captures publish_port: true' do
        expect(importer.result[:influxdb]).to include('publish_port' => true)
      end
    end

    context 'when the donor remaps the host port (18086:8086)' do
      let(:services) do
        {
          'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
          'influxdb' => { 'image' => 'influxdb:2.7-alpine', 'ports' => ['18086:8086'] },
        }
      end

      it 'still captures publish_port: true (target port is what counts)' do
        expect(importer.result[:influxdb]).to include('publish_port' => true)
      end

      it 'preserves the non-default host port' do
        expect(importer.result[:influxdb]).to include('host_port' => '18086')
      end
    end

    context 'when docker compose normalizes a remapped port to long-form' do
      let(:services) do
        {
          'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
          'influxdb' => {
            'image' => 'influxdb:2.7-alpine',
            'ports' => [{ 'target' => 8086, 'published' => '18086', 'protocol' => 'tcp' }],
          },
        }
      end

      it 'preserves the non-default host port' do
        expect(importer.result[:influxdb]).to include('host_port' => '18086')
      end
    end

    context 'when the donor publishes the canonical 8086:8086' do
      let(:services) do
        {
          'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
          'influxdb' => { 'image' => 'influxdb:2.7-alpine', 'ports' => ['8086:8086'] },
        }
      end

      it 'omits host_port (canonical default is implicit)' do
        expect(importer.result[:influxdb]).not_to have_key('host_port')
      end
    end

    context 'when docker compose normalizes ports to long-form' do
      let(:services) do
        {
          'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
          'influxdb' => {
            'image' => 'influxdb:2.7-alpine',
            'ports' => [{ 'target' => 8086, 'published' => '8086', 'protocol' => 'tcp' }],
          },
        }
      end

      it 'captures publish_port: true' do
        expect(importer.result[:influxdb]).to include('publish_port' => true)
      end
    end

    context 'when the donor does not publish the InfluxDB port' do
      it 'omits publish_port (defaults to not publishing)' do
        expect(importer.result[:influxdb]).not_to have_key('publish_port')
      end
    end

    context 'when the donor publishes only an unrelated port' do
      let(:services) do
        {
          'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
          'influxdb' => { 'image' => 'influxdb:2.7-alpine', 'ports' => ['9999:9999'] },
        }
      end

      it 'omits publish_port' do
        expect(importer.result[:influxdb]).not_to have_key('publish_port')
      end
    end
  end
end
