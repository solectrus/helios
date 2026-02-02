require 'rails_helper'

RSpec.describe Configuration do
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

  describe '#installation_date' do
    it 'gets and sets installation date' do
      config = described_class.current
      config.installation_date = '2024-01-15'
      config.save!
      config.reload

      expect(config.installation_date).to eq('2024-01-15')
    end
  end

  describe '#timezone' do
    it 'gets and sets timezone' do
      config = described_class.current
      config.timezone = 'Europe/Berlin'
      config.save!
      config.reload

      expect(config.timezone).to eq('Europe/Berlin')
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
