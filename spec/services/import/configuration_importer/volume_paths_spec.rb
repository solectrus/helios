RSpec.describe 'Import::ConfigurationImporter volume path handling' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:stack_reader) do
    instance_double(
      Import::StackReader,
      raw_env: raw_env,
      raw_compose: { 'services' => {} },
      services: {},
      stack_dir: '/srv/solectrus',
    ).tap do |double|
      allow(double).to receive(:service).and_return(nil)
    end
  end

  context 'when the path resolves to the default bind mount next to compose.yaml' do
    let(:raw_env) do
      {
        'DB_VOLUME_PATH' => '/srv/solectrus/postgresql',
        'INFLUX_VOLUME_PATH' => '/srv/solectrus/influxdb/',
        'REDIS_VOLUME_PATH' => '/srv/solectrus/../solectrus/redis',
      }
    end

    it 'drops the path — the relative default is equivalent' do
      expect(importer.result[:postgresql]).not_to have_key('volume_path')
      expect(importer.result[:influxdb]).not_to have_key('volume_path')
      expect(importer.result[:redis]).not_to have_key('volume_path')
    end
  end

  context 'when the path points outside the stack directory' do
    let(:raw_env) do
      {
        'DB_VOLUME_PATH' => '/volume1/docker/solectrus/postgresql',
        'INFLUX_VOLUME_PATH' => '/mnt/ssd/influxdb',
        'REDIS_VOLUME_PATH' => '/volume1/docker/solectrus/redis',
      }
    end

    it 'preserves the absolute path as volume_path' do
      expect(importer.result[:postgresql]).to include('volume_path' => '/volume1/docker/solectrus/postgresql')
      expect(importer.result[:influxdb]).to include('volume_path' => '/mnt/ssd/influxdb')
      expect(importer.result[:redis]).to include('volume_path' => '/volume1/docker/solectrus/redis')
    end
  end

  context 'when the .env uses a relative path' do
    let(:raw_env) do
      { 'DB_VOLUME_PATH' => './postgresql', 'INFLUX_VOLUME_PATH' => './influxdb', 'REDIS_VOLUME_PATH' => './redis' }
    end

    it 'ignores it — HELIOS already defaults to the same relative mount' do
      expect(importer.result[:postgresql]).not_to have_key('volume_path')
      expect(importer.result[:influxdb]).not_to have_key('volume_path')
      expect(importer.result[:redis]).not_to have_key('volume_path')
    end
  end
end
