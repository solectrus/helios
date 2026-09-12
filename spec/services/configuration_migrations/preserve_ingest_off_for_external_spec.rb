RSpec.describe ConfigurationMigrations::PreserveIngestOffForExternal do
  subject(:up) { described_class.new.up(data) }

  # Balcony power plant on inverter_power_2, house_power delivered by a smart
  # home. Before the Ingest switch existed, the external input alone kept
  # HELIOS from exporting Ingest.
  def base_data(sensors:, **extra)
    {
      'deployment' => { 'mode' => 'full' },
      'system' => { 'timezone' => 'Europe/Berlin' },
      'sensors' => sensors,
    }.merge(extra)
  end

  def balcony_sensor
    { 'source' => 'mqtt', 'measurement' => 'PV', 'field' => 'balcony', 'is_balcony' => true }
  end

  def external_sensor
    { 'source' => 'external', 'measurement' => 'PV', 'field' => 'house_power' }
  end

  context 'with a balcony power plant and an external Ingest input' do
    let(:data) do
      base_data(sensors: { 'inverter_power_2' => balcony_sensor, 'house_power' => external_sensor })
    end

    it 'switches the correction off' do
      expect(up['ingest']).to eq('active' => false)
    end

    context 'when an ingest section already exists' do
      let(:data) do
        base_data(
          sensors: { 'inverter_power_2' => balcony_sensor, 'house_power' => external_sensor },
          'ingest' => { 'retention_hours' => '24' },
        )
      end

      it 'keeps the stored settings' do
        expect(up['ingest']).to eq('retention_hours' => '24', 'active' => false)
      end
    end
  end

  context 'with a balcony power plant and no external Ingest input' do
    let(:data) do
      base_data(sensors: { 'inverter_power_2' => balcony_sensor })
    end

    it 'leaves the correction on' do
      expect(up).not_to have_key('ingest')
    end
  end

  context 'when the external sensor is none of the Ingest inputs' do
    let(:data) do
      base_data(
        sensors: {
          'inverter_power_2' => balcony_sensor,
          'case_temp' => { 'source' => 'external', 'measurement' => 'PV', 'field' => 'case_temp' },
        },
      )
    end

    it 'leaves the correction on' do
      expect(up).not_to have_key('ingest')
    end
  end

  context 'without a balcony power plant' do
    let(:data) do
      base_data(sensors: { 'house_power' => external_sensor })
    end

    it 'leaves the correction on' do
      expect(up).not_to have_key('ingest')
    end
  end

  context 'when the stack runs in collectors_only mode' do
    let(:data) do
      base_data(
        sensors: { 'inverter_power_2' => balcony_sensor, 'house_power' => external_sensor },
        'deployment' => { 'mode' => 'collectors_only' },
      )
    end

    it 'leaves the correction on, because nothing local recalculates' do
      expect(up).not_to have_key('ingest')
    end
  end

  context 'without any sensors' do
    let(:data) { { 'deployment' => { 'mode' => 'full' } } }

    it 'leaves the data untouched' do
      expect(up).to eq('deployment' => { 'mode' => 'full' })
    end
  end

  context 'with a sensor still stored as a raw string' do
    let(:data) do
      base_data(sensors: { 'inverter_power_2' => balcony_sensor, 'house_power' => 'PV:house_power' })
    end

    it 'leaves the data untouched instead of raising' do
      expect(up).not_to have_key('ingest')
    end
  end

  it 'is registered as version 5' do
    expect(described_class.version).to eq(5)
  end
end
