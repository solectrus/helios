RSpec.describe 'Import::ConfigurationImporter currency handling' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:dashboard_env) { {} }
  let(:services) do
    { 'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest', 'environment' => dashboard_env } }
  end
  let(:raw_env) { {} }
  let(:stack_reader) do
    instance_double(
      Import::StackReader,
      raw_env:,
      raw_compose: { 'services' => services },
      services:,
      stack_dir: '/srv/solectrus',
    ).tap { |double| allow(double).to receive(:service) { |name| services[name] } }
  end

  context 'when the dashboard defines a common CURRENCY' do
    let(:dashboard_env) { { 'CURRENCY' => 'CHF' } }

    it 'stores the ISO-4217 code directly' do
      expect(importer.result[:system]).to include('currency' => 'CHF')
    end
  end

  context 'when the dashboard defines an uncommon CURRENCY' do
    let(:dashboard_env) { { 'CURRENCY' => 'SEK' } }

    it 'stores the free-text code the same way (single field)' do
      expect(importer.result[:system]).to include('currency' => 'SEK')
    end
  end

  context 'when CURRENCY is lowercase' do
    let(:dashboard_env) { { 'CURRENCY' => 'chf' } }

    it 'upcases it to the canonical ISO-4217 code' do
      expect(importer.result[:system]).to include('currency' => 'CHF')
    end
  end

  context 'when CURRENCY only lives in raw .env' do
    let(:raw_env) { { 'CURRENCY' => 'USD' } }

    it 'falls back to raw_env so a legacy .env-only value survives' do
      expect(importer.result[:system]).to include('currency' => 'USD')
    end
  end

  context 'when no CURRENCY is present' do
    it 'leaves currency unset so the exporter omits it and the dashboard defaults to EUR' do
      expect(importer.result[:system]).not_to have_key('currency')
    end
  end
end
