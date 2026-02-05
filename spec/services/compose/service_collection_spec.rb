RSpec.describe Compose::ServiceCollection do
  let(:services_hash) do
    {
      'postgresql' => { 'image' => 'postgres:18-alpine' },
      'redis' => { 'image' => 'redis:8-alpine' },
      'dashboard' => { 'image' => 'solectrus/solectrus:latest' },
    }
  end

  let(:collection) { described_class.new(services_hash) }

  describe '#all' do
    it 'returns all services as Service objects' do
      services = collection.all
      expect(services.length).to eq(3)
      expect(services).to all(be_a(Compose::Service))
    end
  end

  describe '#find' do
    it 'finds a service by name' do
      service = collection.find('postgresql')
      expect(service).to be_a(Compose::Service)
      expect(service.name).to eq('postgresql')
      expect(service.image).to eq('postgres:18-alpine')
    end

    it 'returns nil for non-existent service' do
      expect(collection.find('nonexistent')).to be_nil
    end

    it 'accepts symbols' do
      service = collection.find(:redis)
      expect(service.name).to eq('redis')
    end
  end

  describe '#[]' do
    it 'is an alias for find' do
      service = collection['postgresql']
      expect(service.image).to eq('postgres:18-alpine')
    end
  end

  describe '#exists?' do
    it 'returns true for existing service' do
      expect(collection.exists?('postgresql')).to be true
    end

    it 'returns false for non-existent service' do
      expect(collection.exists?('nonexistent')).to be false
    end
  end

  describe '#names' do
    it 'returns all service names' do
      expect(collection.names).to eq(%w[postgresql redis dashboard])
    end
  end

  describe '#count' do
    it 'returns the number of services' do
      expect(collection.count).to eq(3)
    end
  end

  describe '#empty?' do
    it 'returns false when services exist' do
      expect(collection.empty?).to be false
    end

    it 'returns true when no services' do
      empty_collection = described_class.new({})
      expect(empty_collection.empty?).to be true
    end
  end

  describe '#each' do
    it 'iterates over all services' do
      names = collection.map(&:name)
      expect(names).to eq(%w[postgresql redis dashboard])
    end

    it 'is Enumerable' do
      images = collection.map(&:image)
      expect(images).to include('postgres:18-alpine', 'redis:8-alpine')
    end
  end

  describe '#sorted' do
    let(:services_hash) do
      {
        'nginx' => { 'image' => 'nginx:alpine' },
        'redis' => { 'image' => 'redis:8-alpine' },
        'postgresql' => { 'image' => 'postgres:18-alpine' },
        'whoami' => { 'image' => 'traefik/whoami:latest' },
        'dashboard' => { 'image' => 'solectrus/solectrus:latest' },
        'influxdb' => { 'image' => 'influxdb:2-alpine' },
      }
    end

    it 'returns services in priority order: dashboard, influxdb, postgresql, redis, then alphabetically' do
      names = collection.sorted.map(&:name)
      expect(names).to eq(%w[dashboard influxdb postgresql redis nginx whoami])
    end

    it 'returns Service objects' do
      expect(collection.sorted).to all(be_a(Compose::Service))
    end

    context 'with helios service' do
      let(:services_hash) do
        {
          'dashboard' => { 'image' => 'solectrus/solectrus:latest' },
          'helios' => { 'image' => 'helios:latest' },
          'redis' => { 'image' => 'redis:8-alpine' },
        }
      end

      it 'returns helios last, after all other services' do
        names = collection.sorted.map(&:name)
        expect(names.last).to eq('helios')
      end
    end
  end
end
