RSpec.describe Reading do
  let(:fresh_time) { 5.minutes.ago }

  describe '#formatted' do
    it 'returns the empty placeholder for nil values' do
      expect(described_class.new(value: nil).formatted).to eq(Reading::EMPTY_DISPLAY)
    end

    it 'renders integers without decimals' do
      expect(described_class.new(value: 42.0).formatted).to eq('42')
    end

    it 'rounds floats to the requested precision' do
      expect(described_class.new(value: 4.236).formatted(precision: 1)).to eq('4.2')
      expect(described_class.new(value: 4.236).formatted(precision: 2)).to eq('4.24')
    end

    it 'falls back to to_s for non-numeric values' do
      expect(described_class.new(value: 'INITIAL').formatted).to eq('INITIAL')
    end
  end

  describe '#freshness_class' do
    it 'is muted when no value is present' do
      expect(described_class.new(value: nil).freshness_class).to eq('text-base-content/30')
    end

    it 'warns when older than the staleness threshold' do
      expect(described_class.new(value: 1, time: 2.hours.ago).freshness_class).to eq('text-warning')
    end

    it 'is success-colored for fresh values' do
      expect(described_class.new(value: 1, time: fresh_time).freshness_class).to eq('text-success')
    end
  end

  describe '#boolean_label' do
    it 'maps boolean strings to translated labels' do
      expect(described_class.new(value: 'true').boolean_label).to eq(I18n.t('common.boolean_yes'))
      expect(described_class.new(value: 'false').boolean_label).to eq(I18n.t('common.boolean_no'))
    end

    it 'returns nil for non-boolean values' do
      expect(described_class.new(value: 'INITIAL').boolean_label).to be_nil
      expect(described_class.new(value: 42).boolean_label).to be_nil
    end
  end
end
