require 'rails_helper'

RSpec.describe Chapter do
  subject(:chapter) do
    described_class.new(configuration:, name: 'devices', data: {})
  end

  let(:configuration) { Configuration.current }

  describe 'NAMES constant' do
    it 'contains all expected chapter names' do
      expect(described_class::NAMES).to eq(
        %w[devices inverter wallbox heatpump mqtt forecast system],
      )
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:configuration) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }

    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:configuration_id) }

    it { is_expected.to validate_inclusion_of(:name).in_array(described_class::NAMES) }
  end

  describe '#completed?' do
    it 'returns false when data is empty' do
      chapter = described_class.new(configuration:, name: 'devices', data: {})
      expect(chapter.completed?).to be false
    end

    it 'returns false when data is nil' do
      chapter = described_class.new(configuration:, name: 'devices', data: nil)
      expect(chapter.completed?).to be false
    end

    it 'returns true when data is present' do
      chapter =
        described_class.new(
          configuration:,
          name: 'devices',
          data: {
            'devices' => ['inverter'],
          },
        )
      expect(chapter.completed?).to be true
    end
  end

  describe 'data storage' do
    it 'stores and retrieves JSON data' do
      chapter =
        described_class.create!(
          configuration:,
          name: 'inverter',
          data: {
            'type' => 'senec',
            'host' => '192.168.1.100',
            'options' => {
              'interval' => 5,
            },
          },
        )

      chapter.reload
      expect(chapter.data).to eq(
        'type' => 'senec',
        'host' => '192.168.1.100',
        'options' => {
          'interval' => 5,
        },
      )
    end

    it 'stores arrays correctly' do
      chapter =
        described_class.create!(
          configuration:,
          name: 'devices',
          data: {
            'devices' => %w[inverter battery wallbox],
          },
        )

      chapter.reload
      expect(chapter.data['devices']).to eq(%w[inverter battery wallbox])
    end

    it 'defaults to empty hash' do
      chapter = described_class.create!(configuration:, name: 'mqtt')
      expect(chapter.data).to eq({})
    end
  end
end
