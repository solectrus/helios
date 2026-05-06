RSpec.describe Orchestration::PendingOperations do
  after do
    described_class.clear_all
  end

  describe '.set and .get' do
    it 'stores and retrieves an operation' do
      described_class.set('redis', :recreate)

      expect(described_class.get('redis')).to eq(:recreate)
    end

    it 'returns nil for unknown services' do
      expect(described_class.get('unknown')).to be_nil
    end

    it 'normalises symbol and string service names' do
      described_class.set(:redis, :recreate)

      expect(described_class.get('redis')).to eq(:recreate)
    end

    it 'coerces string operations to symbols' do
      described_class.set('redis', 'recreate')

      expect(described_class.get('redis')).to eq(:recreate)
    end
  end

  describe '.clear' do
    it 'removes the operation for a specific service' do
      described_class.set('redis', :recreate)
      described_class.set('influxdb', :start)

      described_class.clear('redis')

      expect(described_class.get('redis')).to be_nil
      expect(described_class.get('influxdb')).to eq(:start)
    end
  end

  describe '.clear_all' do
    it 'removes all stored operations' do
      described_class.set('redis', :recreate)
      described_class.set('influxdb', :start)

      described_class.clear_all

      expect(described_class.get('redis')).to be_nil
      expect(described_class.get('influxdb')).to be_nil
    end
  end
end
