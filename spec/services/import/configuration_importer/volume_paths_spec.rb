RSpec.describe 'Import::ConfigurationImporter volume path handling' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:services) { {} }
  let(:raw_compose) { { 'services' => services } }
  let(:stack_reader) do
    instance_double(
      Import::StackReader,
      raw_env: raw_env,
      raw_compose: raw_compose,
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

  context 'when bind mounts are hardcoded inline with ${VAR} interpolation' do
    let(:raw_env) { { 'BASE_DIR' => '/home/user/docker/solectrus' } }
    let(:raw_compose) do
      {
        'services' => {
          'influxdb' => {
            'volumes' => [
              '${BASE_DIR}/influxdb/data:/var/lib/influxdb2',
              '${BASE_DIR}/influxdb/config:/etc/influxdb2',
            ],
          },
          'redis' => { 'volumes' => ['${BASE_DIR}/redis:/data'] },
          'postgresql' => { 'volumes' => ['${BASE_DIR}/postgres:/var/lib/postgresql'] },
        },
      }
    end

    it 'resolves the host source against .env and persists it as volume_path' do
      expect(importer.result[:influxdb]).to include('volume_path' => '/home/user/docker/solectrus/influxdb/data')
      expect(importer.result[:redis]).to include('volume_path' => '/home/user/docker/solectrus/redis')
      expect(importer.result[:postgresql]).to include('volume_path' => '/home/user/docker/solectrus/postgres')
    end
  end

  context 'when postgres mounts a PGDATA subpath instead of the parent dir' do
    let(:raw_env) do
      {
        'BASE_DIR' => '/home/user/docker/solectrus',
        'PGDATA' => '/var/lib/postgresql/data/',
      }
    end
    let(:raw_compose) do
      {
        'services' => {
          'postgresql' => { 'volumes' => ['${BASE_DIR}/postgres/16/data/:${PGDATA}'] },
        },
      }
    end

    it 'strips the trailing /data segment so HELIOS can parent-mount it' do
      expect(importer.result[:postgresql]).to include('volume_path' => '/home/user/docker/solectrus/postgres/16')
    end
  end

  context 'when postgres uses an implicit PGDATA default for the subpath mount' do
    let(:raw_env) { { 'BASE_DIR' => '/srv/stacks' } }
    let(:raw_compose) do
      {
        'services' => {
          'postgresql' => { 'volumes' => ['${BASE_DIR}/pg/data:/var/lib/postgresql/data'] },
        },
      }
    end

    it 'falls back to the postgres image default PGDATA path' do
      expect(importer.result[:postgresql]).to include('volume_path' => '/srv/stacks/pg')
    end
  end

  context 'when postgres mounts a PGDATA subpath but host source does not end in /data' do
    let(:raw_env) { { 'PGDATA' => '/var/lib/postgresql/data' } }
    let(:raw_compose) do
      {
        'services' => {
          'postgresql' => { 'volumes' => ['/mnt/postgres-vol:${PGDATA}'] },
        },
      }
    end

    it 'refuses to guess the parent dir and falls through' do
      expect(importer.result[:postgresql] || {}).not_to have_key('volume_path')
    end
  end

  context 'when the postgres service is named `postgres` (legacy alias)' do
    let(:raw_env) do
      {
        'BASE_DIR' => '/home/user/docker/solectrus',
        'PGDATA' => '/var/lib/postgresql/data/',
      }
    end
    let(:raw_compose) do
      {
        'services' => {
          'postgres' => {
            'image' => 'postgres:16',
            'volumes' => ['${BASE_DIR}/postgres/16/data/:${PGDATA}'],
          },
        },
      }
    end

    it 'resolves the alias via SERVICE_IMAGE_PREFIXES and detects the mount' do
      expect(importer.result[:postgresql]).to include('volume_path' => '/home/user/docker/solectrus/postgres/16')
    end
  end

  context 'when *_VOLUME_PATH env var itself uses ${VAR} interpolation' do
    let(:raw_env) do
      {
        'BASE_DIR' => '/home/user/docker/solectrus',
        'INFLUX_VOLUME_PATH' => '${BASE_DIR}/influxdb',
      }
    end

    it 'resolves the env-var value before storing it as volume_path' do
      expect(importer.result[:influxdb]).to include('volume_path' => '/home/user/docker/solectrus/influxdb')
    end
  end

  context 'when the inline volume uses a relative `./service` path' do
    let(:raw_env) { {} }
    let(:raw_compose) do
      {
        'services' => {
          'influxdb' => { 'volumes' => ['./influxdb:/var/lib/influxdb2'] },
          'redis' => { 'volumes' => ['./redis:/data'] },
        },
      }
    end

    it 'is treated as the default bind mount and dropped' do
      expect(importer.result[:influxdb]).not_to have_key('volume_path')
      expect(importer.result[:redis]).not_to have_key('volume_path')
    end
  end

  context 'when ${VAR} interpolation chains through multiple .env entries' do
    let(:raw_env) do
      {
        'STACK_ROOT' => '/srv/stacks',
        'BASE_DIR' => '${STACK_ROOT}/solectrus',
      }
    end
    let(:raw_compose) do
      {
        'services' => {
          'redis' => { 'volumes' => ['${BASE_DIR}/redis:/data'] },
        },
      }
    end

    it 'follows the chain of references' do
      expect(importer.result[:redis]).to include('volume_path' => '/srv/stacks/solectrus/redis')
    end
  end

  context 'when ${VAR} interpolation forms a cycle' do
    let(:raw_env) do
      {
        'A' => '${B}',
        'B' => '${A}',
      }
    end
    let(:raw_compose) do
      { 'services' => { 'redis' => { 'volumes' => ['${A}:/data'] } } }
    end

    it 'returns no volume_path instead of recursing forever' do
      expect(importer.result[:redis] || {}).not_to have_key('volume_path')
    end
  end
end
