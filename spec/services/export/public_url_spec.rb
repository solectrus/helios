RSpec.describe Export::PublicUrl do
  subject(:build) { described_class.build(configuration, service_name, published:) }

  let(:configuration) { Configuration.from_data(data) }
  let(:published) { true }

  describe 'without a reverse proxy' do
    let(:data) { {} }

    %w[dashboard influxdb ingest].each do |name|
      context "with #{name}" do
        let(:service_name) { name }

        it { is_expected.to be_nil }
      end
    end
  end

  describe 'behind a managed Traefik' do
    let(:data) do
      {
        'reverse_proxy' => { 'app_domain' => 'solectrus.example.com' },
        'influxdb' => influxdb,
      }
    end
    let(:influxdb) { {} }

    context 'with the dashboard' do
      let(:service_name) { 'dashboard' }

      it { is_expected.to eq('https://solectrus.example.com') }
    end

    context 'with an exposed InfluxDB' do
      let(:service_name) { 'influxdb' }
      let(:influxdb) { { 'publish_port' => true, 'host_port' => '18086' } }

      it 'links to the dedicated entrypoint port' do
        expect(build).to eq('https://solectrus.example.com:18086')
      end

      it 'defaults to 8086 without a custom host_port' do
        configuration.update('influxdb', { 'publish_port' => true })
        expect(build).to eq('https://solectrus.example.com:8086')
      end
    end

    context 'with an InfluxDB that is not exposed' do
      let(:service_name) { 'influxdb' }

      it { is_expected.to be_nil }
    end

    context 'with a service kept on a direct port (ingest)' do
      let(:service_name) { 'ingest' }

      it { is_expected.to be_nil }
    end
  end

  describe 'behind an external Traefik' do
    let(:data) do
      {
        'reverse_proxy' => { 'bind_ip' => '10.0.0.5' },
        'system' => { 'app_host' => 'solectrus.example.com' },
      }
    end

    context 'with the dashboard' do
      let(:service_name) { 'dashboard' }

      it 'links to the bare host' do
        expect(build).to eq('https://solectrus.example.com')
      end
    end

    context 'with InfluxDB' do
      let(:service_name) { 'influxdb' }

      it 'links to the influxdb subdomain' do
        expect(build).to eq('https://influxdb.solectrus.example.com')
      end
    end

    context 'with ingest' do
      let(:service_name) { 'ingest' }

      it 'links to the ingest subdomain' do
        expect(build).to eq('https://ingest.solectrus.example.com')
      end
    end

    context 'when the service publishes no host port' do
      let(:service_name) { 'influxdb' }
      let(:published) { false }

      it { is_expected.to be_nil }
    end

    context 'without a configured app_host' do
      let(:data) { { 'reverse_proxy' => { 'bind_ip' => '10.0.0.5' } } }
      let(:service_name) { 'dashboard' }

      it { is_expected.to be_nil }
    end
  end
end
