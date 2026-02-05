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
      expect(config.chapter('devices')).to eq({})
    end

    it 'returns chapter data when chapter exists' do
      config = described_class.current
      config.update_chapter('devices', { 'devices' => %w[inverter battery] })

      expect(config.chapter('devices')).to eq(
        { 'devices' => %w[inverter battery] },
      )
    end
  end

  describe '#update_chapter' do
    it 'creates a new chapter if it does not exist' do
      config = described_class.current

      expect do
        config.update_chapter('inverter', { 'type' => 'senec' })
      end.to change(Chapter, :count).by(1)

      expect(config.chapter('inverter')).to eq({ 'type' => 'senec' })
    end

    it 'updates existing chapter data' do
      config = described_class.current
      config.update_chapter('inverter', { 'type' => 'senec' })
      config.update_chapter(
        'inverter',
        { 'type' => 'fronius', 'host' => '1.2.3.4' },
      )

      expect(config.chapter('inverter')).to eq(
        { 'type' => 'fronius', 'host' => '1.2.3.4' },
      )
    end

    it 'does not create duplicate chapters' do
      config = described_class.current
      config.update_chapter('devices', { 'v1' => true })
      config.update_chapter('devices', { 'v2' => true })

      expect(config.chapters.where(name: 'devices').count).to eq(1)
    end
  end

  describe '#chapter_completed?' do
    it 'returns false for non-existent chapter' do
      config = described_class.current
      expect(config.chapter_completed?('devices')).to be false
    end

    it 'returns false for chapter with empty data' do
      config = described_class.current
      config.chapters.create!(name: 'devices', data: {})

      expect(config.chapter_completed?('devices')).to be false
    end

    it 'returns true for chapter with data' do
      config = described_class.current
      config.update_chapter('devices', { 'devices' => ['inverter'] })

      expect(config.chapter_completed?('devices')).to be true
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
