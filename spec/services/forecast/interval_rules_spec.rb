RSpec.describe Forecast::IntervalRules do
  describe '.normalize' do
    it 'drops the donor value for pvnode (collector ignores it at runtime)' do
      expect(described_class.normalize(provider: 'pvnode', interval: '900')).to be_nil
      expect(described_class.normalize(provider: 'pvnode', interval: '2')).to be_nil
      expect(described_class.normalize(provider: 'pvnode', interval: nil)).to be_nil
    end

    it 'passes solcast values through unchanged — the operator picks the cadence' do
      expect(described_class.normalize(provider: 'solcast', interval: '8640')).to eq('8640')
      expect(described_class.normalize(provider: 'solcast', interval: '17280')).to eq('17280')
      expect(described_class.normalize(provider: 'solcast', interval: '900')).to eq('900')
    end

    it 'passes forecast.solar values through unchanged' do
      expect(described_class.normalize(provider: 'forecast.solar', interval: '900')).to eq('900')
      expect(described_class.normalize(provider: 'forecast.solar', interval: '100')).to eq('100')
    end

    it 'drops blank values regardless of provider' do
      expect(described_class.normalize(provider: 'solcast', interval: nil)).to be_nil
      expect(described_class.normalize(provider: 'forecast.solar', interval: '')).to be_nil
    end
  end

  describe '.emit_value' do
    it 'returns nil for pvnode regardless of input (variable is omitted entirely)' do
      expect(described_class.emit_value(provider: 'pvnode', interval: '900')).to be_nil
      expect(described_class.emit_value(provider: 'pvnode', interval: '2')).to be_nil
      expect(described_class.emit_value(provider: 'pvnode', interval: nil)).to be_nil
    end

    it "returns the operator's value for solcast and forecast.solar when set" do
      expect(described_class.emit_value(provider: 'solcast', interval: '8640')).to eq('8640')
      expect(described_class.emit_value(provider: 'forecast.solar', interval: '3600')).to eq('3600')
    end

    it 'falls back to the 900s baseline when no value is set' do
      expect(described_class.emit_value(provider: 'solcast', interval: nil)).to eq('900')
      expect(described_class.emit_value(provider: 'forecast.solar', interval: '')).to eq('900')
    end
  end
end
