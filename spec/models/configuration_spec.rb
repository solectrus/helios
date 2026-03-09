RSpec.describe Configuration do
  describe 'associations' do
    it { is_expected.to have_many(:chapters).dependent(:destroy) }
  end

  describe '.current' do
    it 'returns singleton instance' do
      config1 = described_class.current
      config2 = described_class.current
      expect(config1.id).to eq(config2.id)
    end

    it 'creates with default data if none exists' do
      config = described_class.current
      expect(config.data).to include('setup_completed')
      expect(config.setup_completed?).to be false
    end
  end

  describe '#chapter' do
    it 'returns empty hash for non-existent chapter' do
      config = described_class.current
      expect(config.chapter('system')).to eq({})
    end

    it 'returns chapter data for singleton' do
      config = described_class.current
      config.update_chapter('system', { 'timezone' => 'Europe/Berlin' })

      expect(config.chapter('system')).to eq(
        { 'timezone' => 'Europe/Berlin' },
      )
    end

    it 'returns chapter data for device with name' do
      config = described_class.current
      config.update_chapter(
        'inverter',
        { 'data_source' => 'senec_local' },
        name: 'Dach Süd',
      )

      expect(config.chapter('inverter', 'Dach Süd')).to eq(
        { 'data_source' => 'senec_local' },
      )
    end
  end

  describe '#update_chapter' do
    it 'creates a new chapter if it does not exist' do
      config = described_class.current

      expect do
        config.update_chapter(
          'inverter',
          { 'data_source' => 'senec_local' },
          name: 'Dach Süd',
        )
      end.to change(Chapter, :count).by(1)

      expect(config.chapter('inverter', 'Dach Süd')).to eq(
        { 'data_source' => 'senec_local' },
      )
    end

    it 'updates existing chapter data' do
      config = described_class.current
      config.update_chapter('system', { 'timezone' => 'UTC' })
      config.update_chapter(
        'system',
        { 'timezone' => 'Europe/Berlin', 'mqtt_host' => '192.168.1.44' },
      )

      expect(config.chapter('system')).to eq(
        { 'timezone' => 'Europe/Berlin', 'mqtt_host' => '192.168.1.44' },
      )
    end

    it 'defaults name to kind for singletons' do
      config = described_class.current
      config.update_chapter('system', { 'timezone' => 'UTC' })

      chapter = config.chapters.find_by(kind: 'system')
      expect(chapter.name).to eq('system')
    end

    it 'does not create duplicate chapters' do
      config = described_class.current
      config.update_chapter('system', { 'v1' => true })
      config.update_chapter('system', { 'v2' => true })

      expect(config.chapters.where(kind: 'system').count).to eq(1)
    end
  end

  describe '#chapter_completed?' do
    it 'returns false for non-existent chapter' do
      config = described_class.current
      expect(config.chapter_completed?('system')).to be false
    end

    it 'returns false for chapter with empty data' do
      config = described_class.current
      config.chapters.create!(kind: 'system', name: 'system', data: {})

      expect(config.chapter_completed?('system')).to be false
    end

    it 'returns true for chapter with data' do
      config = described_class.current
      config.update_chapter('system', { 'timezone' => 'UTC' })

      expect(config.chapter_completed?('system')).to be true
    end
  end

  describe '#chapters_of_kind' do
    it 'returns all chapters of a given kind' do
      config = described_class.current
      config.add_device('inverter', 'Dach Süd', { 'data_source' => 'senec_local' })
      config.add_device('inverter', 'BKW', { 'data_source' => 'mqtt' })
      config.add_device('wallbox', 'Garage')

      expect(config.chapters_of_kind('inverter').count).to eq(2)
    end
  end

  describe '#add_device' do
    it 'creates a device chapter' do
      config = described_class.current

      expect do
        config.add_device('inverter', 'Dach Süd', { 'data_source' => 'senec_local' })
      end.to change(Chapter, :count).by(1)

      chapter = config.chapters.find_by(kind: 'inverter', name: 'Dach Süd')
      expect(chapter.data).to eq({ 'data_source' => 'senec_local' })
    end

    it 'raises error for non-device kinds' do
      config = described_class.current

      expect do
        config.add_device('system', 'test')
      end.to raise_error(ArgumentError, /not a device kind/)
    end
  end

  describe '#remove_device' do
    it 'removes a device chapter' do
      config = described_class.current
      config.add_device('inverter', 'Dach Süd')

      expect do
        config.remove_device('inverter', 'Dach Süd')
      end.to change(Chapter, :count).by(-1)
    end

    it 'raises error if device not found' do
      config = described_class.current

      expect do
        config.remove_device('inverter', 'nonexistent')
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '#mqtt_required?' do
    it 'returns false when no devices use MQTT' do
      config = described_class.current
      config.add_device('inverter', 'PV', { 'data_source' => 'senec_local' })

      expect(config.mqtt_required?).to be false
    end

    it 'returns true when a device uses MQTT as data_source' do
      config = described_class.current
      config.add_device('inverter', 'PV', { 'data_source' => 'mqtt' })

      expect(config.mqtt_required?).to be true
    end

    it 'returns true when heatpump uses MQTT as power_source' do
      config = described_class.current
      config.add_device('heatpump', 'HP', { 'power_source' => 'mqtt' })

      expect(config.mqtt_required?).to be true
    end

    it 'returns true when heatpump uses MQTT as details_source' do
      config = described_class.current
      config.add_device('heatpump', 'HP', { 'details_source' => 'mqtt' })

      expect(config.mqtt_required?).to be true
    end
  end

  describe '#ingest_required?' do
    it 'returns false with single inverter that knows house power' do
      config = described_class.current
      config.add_device('inverter', 'PV', { 'house_power_known' => true })

      expect(config.ingest_required?).to be false
    end

    it 'returns true with single inverter that does not know house power' do
      config = described_class.current
      config.add_device('inverter', 'PV', { 'house_power_known' => false })

      expect(config.ingest_required?).to be true
    end

    it 'returns true with multiple inverters' do
      config = described_class.current
      config.add_device('inverter', 'Dach', { 'house_power_known' => true })
      config.add_device('inverter', 'BKW', { 'house_power_known' => true })

      expect(config.ingest_required?).to be true
    end

    it 'returns false with no inverters' do
      config = described_class.current

      expect(config.ingest_required?).to be false
    end
  end

  describe '#senec_hosts' do
    it 'returns deduplicated SENEC hosts' do
      config = described_class.current
      config.add_device(
        'inverter', 'PV',
        { 'data_source' => 'senec_local', 'senec_host' => '192.168.1.42' }
      )
      config.add_device(
        'battery', 'Akku',
        { 'data_source' => 'senec_local', 'senec_host' => '192.168.1.42' }
      )

      expect(config.senec_hosts).to eq(['192.168.1.42'])
    end

    it 'returns empty array when no SENEC devices' do
      config = described_class.current
      config.add_device('inverter', 'PV', { 'data_source' => 'mqtt' })

      expect(config.senec_hosts).to eq([])
    end
  end

  describe '#effective_sensor_mappings' do
    it 'merges computed mappings with overrides' do
      config = described_class.current
      config.update_chapter(
        'sensors',
        { 'inverter_power' => 'custom:power' },
      )

      expect(config.effective_sensor_mappings).to include(
        'inverter_power' => 'custom:power',
      )
    end
  end

  describe '#installation_date' do
    it 'gets and sets installation date' do
      config = described_class.current
      config.installation_date = '2024-01-15'
      config.reload

      expect(config.installation_date).to eq('2024-01-15')
    end

    it 'returns nil when not set' do
      config = described_class.current
      expect(config.installation_date).to be_nil
    end
  end

  describe '#timezone' do
    it 'gets and sets timezone' do
      config = described_class.current
      config.timezone = 'Europe/Berlin'
      config.reload

      expect(config.timezone).to eq('Europe/Berlin')
    end

    it 'returns nil when not set' do
      config = described_class.current
      expect(config.timezone).to be_nil
    end
  end

  describe '#setup_completed?' do
    it 'returns false by default' do
      config = described_class.current
      expect(config.setup_completed?).to be false
    end

    it 'returns true after complete_setup!' do
      config = described_class.current
      config.complete_setup!
      expect(config.setup_completed?).to be true
    end
  end
end
