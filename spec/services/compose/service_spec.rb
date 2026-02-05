RSpec.describe Compose::Service do
  describe '#image' do
    it 'returns the image name' do
      service = described_class.new('test', { 'image' => 'postgres:18-alpine' })
      expect(service.image).to eq('postgres:18-alpine')
    end

    it 'returns nil when not set' do
      service = described_class.new('test', {})
      expect(service.image).to be_nil
    end
  end

  describe '#image_name' do
    it 'returns the image name without tag' do
      service = described_class.new('test', { 'image' => 'postgres:18-alpine' })
      expect(service.image_name).to eq('postgres')
    end

    it 'returns the full name when no tag' do
      service = described_class.new('test', { 'image' => 'postgres' })
      expect(service.image_name).to eq('postgres')
    end
  end

  describe '#image_tag' do
    it 'returns the tag from image' do
      service = described_class.new('test', { 'image' => 'postgres:18-alpine' })
      expect(service.image_tag).to eq('18-alpine')
    end

    it 'returns latest when no tag specified' do
      service = described_class.new('test', { 'image' => 'postgres' })
      expect(service.image_tag).to eq('latest')
    end
  end

  describe '#display_name' do
    it 'returns PostgreSQL for postgres image' do
      service = described_class.new('db', { 'image' => 'postgres:18-alpine' })
      expect(service.display_name).to eq('PostgreSQL')
    end

    it 'returns Redis for redis image' do
      service = described_class.new('cache', { 'image' => 'redis:8-alpine' })
      expect(service.display_name).to eq('Redis')
    end

    it 'returns InfluxDB for influxdb image' do
      service = described_class.new('tsdb', { 'image' => 'influxdb:2-alpine' })
      expect(service.display_name).to eq('InfluxDB')
    end

    it 'returns SOLECTRUS for solectrus image' do
      service =
        described_class.new(
          'dashboard',
          { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
        )
      expect(service.display_name).to eq('SOLECTRUS')
    end

    it 'returns service name for unknown images' do
      service =
        described_class.new('my-custom-service', { 'image' => 'nginx:latest' })
      expect(service.display_name).to eq('my-custom-service')
    end

    it 'returns service name when image is nil' do
      service = described_class.new('no-image', {})
      expect(service.display_name).to eq('no-image')
    end
  end

  describe '#ports' do
    it 'returns the ports array' do
      service =
        described_class.new('test', { 'ports' => %w[3000:3000 8080:80] })
      expect(service.ports).to eq(%w[3000:3000 8080:80])
    end

    it 'returns empty array when not set' do
      service = described_class.new('test', {})
      expect(service.ports).to eq([])
    end
  end

  describe '#public_port' do
    it 'returns the first public port from string format' do
      service = described_class.new('test', { 'ports' => ['3000:3000'] })
      expect(service.public_port).to eq(3000)
    end

    it 'returns the published port from hash format' do
      service =
        described_class.new(
          'test',
          { 'ports' => [{ 'published' => 8080, 'target' => 80 }] },
        )
      expect(service.public_port).to eq(8080)
    end

    it 'returns nil when no ports' do
      service = described_class.new('test', {})
      expect(service.public_port).to be_nil
    end
  end

  describe '#environment' do
    it 'returns the environment hash' do
      service =
        described_class.new('test', { 'environment' => { 'FOO' => 'bar' } })
      expect(service.environment).to eq({ 'FOO' => 'bar' })
    end

    it 'returns empty hash when not set' do
      service = described_class.new('test', {})
      expect(service.environment).to eq({})
    end
  end

  describe '#volumes' do
    it 'returns the volumes array' do
      service = described_class.new('test', { 'volumes' => ['./data:/data'] })
      expect(service.volumes).to eq(['./data:/data'])
    end

    it 'returns empty array when not set' do
      service = described_class.new('test', {})
      expect(service.volumes).to eq([])
    end
  end

  describe '#depends_on' do
    it 'returns the depends_on hash' do
      service =
        described_class.new(
          'test',
          { 'depends_on' => { 'db' => { 'condition' => 'service_healthy' } } },
        )
      expect(service.depends_on).to eq(
        { 'db' => { 'condition' => 'service_healthy' } },
      )
    end

    it 'returns empty hash when not set' do
      service = described_class.new('test', {})
      expect(service.depends_on).to eq({})
    end
  end

  describe '#restart' do
    it 'returns the restart policy' do
      service = described_class.new('test', { 'restart' => 'unless-stopped' })
      expect(service.restart).to eq('unless-stopped')
    end
  end

  describe '#healthcheck' do
    it 'returns the healthcheck config' do
      healthcheck = { 'test' => %w[CMD pg_isready], 'interval' => '10s' }
      service = described_class.new('test', { 'healthcheck' => healthcheck })
      expect(service.healthcheck).to eq(healthcheck)
    end
  end

  describe '#to_h' do
    it 'returns the config as hash' do
      config = {
        'image' => 'postgres:18-alpine',
        'restart' => 'unless-stopped',
      }
      service = described_class.new('test', config)
      expect(service.to_h).to eq(config)
    end
  end

  describe '#helios?' do
    it 'returns true for helios:latest image' do
      service = described_class.new('helios', { 'image' => 'helios:latest' })
      expect(service.helios?).to be true
    end

    it 'returns true for ghcr.io/solectrus/helios:latest image' do
      service =
        described_class.new(
          'helios',
          { 'image' => 'ghcr.io/solectrus/helios:latest' },
        )
      expect(service.helios?).to be true
    end

    it 'returns false for other images' do
      service = described_class.new('test', { 'image' => 'postgres:18-alpine' })
      expect(service.helios?).to be false
    end

    it 'returns false when image is nil' do
      service = described_class.new('test', {})
      expect(service.helios?).to be false
    end
  end
end
