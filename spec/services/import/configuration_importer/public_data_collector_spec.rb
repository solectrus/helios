RSpec.describe 'Import::ConfigurationImporter public-data-collector' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:services) do
    {
      'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:develop' },
      'public-data-collector' => {
        'image' => 'ghcr.io/solectrus/public-data-collector:develop',
        'environment' => { 'COUNTRY' => 'DE', 'ENABLE_FUEL' => 'true' },
      },
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

  it 'preserves the image channel' do
    expect(importer.result[:public_data_collector]).to eq('image' => 'ghcr.io/solectrus/public-data-collector:develop')
  end

  it 'takes the country into the system settings' do
    expect(importer.result[:system]).to include('country' => 'DE')
  end

  context 'with a country outside the European Union' do
    before { services['public-data-collector']['environment']['COUNTRY'] = 'ch' }

    it 'keeps the choice outside the European Union over the timezone' do
      expect(importer.result[:system]).to include('country' => 'other')
    end
  end

  # The European Union writes Greece as EL, and the collector takes it.
  context 'with the EU code of Greece' do
    before { services['public-data-collector']['environment']['COUNTRY'] = 'el' }

    it 'takes the ISO code' do
      expect(importer.result[:system]).to include('country' => 'GR')
    end
  end

  context 'with a value that is no country code' do
    before { services['public-data-collector']['environment']['COUNTRY'] = 'Germany' }

    it 'leaves the country to the timezone' do
      expect(importer.result[:system]).not_to have_key('country')
    end
  end

  context 'without a country' do
    before { services['public-data-collector']['environment'].delete('COUNTRY') }

    it 'leaves the country to the timezone' do
      expect(importer.result[:system]).not_to have_key('country')
    end

    # Another service can read a COUNTRY of its own.
    it 'ignores a COUNTRY in .env' do
      allow(stack_reader).to receive(:raw_env).and_return('COUNTRY' => 'AT')

      expect(importer.result[:system]).not_to have_key('country')
    end
  end

  it 'takes the service over instead of keeping it as an unmanaged one' do
    expect(importer.result.dig(:unmanaged, 'services')).to be_nil
  end

  # Only a stack HELIOS wrote has to come back whole. HELIOS writes the
  # service only where the configuration enables it, so re-importing its own
  # stack enables it again.
  context 'with a stack HELIOS exported' do
    let(:snapshot) { ScenarioSnapshot.path('import', 'with_external').join('snapshot') }
    let(:stack_reader) do
      Import::StackReader.new(compose_path: snapshot.join('compose.yaml'), env_path: snapshot.join('.env'))
    end

    it 'keeps the service' do
      expect(Export::Services::PublicDataCollector.enabled?(importer.import!)).to be(true)
    end

    # The compose file only passes COUNTRY through, the value is in .env.
    it 'reads the country from .env' do
      expect(importer.result[:system]).to include('country' => 'DE')
    end
  end

  context 'without the service in the stack' do
    let(:services) { { 'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:develop' } } }

    it 'leaves the image to the default applied on export' do
      expect(importer.result[:public_data_collector]).to be_nil
    end

    # Another service can read a COUNTRY of its own.
    it 'ignores a COUNTRY in .env' do
      allow(stack_reader).to receive(:raw_env).and_return('COUNTRY' => 'AT')

      expect(importer.result[:system]).not_to have_key('country')
    end
  end
end
