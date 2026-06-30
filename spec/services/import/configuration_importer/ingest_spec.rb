RSpec.describe 'Import::ConfigurationImporter Ingest handling' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  def stub_stack_reader(services, raw_env: {}, stack_dir: '/srv/solectrus')
    defaults = { 'INFLUX_TOKEN' => 'token', 'INFLUX_ORG' => 'solectrus', 'INFLUX_BUCKET' => 'solectrus' }
    instance_double(
      Import::StackReader,
      services: services,
      raw_env: defaults.merge(raw_env),
      raw_compose: { 'services' => services },
      stack_dir: stack_dir,
    ).tap do |double|
      allow(double).to receive(:service) { |name| services[name] }
    end
  end

  context 'with an Ingest service in the stack' do
    let(:stack_reader) do
      stub_stack_reader({
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
                        })
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

      # The stack runs Ingest but has no collector, so inverter_power_2 is
      # imported as source: external. HELIOS routes Ingest inputs through the
      # proxy and cannot reroute an external writer, so it would drop Ingest.
      it 'leaves ingest_required? false because the Ingest input is external' do
        importer.import!
        expect(Configuration.current.ingest_required?).to be false
      end

      it 'flags the external Ingest inputs as a conflict (import gets refused)' do
        # Both the balcony (inverter_power_2) and house_power arrive without a
        # managed collector, so both are external Ingest inputs.
        expect(importer.ingest_conflict_sensors).to contain_exactly('inverter_power_2', 'house_power')
      end

      it 'persists the ingest section' do
        expect(config.ingest.retention_hours).to eq('48')
      end
    end
  end

  context 'with an Ingest service and a custom INGEST_VOLUME_PATH' do
    let(:services) do
      {
        'dashboard' => { 'environment' => { 'INFLUX_SENSOR_INVERTER_POWER_2' => 'SENEC:mpp2_power' } },
        'ingest' => { 'image' => 'ghcr.io/solectrus/ingest:latest', 'environment' => {} },
      }
    end

    context 'when the path points outside the stack directory' do
      let(:stack_reader) do
        stub_stack_reader(services, raw_env: { 'INGEST_VOLUME_PATH' => '/volume1/docker/solectrus/ingest' })
      end

      it 'preserves the absolute path as volume_path' do
        expect(importer.result[:ingest]).to include('volume_path' => '/volume1/docker/solectrus/ingest')
      end

      it 'does not leak INGEST_VOLUME_PATH into unmanaged env_vars' do
        expect(importer.result[:unmanaged]&.dig('env_vars') || {}).not_to have_key('INGEST_VOLUME_PATH')
      end
    end

    context 'when the path resolves to the default bind mount next to compose.yaml' do
      let(:stack_reader) do
        stub_stack_reader(services, raw_env: { 'INGEST_VOLUME_PATH' => '/srv/solectrus/ingest' })
      end

      it 'drops the path — the relative default is equivalent' do
        expect(importer.result[:ingest]).not_to have_key('volume_path')
      end

      it 'does not leak INGEST_VOLUME_PATH into unmanaged env_vars' do
        expect(importer.result[:unmanaged]&.dig('env_vars') || {}).not_to have_key('INGEST_VOLUME_PATH')
      end
    end

    context 'when the .env uses a relative path' do
      let(:stack_reader) do
        stub_stack_reader(services, raw_env: { 'INGEST_VOLUME_PATH' => './ingest' })
      end

      it 'ignores it — HELIOS already defaults to the same relative mount' do
        expect(importer.result[:ingest]).not_to have_key('volume_path')
      end

      it 'does not leak INGEST_VOLUME_PATH into unmanaged env_vars' do
        expect(importer.result[:unmanaged]&.dig('env_vars') || {}).not_to have_key('INGEST_VOLUME_PATH')
      end
    end
  end

  context 'with an Ingest service and a multi-MPPT inverter (shared measurement)' do
    let(:stack_reader) do
      stub_stack_reader({
                          'dashboard' => {
                            'environment' => {
                              'INFLUX_SENSOR_INVERTER_POWER_1' => 'SENEC:mpp1_power',
                              'INFLUX_SENSOR_INVERTER_POWER_2' => 'SENEC:mpp2_power',
                              'INFLUX_SENSOR_INVERTER_POWER_3' => 'SENEC:mpp3_power',
                              'INFLUX_SENSOR_HOUSE_POWER' => 'SENEC:house_power',
                            },
                          },
                          'ingest' => {
                            'image' => 'ghcr.io/solectrus/ingest:latest',
                            'environment' => { 'RETENTION_HOURS' => '48' },
                          },
                        })
    end

    it 'recognizes the slots as one multi-string inverter, not a balcony generator' do
      config = importer.import!
      expect(config.sensor_config('inverter_power_3').is_balcony).to be_nil
    end

    it 'drops the ingest section — ingest follows balcony sensors, not the donor service' do
      expect(importer.result[:ingest]).to be_nil
    end

    it 'results in ingest_required? being false' do
      importer.import!
      expect(Configuration.current.ingest_required?).to be false
    end
  end

  context 'with an Ingest service and a multi-string inverter plus a balcony generator' do
    let(:stack_reader) do
      stub_stack_reader({
                          'dashboard' => {
                            'environment' => {
                              'INFLUX_SENSOR_INVERTER_POWER_1' => 'SENEC:mpp1_power',
                              'INFLUX_SENSOR_INVERTER_POWER_2' => 'SENEC:mpp2_power',
                              'INFLUX_SENSOR_INVERTER_POWER_3' => 'Garage:power',
                              'INFLUX_SENSOR_HOUSE_POWER' => 'SENEC:house_power',
                            },
                          },
                          'ingest' => {
                            'image' => 'ghcr.io/solectrus/ingest:latest',
                            'environment' => {},
                          },
                        })
    end

    it 'flags the highest-numbered slot (different measurement) as balcony' do
      config = importer.import!
      expect(config.sensor_config('inverter_power_3').is_balcony).to be true
    end

    it 'does not flag the MPPT string sharing the main inverter measurement' do
      config = importer.import!
      expect(config.sensor_config('inverter_power_2').is_balcony).to be_nil
    end

    it 'imports the ingest section' do
      expect(importer.result[:ingest]).to include('image' => 'ghcr.io/solectrus/ingest:latest')
    end
  end

  context 'with an Ingest service and two separate balcony generators' do
    let(:stack_reader) do
      stub_stack_reader({
                          'dashboard' => {
                            'environment' => {
                              'INFLUX_SENSOR_INVERTER_POWER_1' => 'SENEC:inverter_power',
                              'INFLUX_SENSOR_INVERTER_POWER_2' => 'Fence:power',
                              'INFLUX_SENSOR_INVERTER_POWER_3' => 'Fence2:power',
                              'INFLUX_SENSOR_HOUSE_POWER' => 'SENEC:house_power',
                            },
                          },
                          'ingest' => {
                            'image' => 'ghcr.io/solectrus/ingest:latest',
                            'environment' => {},
                          },
                        })
    end

    it 'flags every distinct-measurement slot as its own balcony generator' do
      config = importer.import!
      expect(config.sensor_config('inverter_power_2').is_balcony).to be true
      expect(config.sensor_config('inverter_power_3').is_balcony).to be true
    end

    it 'leaves the main roof inverter unflagged' do
      config = importer.import!
      expect(config.sensor_config('inverter_power_1').is_balcony).to be_nil
    end
  end

  context 'with an Ingest service but no individual inverter sensors' do
    let(:stack_reader) do
      stub_stack_reader({
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
                        })
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
