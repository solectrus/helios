RSpec.describe 'Import::ConfigurationImporter volume path handling' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:services) { {} }
  let(:stack_reader) do
    instance_double(
      Import::StackReader,
      raw_env: raw_env,
      raw_compose: { 'services' => services },
      services: services,
      stack_dir: '/srv/solectrus',
    ).tap do |double|
      allow(double).to receive(:service) { |name| services[name] }
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

  context 'when TRAEFIK_VOLUME_PATH points outside the stack directory' do
    let(:services) do
      {
        'traefik' => { 'image' => 'traefik:v3' },
        'dashboard' => { 'labels' => ['traefik.http.routers.dashboard.rule=Host(`app.example.com`)'] },
      }
    end
    let(:raw_env) { { 'TRAEFIK_VOLUME_PATH' => '/volume1/docker/solectrus/traefik' } }

    it 'preserves the absolute path as reverse_proxy.volume_path' do
      expect(importer.result[:reverse_proxy]).to include('volume_path' => '/volume1/docker/solectrus/traefik')
    end

    it 'does not leak TRAEFIK_VOLUME_PATH into unmanaged env_vars' do
      expect(importer.result[:unmanaged]&.dig('env_vars') || {}).not_to have_key('TRAEFIK_VOLUME_PATH')
    end
  end

  context 'when TRAEFIK_VOLUME_PATH is the default relative mount' do
    let(:services) do
      {
        'traefik' => { 'image' => 'traefik:v3' },
        'dashboard' => { 'labels' => ['traefik.http.routers.dashboard.rule=Host(`app.example.com`)'] },
      }
    end
    let(:raw_env) { { 'TRAEFIK_VOLUME_PATH' => './traefik' } }

    it 'does not persist it as reverse_proxy.volume_path' do
      expect(importer.result[:reverse_proxy] || {}).not_to have_key('volume_path')
    end

    it 'does not leak TRAEFIK_VOLUME_PATH into unmanaged env_vars' do
      expect(importer.result[:unmanaged]&.dig('env_vars') || {}).not_to have_key('TRAEFIK_VOLUME_PATH')
    end
  end
end
