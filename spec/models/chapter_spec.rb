RSpec.describe Chapter do
  subject(:chapter) do
    described_class.new(configuration:, kind: 'inverter', name: 'inverter', data: {})
  end

  let(:configuration) { Configuration.current }

  describe 'KINDS constant' do
    it 'contains all expected chapter kinds' do
      expect(described_class::KINDS).to eq(
        %w[
          inverter battery wallbox car heatpump consumer
          forecast system reverse_proxy backup sensors
        ],
      )
    end
  end

  describe 'DEVICE_KINDS constant' do
    it 'contains all device kinds' do
      expect(described_class::DEVICE_KINDS).to eq(
        %w[inverter battery wallbox car heatpump consumer],
      )
    end
  end

  describe 'SINGLETON_KINDS constant' do
    it 'contains all singleton kinds' do
      expect(described_class::SINGLETON_KINDS).to eq(
        %w[forecast system reverse_proxy backup sensors],
      )
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:configuration) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:kind) }

    it {
      expect(chapter).to validate_inclusion_of(:kind).in_array(
        described_class::KINDS,
      )
    }

    it { is_expected.to validate_presence_of(:name) }

    it {
      expect(chapter).to validate_uniqueness_of(:name).scoped_to(
        :configuration_id,
        :kind,
      )
    }
  end

  describe '#completed?' do
    it 'returns false when data is empty' do
      chapter = described_class.new(
        configuration:, kind: 'inverter', name: 'inverter', data: {},
      )
      expect(chapter.completed?).to be false
    end

    it 'returns false when data is nil' do
      chapter = described_class.new(
        configuration:, kind: 'inverter', name: 'inverter', data: nil,
      )
      expect(chapter.completed?).to be false
    end

    it 'returns true when data is present' do
      chapter = described_class.new(
        configuration:,
        kind: 'inverter',
        name: 'inverter',
        data: { 'data_source' => 'senec_local' },
      )
      expect(chapter.completed?).to be true
    end
  end

  describe '#singleton?' do
    it 'returns true for singleton kinds' do
      Chapter::SINGLETON_KINDS.each do |kind|
        c = described_class.new(kind:)
        expect(c.singleton?).to be true
      end
    end

    it 'returns false for device kinds' do
      Chapter::DEVICE_KINDS.each do |kind|
        c = described_class.new(kind:)
        expect(c.singleton?).to be false
      end
    end
  end

  describe '#device?' do
    it 'returns true for device kinds' do
      Chapter::DEVICE_KINDS.each do |kind|
        c = described_class.new(kind:)
        expect(c.device?).to be true
      end
    end

    it 'returns false for singleton kinds' do
      Chapter::SINGLETON_KINDS.each do |kind|
        c = described_class.new(kind:)
        expect(c.device?).to be false
      end
    end
  end

  describe 'data storage' do
    it 'stores and retrieves JSON data' do
      chapter =
        described_class.create!(
          configuration:,
          kind: 'inverter',
          name: 'Dach Süd',
          data: {
            'data_source' => 'senec_local',
            'senec_host' => '192.168.1.100',
            'senec_interval' => 5,
          },
        )

      chapter.reload
      expect(chapter.data).to eq(
        'data_source' => 'senec_local',
        'senec_host' => '192.168.1.100',
        'senec_interval' => 5,
      )
    end

    it 'allows multiple devices of the same kind with different names' do
      described_class.create!(
        configuration:, kind: 'inverter', name: 'Dach Süd', data: {},
      )
      described_class.create!(
        configuration:, kind: 'inverter', name: 'Balkonkraftwerk', data: {},
      )

      expect(configuration.chapters.where(kind: 'inverter').count).to eq(2)
    end

    it 'prevents duplicate names within the same kind' do
      described_class.create!(
        configuration:, kind: 'inverter', name: 'Dach Süd', data: {},
      )
      duplicate = described_class.new(
        configuration:, kind: 'inverter', name: 'Dach Süd', data: {},
      )

      expect(duplicate).not_to be_valid
    end

    it 'defaults to empty hash' do
      chapter = described_class.create!(
        configuration:, kind: 'system', name: 'system',
      )
      expect(chapter.data).to eq({})
    end
  end
end
