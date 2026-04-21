RSpec.describe 'Import::ConfigurationImporter Ingest handling' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  def stub_stack_reader(services)
    instance_double(
      Import::StackReader,
      services: services,
      raw_env: { 'INFLUX_TOKEN' => 'token', 'INFLUX_ORG' => 'solectrus', 'INFLUX_BUCKET' => 'solectrus' },
      raw_compose: { 'services' => services },
    ).tap do |double|
      allow(double).to receive(:service) { |name| services[name] }
    end
  end

  context 'with an Ingest service in the stack' do
    let(:stack_reader) do
      stub_stack_reader(
        'dashboard' => {
          'environment' => {
            'INFLUX_SENSOR_INVERTER_POWER_2' => 'SENEC:mpp2_power',
            'INFLUX_SENSOR_HOUSE_POWER' => 'SENEC:house_power',
            'INFLUX_SENSOR_HOUSE_POWER_CALCULATED' => 'SENEC:house_power_calculated',
          },
        },
        'ingest' => {
          'image' => 'ghcr.io/solectrus/ingest:latest',
          'environment' => { 'RETENTION_HOURS' => '48' },
        },
        'power-splitter' => { 'environment' => {} },
      )
    end

    describe 'ingest section data' do
      subject(:ingest_data) { importer.result[:ingest] }

      it 'imports retention hours' do
        expect(ingest_data).to include('retention_hours' => '48')
      end

      it 'imports the ingest image' do
        expect(ingest_data).to include('image' => 'ghcr.io/solectrus/ingest:latest')
      end

      it 'does not carry over STATS_PASSWORD (auto-linked to ADMIN_PASSWORD on export)' do
        expect(ingest_data.keys).not_to include('stats_password')
      end
    end

    describe 'sensor data' do
      subject(:sensors) { importer.result[:sensors] }

      it 'drops INFLUX_SENSOR_HOUSE_POWER_CALCULATED because it is not a real sensor' do
        expect(sensors.keys).not_to include('house_power_calculated')
      end

      it 'keeps regular sensor mappings' do
        expect(sensors).to include(
          'inverter_power_2' => 'SENEC:mpp2_power',
          'house_power' => 'SENEC:house_power',
        )
      end
    end

    describe '#import!' do
      subject(:config) { importer.import! }

      it 'flags the first individual inverter sensor as balcony power plant' do
        expect(config.sensor_config('inverter_power_2').is_balcony).to be true
      end

      it 'makes ingest_required? true after import' do
        importer.import!
        expect(Configuration.current.ingest_required?).to be true
      end

      it 'persists the ingest section' do
        expect(config.ingest.retention_hours).to eq('48')
      end
    end
  end

  context 'with an Ingest service but no individual inverter sensors' do
    let(:stack_reader) do
      stub_stack_reader(
        'dashboard' => {
          'environment' => {
            'INFLUX_SENSOR_INVERTER_POWER' => 'SENEC:inverter_power',
            'INFLUX_SENSOR_HOUSE_POWER' => 'SENEC:house_power',
          },
        },
        'ingest' => {
          'image' => 'ghcr.io/solectrus/ingest:latest',
          'environment' => { 'RETENTION_HOURS' => '48' },
        },
      )
    end

    it 'skips the ingest section (inconsistent stack — Ingest needs split inverters)' do
      expect(importer.result[:ingest]).to be_nil
    end

    it 'does not flag any sensor as balcony power plant' do
      config = importer.import!
      expect(config.sensor_config('inverter_power').is_balcony).to be_nil
    end

    it 'results in ingest_required? being false' do
      importer.import!
      expect(Configuration.current.ingest_required?).to be false
    end
  end
end
