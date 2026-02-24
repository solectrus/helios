RSpec.describe Compose::ServiceStore do
  after do
    described_class.clear_all
  end

  describe '.set and .get' do
    it 'stores and retrieves an error message' do
      described_class.set('influxdb', 'Port 8086 is already allocated')

      expect(described_class.get('influxdb')).to eq('Port 8086 is already allocated')
    end

    it 'returns nil for unknown services' do
      expect(described_class.get('unknown')).to be_nil
    end

    it 'handles string and symbol service names consistently' do
      described_class.set(:influxdb, 'some error')

      expect(described_class.get('influxdb')).to eq('some error')
    end
  end

  describe '.clear' do
    it 'removes the error for a specific service' do
      described_class.set('influxdb', 'some error')
      described_class.set('redis', 'another error')

      described_class.clear('influxdb')

      expect(described_class.get('influxdb')).to be_nil
      expect(described_class.get('redis')).to eq('another error')
    end
  end

  describe '.clear_all' do
    it 'removes all stored errors and pending states' do
      described_class.set('influxdb', 'error 1')
      described_class.set('redis', 'error 2')
      described_class.mark_pending('influxdb')

      described_class.clear_all

      expect(described_class.get('influxdb')).to be_nil
      expect(described_class.get('redis')).to be_nil
      expect(described_class.pending?('influxdb')).to be false
    end
  end

  describe '.mark_pending and .pending?' do
    it 'marks a service as pending' do
      described_class.mark_pending('influxdb')

      expect(described_class.pending?('influxdb')).to be true
    end

    it 'returns false for non-pending services' do
      expect(described_class.pending?('influxdb')).to be false
    end
  end

  describe '.clear_pending' do
    it 'removes pending state for a specific service' do
      described_class.mark_pending('influxdb')
      described_class.mark_pending('redis')

      described_class.clear_pending('influxdb')

      expect(described_class.pending?('influxdb')).to be false
      expect(described_class.pending?('redis')).to be true
    end
  end

  describe '.clear_all_pending' do
    it 'removes all pending states' do
      described_class.mark_pending('influxdb')
      described_class.mark_pending('redis')

      described_class.clear_all_pending

      expect(described_class.pending?('influxdb')).to be false
      expect(described_class.pending?('redis')).to be false
    end
  end
end
