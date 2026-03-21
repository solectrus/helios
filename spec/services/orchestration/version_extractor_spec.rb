RSpec.describe Orchestration::VersionExtractor do
  def build_container(image:, labels: {}, env: [])
    instance_double(
      Docker::Container,
      info: { 'Image' => image },
      json: { 'Config' => { 'Labels' => labels, 'Env' => env } },
    )
  end

  describe '.extract' do
    it 'extracts SOLECTRUS version from COMMIT_VERSION' do
      container = build_container(
        image: 'ghcr.io/solectrus/solectrus:latest',
        env: ['COMMIT_VERSION=0.18.2'],
      )

      expect(described_class.extract(container)).to eq('0.18.2')
    end

    it 'extracts InfluxDB version from env' do
      container = build_container(
        image: 'influxdb:2.7-alpine',
        env: ['INFLUXDB_VERSION=2.7.11'],
      )

      expect(described_class.extract(container)).to eq('2.7.11')
    end

    it 'extracts PostgreSQL version from PG_VERSION' do
      container = build_container(
        image: 'postgres:18-alpine',
        env: ['PG_VERSION=18.4'],
      )

      expect(described_class.extract(container)).to eq('18.4')
    end

    it 'falls back to OCI label' do
      container = build_container(
        image: 'some/unknown:latest',
        labels: { 'org.opencontainers.image.version' => '3.2.1' },
      )

      expect(described_class.extract(container)).to eq('3.2.1')
    end

    it 'falls back to env version pattern' do
      container = build_container(
        image: 'some/unknown:latest',
        env: ['APP_VERSION=1.0.0'],
      )

      expect(described_class.extract(container)).to eq('1.0.0')
    end

    it 'strips leading v from version' do
      container = build_container(
        image: 'some/unknown:latest',
        labels: { 'org.opencontainers.image.version' => 'v2.0.0' },
      )

      expect(described_class.extract(container)).to eq('2.0.0')
    end

    it 'returns nil when no version found' do
      container = build_container(image: 'some/unknown:latest')

      expect(described_class.extract(container)).to be_nil
    end
  end
end
