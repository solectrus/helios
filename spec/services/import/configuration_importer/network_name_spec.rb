RSpec.describe 'Import::ConfigurationImporter network name handling' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:services) { { 'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' } } }
  let(:raw_compose) { { 'services' => services }.merge(networks_block) }
  let(:networks_block) { {} }
  let(:stack_reader) do
    instance_double(
      Import::StackReader,
      raw_env: {},
      raw_compose: raw_compose,
      services: services,
      stack_dir: '/srv/solectrus',
    ).tap { |double| allow(double).to receive(:service) { |name| services[name] } }
  end

  context 'when the imported compose overrides the default network name' do
    let(:networks_block) { { 'networks' => { 'default' => { 'name' => 'solectrus-default' } } } }

    it 'preserves the override so the regenerated stack reuses the existing network' do
      expect(importer.result[:system]).to include('network_name' => 'solectrus-default')
    end
  end

  context 'when the imported compose has no networks block' do
    it 'leaves network_name unset so the exporter falls back to the HELIOS default' do
      expect(importer.result[:system]).not_to have_key('network_name')
    end
  end

  context 'when the imported compose has an empty network name' do
    let(:networks_block) { { 'networks' => { 'default' => { 'name' => '' } } } }

    it 'treats the blank value as absent rather than as an empty network name' do
      expect(importer.result[:system]).not_to have_key('network_name')
    end
  end
end
