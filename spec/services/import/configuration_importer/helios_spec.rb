RSpec.describe 'Import::ConfigurationImporter helios image' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:services) do
    {
      'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
    }
  end
  let(:stack_reader) do
    instance_double(
      Import::StackReader,
      raw_env: {},
      raw_compose: { 'services' => services },
      services: services,
      stack_dir: '/srv/solectrus',
    ).tap { |double| allow(double).to receive(:service) { |name| services[name] } }
  end

  context 'when the stack already runs HELIOS on a specific channel' do
    let(:services) do
      {
        'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
        'helios' => { 'image' => 'ghcr.io/solectrus/helios:develop' },
      }
    end

    it 'preserves the existing channel' do
      expect(importer.result[:helios]).to eq('image' => 'ghcr.io/solectrus/helios:develop')
    end
  end

  context 'when the imported stack has no HELIOS service' do
    it 'leaves the channel to the default applied on export' do
      expect(importer.result[:helios]).to eq({})
    end
  end
end
