RSpec.describe Export::Builder do
  before { with_config_yaml }

  let(:tmp_dir) { Rails.configuration.data_path }
  let(:compose_path) { File.join(tmp_dir, 'compose.yaml') }
  let(:env_path) { File.join(tmp_dir, '.env') }

  let(:configuration) do
    config = Configuration.current
    config.update('system', { 'installation_date' => '2024-01-15', 'timezone' => 'Europe/Berlin' })
    config
  end

  describe '#write!' do
    before { described_class.new(configuration).write! }

    it_behaves_like 'valid Docker Compose configuration'

    it 'creates compose.yaml and .env files' do
      expect(File.exist?(compose_path)).to be true
      expect(File.exist?(env_path)).to be true
    end

    it 'creates data directories' do
      expect(Dir.exist?(File.join(tmp_dir, 'postgresql'))).to be true
      expect(Dir.exist?(File.join(tmp_dir, 'redis'))).to be true
      expect(Dir.exist?(File.join(tmp_dir, 'influxdb'))).to be true
    end
  end

  describe '#write_if_stale!' do
    let(:builder) { described_class.new(configuration) }

    before { builder.write! }

    it 'is a no-op when targets are newer than config.yaml' do
      original_mtime = File.mtime(compose_path)
      builder.write_if_stale!
      expect(File.mtime(compose_path)).to eq(original_mtime)
    end

    it 'regenerates when config.yaml is newer than compose.yaml' do
      sleep 0.01
      FileUtils.touch(Configuration.path)

      expect { builder.write_if_stale! }.to(change { File.mtime(compose_path) })
    end

    it 'regenerates when compose.yaml is missing' do
      File.delete(compose_path)
      builder.write_if_stale!
      expect(File.exist?(compose_path)).to be true
    end

    it 'regenerates when .env is missing' do
      File.delete(env_path)
      builder.write_if_stale!
      expect(File.exist?(env_path)).to be true
    end
  end

  describe 'managed image preservation on write!' do
    let(:builder) { described_class.new(configuration) }

    it 'preserves a legacy InfluxDB image instead of auto-upgrading it' do
      stub_const('DockerImages::INFLUXDB',
                 { current: 'influxdb:9-alpine', legacy: ['influxdb:8-alpine'].freeze }.freeze)
      configuration.update('influxdb', configuration.influxdb.merge('image' => 'influxdb:8-alpine'))
      builder.write!
      expect(Configuration.current.influxdb.image).to eq('influxdb:8-alpine')
      expect(File.read(compose_path)).to include('influxdb:8-alpine')
    end

    it 'preserves the unmaintained containrrr Watchtower repo verbatim' do
      configuration.update('watchtower', { 'image' => 'containrrr/watchtower:latest' })
      builder.write!
      expect(Configuration.current.watchtower.image).to eq('containrrr/watchtower:latest')
    end

    it 'preserves a user-pinned image' do
      configuration.update('influxdb', configuration.influxdb.merge('image' => 'influxdb:8.5-alpine'))
      builder.write!
      expect(Configuration.current.influxdb.image).to eq('influxdb:8.5-alpine')
    end
  end

  # The PostgreSQL image's data directory moved between major versions, so
  # HELIOS bind-mounts the target the running image expects: `postgres:17`
  # and older → `/var/lib/postgresql/data`, `postgres:18`+ → the parent
  # `/var/lib/postgresql`. No PGDATA override is synthesized. See ADR-0003.
  describe 'PostgreSQL mount target by image major version' do
    def postgresql_volume
      Compose.load.services.find('postgresql').config['volumes'].first
    end

    context 'with postgres:18 (the HELIOS default image)' do
      before { described_class.new(configuration).write! }

      it 'bind-mounts the parent /var/lib/postgresql' do
        expect(postgresql_volume).to eq('${DB_VOLUME_PATH}:/var/lib/postgresql')
      end

      it 'emits no PGDATA override' do
        expect(Env.load['PGDATA']).to be_nil
        expect(Compose.load.services.find('postgresql').environment).not_to include('PGDATA')
      end
    end

    context 'with an imported postgres:16 image' do
      let(:configuration) do
        config = super()
        config.update('postgresql', { 'image' => 'postgres:16-alpine' })
        config
      end

      before { described_class.new(configuration).write! }

      it 'bind-mounts the version-native /var/lib/postgresql/data' do
        expect(postgresql_volume).to eq('${DB_VOLUME_PATH}:/var/lib/postgresql/data')
      end

      it 'emits no PGDATA override' do
        expect(Env.load['PGDATA']).to be_nil
        expect(Compose.load.services.find('postgresql').environment).not_to include('PGDATA')
      end
    end
  end

  describe 'compose file generation' do
    before { described_class.new(configuration).write! }

    it 'sets project name to solectrus' do
      compose = Compose.load
      expect(compose.name).to eq('solectrus')
    end

    it 'includes all required core services' do
      compose = Compose.load
      expect(compose.services.names).to contain_exactly(
        'postgresql',
        'redis',
        'influxdb',
        'dashboard',
        'watchtower',
        'helios',
      )
    end

    it 'omits power-splitter when its mandatory sensor mappings are missing' do
      compose = Compose.load
      expect(compose.services.names).not_to include('power-splitter')
    end

    it 'configures postgresql with healthcheck' do
      compose = Compose.load
      postgresql = compose.services.find('postgresql')

      expect(postgresql.image).to eq('postgres:18-alpine')
      expect(postgresql.healthcheck).to include('test', 'interval')
    end

    context 'with Docker Engine 25.0 or newer' do
      before do
        allow(Orchestration::Connection).to receive(:engine_version).and_return(Gem::Version.new('25.0.3'))
        described_class.new(configuration).write!
      end

      it 'includes start_interval in healthchecks' do
        compose = Compose.load
        expect(compose.services.find('postgresql').healthcheck).to include('start_interval' => '2s')
      end
    end

    context 'with Docker Engine older than 25.0' do
      before do
        allow(Orchestration::Connection).to receive(:engine_version).and_return(Gem::Version.new('24.0.2'))
        described_class.new(configuration).write!
      end

      it 'omits start_interval from healthchecks' do
        compose = Compose.load
        expect(compose.services.find('postgresql').healthcheck).not_to include('start_interval')
      end
    end

    context 'when the Docker daemon is unreachable' do
      before do
        allow(Orchestration::Connection).to receive(:engine_version).and_return(nil)
        described_class.new(configuration).write!
      end

      it 'omits start_interval from healthchecks' do
        compose = Compose.load
        expect(compose.services.find('postgresql').healthcheck).not_to include('start_interval')
      end
    end

    it 'declares scope, cleanup, and interval as env vars on the watchtower service' do
      compose = Compose.load
      watchtower = compose.services.find('watchtower')
      expect(watchtower.environment).to include(
        'WATCHTOWER_POLL_INTERVAL',
        'WATCHTOWER_SCOPE',
        'WATCHTOWER_CLEANUP',
      )
      expect(watchtower.config).not_to have_key('command')
    end

    it 'writes WATCHTOWER_SCOPE and WATCHTOWER_CLEANUP to .env' do
      env = Env.load
      expect(env['WATCHTOWER_SCOPE']).to eq('solectrus')
      expect(env['WATCHTOWER_CLEANUP']).to eq('true')
    end

    context 'when the update interval is configured' do
      before do
        configuration.update('system', configuration.system.merge('update_interval' => '3600'))
        described_class.new(configuration).write!
      end

      it 'writes the configured value to .env' do
        env = Env.load
        expect(env['WATCHTOWER_POLL_INTERVAL']).to eq('3600')
      end
    end

    context 'when the update interval is not configured' do
      it 'falls back to the daily default in .env' do
        env = Env.load
        expect(env['WATCHTOWER_POLL_INTERVAL']).to eq(ConfigSchema::DEFAULT_UPDATE_INTERVAL)
      end
    end

    it 'configures dashboard with depends_on' do
      compose = Compose.load
      dashboard = compose.services.find('dashboard')

      expect(dashboard.depends_on.keys).to include(
        'postgresql',
        'redis',
        'influxdb',
      )
    end

    it 'includes a do-not-edit header comment' do
      content = File.read(compose_path)
      expect(content).to include('DO NOT EDIT THIS FILE')
      expect(content).to include('generated by HELIOS')
    end

    it 'forwards the base secrets and TZ to the helios container' do
      compose = Compose.load
      helios = compose.services.find('helios')
      expect(helios.environment).to contain_exactly('TZ', 'ADMIN_PASSWORD', 'SECRET_KEY_BASE')
    end
  end

  describe 'env file generation' do
    before { described_class.new(configuration).write! }

    it 'sets user configuration' do
      env = Env.load
      expect(env['INSTALLATION_DATE']).to eq('2024-01-15')
      expect(env['TZ']).to eq('Europe/Berlin')
    end

    it 'generates secrets' do
      env = Env.load
      secrets = %w[POSTGRES_PASSWORD INFLUX_PASSWORD INFLUX_ADMIN_TOKEN INFLUX_TOKEN_READWRITE
                   INFLUX_TOKEN_WRITE INFLUX_TOKEN_READ SECRET_KEY_BASE ADMIN_PASSWORD]
      expect(secrets.map { |key| env[key] }).to all(be_present)
    end

    it 'generates secrets with correct lengths' do
      env = Env.load
      expect(env['POSTGRES_PASSWORD'].length).to eq(32)
      expect(env['SECRET_KEY_BASE'].length).to eq(128)
      expect(env['INFLUX_ADMIN_TOKEN'].length).to eq(64)
      expect(env['ADMIN_PASSWORD'].length).to eq(32)
    end

    it 'derives ADMIN_PASSWORD deterministically from SECRET_KEY_BASE' do
      env = Env.load
      expected = Digest::SHA256.hexdigest(env['SECRET_KEY_BASE'])[0, 32]
      expect(env['ADMIN_PASSWORD']).to eq(expected)
    end

    # InfluxDB's docker-entrypoint seeds only the admin token; until HELIOS
    # provisions separate authorizations via the API, the four .env tokens
    # must point at the same value or collectors and dashboard would fail
    # authentication.
    it 'links the four influx tokens to a shared value on first generation' do
      env = Env.load
      shared = env['INFLUX_ADMIN_TOKEN']
      %w[INFLUX_TOKEN_READWRITE INFLUX_TOKEN_WRITE INFLUX_TOKEN_READ].each do |key|
        expect(env[key]).to eq(shared)
      end
    end

    it 'sets InfluxDB configuration' do
      env = Env.load
      expect(env['INFLUX_ORG']).to eq('solectrus')
      expect(env['INFLUX_BUCKET']).to eq('solectrus')
    end

    it 'includes a do-not-edit header comment' do
      content = File.read(env_path)
      expect(content).to include('DO NOT EDIT THIS FILE')
      expect(content).to include('generated by HELIOS')
    end

    it 'includes inline comments for each variable' do
      content = File.read(env_path)
      expect(content).to include('# Timezone for all services')
      expect(content).to include('# Admin password')
      expect(content).to include('# Database password')
    end
  end

  # The boot-time stack refresh (config/initializers/20_stack_refresh.rb)
  # rewrites compose.yaml/.env on every HELIOS startup. If the rewrite is not
  # byte-stable for an unchanged config, every boot bumps the compose
  # config-hash for affected services, and the next routine `docker compose
  # up -d` cascades container recreations the user did not ask for.
  shared_examples 'byte-stable rendering' do
    it 'produces byte-identical compose.yaml on a second render' do
      described_class.new(Configuration.current).write!
      first = File.read(compose_path)
      described_class.new(Configuration.current).write!
      expect(File.read(compose_path)).to eq(first)
    end

    it 'produces byte-identical .env on a second render' do
      described_class.new(Configuration.current).write!
      first = File.read(env_path)
      described_class.new(Configuration.current).write!
      expect(File.read(env_path)).to eq(first)
    end
  end

  describe 'idempotent output' do
    context 'with a minimal default configuration' do
      before { configuration } # materialize the base configuration

      it_behaves_like 'byte-stable rendering'
    end

    context 'with a full configuration covering most sections' do
      before do
        configuration.update('reverse_proxy', { 'app_domain' => 'solar.example.com' })
        configuration.update('backup', {
                               'aws_access_key_id' => 'AKIAEXAMPLE',
                               'aws_secret_access_key' => 'secret123',
                               'aws_region' => 'eu-central-1',
                               'aws_bucket' => 'my-bucket',
                             })
        configuration.update('senec', { 'adapter' => 'local', 'host' => '192.168.1.100',
                                        'schema' => 'https', 'language' => 'de', 'interval' => '5' })
        configuration.update('forecast', {
                               'forecast' => 'forecast.solar', 'forecast_latitude' => '51.3',
                               'forecast_longitude' => '9.5', 'forecast_declination1' => '30',
                               'forecast_azimuth1' => '180', 'forecast_kwp1' => '10'
                             })
        configuration.update('mqtt', { 'mqtt_host' => '192.168.1.50', 'mqtt_port' => '1883' })
        configuration.update('shelly', { 'connection' => 'local', 'interval' => '5' })
        configuration.update_sensor('inverter_power', { 'source' => 'senec' })
        configuration.update_sensor('grid_import_power', { 'source' => 'senec' })
        configuration.update_sensor('house_power', { 'source' => 'senec' })
        configuration.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })
        configuration.update_sensor('heatpump_power',
                                    { 'source' => 'shelly', 'shelly_host' => 'shelly.local',
                                      'measurement' => 'heatpump' })
        configuration.update_sensor('case_temp',
                                    { 'source' => 'mqtt', 'mqtt_topic' => 'case/temp',
                                      'measurement' => 'case', 'field' => 'temp',
                                      'mqtt_payload_type' => 'float' })
      end

      it_behaves_like 'byte-stable rendering'
    end

    context 'with collectors_only deployment' do
      before do
        configuration.update('deployment', { 'mode' => 'collectors_only' })
        configuration.update('influxdb', {
                               'host' => 'ingest.example.com', 'port' => '443',
                               'schema' => 'https', 'org' => 'solectrus',
                               'bucket' => 'solectrus', 'token' => 't'
                             })
        configuration.update('senec', { 'adapter' => 'local', 'host' => '192.168.1.100' })
        configuration.update_sensor('inverter_power', { 'source' => 'senec' })
      end

      it_behaves_like 'byte-stable rendering'
    end
  end

  describe 'overwrite behavior' do
    context 'when existing files were not generated by HELIOS' do
      before do
        File.write(compose_path, "name: solectrus\n")
        File.write(env_path, "TZ=Europe/Berlin\n")
        described_class.new(configuration).write!
      end

      it 'overwrites the files' do
        expect(File.read(compose_path)).to include('generated by HELIOS')
        expect(File.read(env_path)).to include('generated by HELIOS')
      end
    end

    context 'when no files exist yet' do
      before { described_class.new(configuration).write! }

      it 'does not create a backup for compose.yaml' do
        expect(File.exist?(File.join(tmp_dir, 'compose.yaml.bak'))).to be false
      end

      it 'does not create a backup for .env' do
        expect(File.exist?(File.join(tmp_dir, '.env.bak'))).to be false
      end
    end
  end

  describe 'with reverse_proxy configured' do
    before do
      configuration.update('reverse_proxy', {
                             'app_domain' => 'solar.example.com',
                           })
      described_class.new(configuration).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'includes traefik service in compose.yaml' do
      compose = Compose.load
      expect(compose.services.names).to include('traefik')
    end

    it 'configures traefik with correct image' do
      compose = Compose.load
      traefik = compose.services.find('traefik')
      expect(traefik.image).to eq(DockerImages.current(:TRAEFIK))
    end

    it 'removes dashboard ports' do
      compose = Compose.load
      dashboard = compose.services.find('dashboard')
      expect(dashboard.ports).to be_blank
    end

    it 'adds traefik labels to dashboard' do
      compose = Compose.load
      dashboard = compose.services.find('dashboard')
      labels = dashboard.config['labels']
      expect(labels).to include('traefik.enable=true')
      expect(labels).to include(
        'traefik.http.routers.dashboard.rule=Host(`solar.example.com`)',
      )
    end

    it 'sets FORCE_SSL=true in .env when Traefik is enabled' do
      env = Env.load
      expect(env['FORCE_SSL']).to eq('true')
    end

    it 'references FORCE_SSL in the dashboard environment' do
      compose = Compose.load
      dashboard = compose.services.find('dashboard')
      expect(dashboard.environment).to include('FORCE_SSL')
    end

    it 'includes APP_DOMAIN in .env' do
      env = Env.load
      expect(env['APP_DOMAIN']).to eq('solar.example.com')
    end

    it 'includes LETSENCRYPT_EMAIL in .env' do
      env = Env.load
      expect(env['LETSENCRYPT_EMAIL']).to eq('webmaster@solar.example.com')
    end

    it 'creates traefik data directory' do
      expect(Dir.exist?(File.join(tmp_dir, 'traefik'))).to be true
    end

    it 'mounts the default relative bind path for /letsencrypt' do
      compose = Compose.load
      traefik = compose.services.find('traefik')
      expect(traefik.config['volumes']).to include('${TRAEFIK_VOLUME_PATH}:/letsencrypt')
      env = Env.load
      expect(env['TRAEFIK_VOLUME_PATH']).to eq('./traefik')
    end
  end

  describe 'with reverse_proxy and custom volume path' do
    before do
      configuration.update('reverse_proxy', {
                             'app_domain' => 'solar.example.com',
                             'volume_path' => '/volume1/docker/solectrus/traefik',
                           })
      described_class.new(configuration).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'mounts the configured host path in compose.yaml' do
      compose = Compose.load
      traefik = compose.services.find('traefik')
      expect(traefik.config['volumes']).to include('${TRAEFIK_VOLUME_PATH}:/letsencrypt')
      env = Env.load
      expect(env['TRAEFIK_VOLUME_PATH']).to eq('/volume1/docker/solectrus/traefik')
    end

    it 'does not create the default traefik data directory' do
      expect(Dir.exist?(File.join(tmp_dir, 'traefik'))).to be false
    end
  end

  describe 'without reverse_proxy configured' do
    before { described_class.new(configuration).write! }

    it 'does not include traefik service' do
      compose = Compose.load
      expect(compose.services.names).not_to include('traefik')
    end

    it 'includes dashboard ports' do
      compose = Compose.load
      dashboard = compose.services.find('dashboard')
      expect(dashboard.ports).to include('3000:3000')
    end

    it 'does not include APP_DOMAIN in .env' do
      content = File.read(env_path)
      expect(content).not_to include('APP_DOMAIN')
    end
  end

  describe 'with a remapped dashboard host port' do
    before do
      configuration.update('dashboard', { 'host_port' => '3010' })
      described_class.new(configuration).write!
    end

    it 'maps the configured host port to the container port' do
      compose = Compose.load
      dashboard = compose.services.find('dashboard')
      expect(dashboard.ports).to include('3010:3000')
      expect(dashboard.ports).not_to include('3000:3000')
    end
  end

  describe 'with InfluxDB UI port exposure' do
    context 'without publish_port set' do
      before { described_class.new(configuration).write! }

      it 'does not publish 8086 to the host' do
        compose = Compose.load
        influxdb = compose.services.find('influxdb')
        expect(influxdb.config[:ports] || influxdb.ports).to be_blank
      end
    end

    context 'when publish_port is enabled' do
      before do
        configuration.update('influxdb', configuration.influxdb.merge('publish_port' => true))
        described_class.new(configuration).write!
      end

      it 'publishes 8086:8086 to the host' do
        compose = Compose.load
        influxdb = compose.services.find('influxdb')
        expect(influxdb.ports).to include('8086:8086')
      end
    end

    context 'with a custom host_port' do
      before do
        configuration.update('influxdb',
                             configuration.influxdb.merge('publish_port' => true, 'host_port' => '18086'))
        described_class.new(configuration).write!
      end

      it 'maps the configured host port to container port 8086' do
        compose = Compose.load
        influxdb = compose.services.find('influxdb')
        expect(influxdb.ports).to include('18086:8086')
        expect(influxdb.ports).not_to include('8086:8086')
      end
    end

    context 'when running in dashboard_only mode' do
      before do
        configuration.update('deployment', { 'mode' => 'dashboard_only' })
        described_class.new(configuration).write!
      end

      # Remote collectors reach the InfluxDB across the LAN — the port HAS to
      # be open regardless of the flag, otherwise the dashboard_only stack
      # can't receive any measurements.
      it 'forces the port open even with publish_port unset' do
        compose = Compose.load
        influxdb = compose.services.find('influxdb')
        expect(influxdb.ports).to include('8086:8086')
      end
    end
  end

  describe 'with reverse_proxy and an exposed InfluxDB' do
    before do
      configuration.update('reverse_proxy', { 'app_domain' => 'solar.example.com' })
      configuration.update('influxdb', configuration.influxdb.merge('publish_port' => true))
      described_class.new(configuration).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'routes InfluxDB through Traefik instead of publishing a host port' do
      compose = Compose.load
      influxdb = compose.services.find('influxdb')
      expect(influxdb.ports).to be_blank
      expect(influxdb.config['labels']).to include(
        'traefik.enable=true',
        'traefik.http.routers.influxdb.rule=Host(`solar.example.com`)',
        'traefik.http.routers.influxdb.entrypoints=influxdb',
        'traefik.http.routers.influxdb.tls.certresolver=letsencrypt',
        'traefik.http.services.influxdb.loadbalancer.server.port=8086',
      )
    end

    it 'adds the influxdb entrypoint and published port to Traefik' do
      compose = Compose.load
      traefik = compose.services.find('traefik')
      expect(traefik.config['command']).to include('--entrypoints.influxdb.address=:8086')
      expect(traefik.ports).to include('8086:8086')
    end

    context 'with a custom InfluxDB host port' do
      before do
        configuration.update('influxdb',
                             configuration.influxdb.merge('publish_port' => true, 'host_port' => '18086'))
        described_class.new(configuration).write!
      end

      it 'uses the custom port for the Traefik entrypoint and mapping' do
        compose = Compose.load
        traefik = compose.services.find('traefik')
        expect(traefik.config['command']).to include('--entrypoints.influxdb.address=:18086')
        expect(traefik.ports).to include('18086:18086')
      end
    end

    context 'when running in dashboard_only mode' do
      before do
        configuration.update('deployment', { 'mode' => 'dashboard_only' })
        described_class.new(configuration).write!
      end

      it 'still routes InfluxDB through Traefik' do
        compose = Compose.load
        influxdb = compose.services.find('influxdb')
        traefik = compose.services.find('traefik')
        expect(influxdb.ports).to be_blank
        expect(traefik.ports).to include('8086:8086')
      end
    end

    # Imported custom Traefik (captured `command`) that already declares an
    # `influxdb` entrypoint — HELIOS leaves routing to it (service_overrides
    # carries the labels) and publishes no host port, so 8086 isn't bound twice.
    context 'with an imported Traefik that routes influxdb itself' do
      before do
        configuration.update('reverse_proxy', {
                               'app_domain' => 'solar.example.com',
                               'command' => [
                                 '--providers.docker=true',
                                 '--entrypoints.web.address=:80',
                                 '--entrypoints.websecure.address=:443',
                                 '--entrypoints.influxdb.address=:8086',
                               ],
                               'ports' => %w[80:80 443:443 8086:8086],
                             })
        described_class.new(configuration).write!
      end

      it 'publishes no direct host port for InfluxDB' do
        compose = Compose.load
        influxdb = compose.services.find('influxdb')
        expect(influxdb.ports).to be_blank
      end
    end

    # Imported custom Traefik without an `influxdb` entrypoint — HELIOS can't
    # route through it, so an exposed InfluxDB falls back to a direct host
    # port (no clash, since Traefik doesn't publish 8086).
    context 'with an imported Traefik that does not route influxdb' do
      before do
        configuration.update('reverse_proxy', {
                               'app_domain' => 'solar.example.com',
                               'command' => [
                                 '--providers.docker=true',
                                 '--entrypoints.web.address=:80',
                                 '--entrypoints.websecure.address=:443',
                               ],
                               'ports' => %w[80:80 443:443],
                             })
        described_class.new(configuration).write!
      end

      it 'falls back to a direct host port for InfluxDB' do
        compose = Compose.load
        influxdb = compose.services.find('influxdb')
        expect(influxdb.ports).to include('8086:8086')
      end
    end
  end

  describe 'with reverse_proxy but InfluxDB not exposed' do
    before do
      configuration.update('reverse_proxy', { 'app_domain' => 'solar.example.com' })
      described_class.new(configuration).write!
    end

    it 'leaves the influxdb entrypoint off Traefik' do
      compose = Compose.load
      traefik = compose.services.find('traefik')
      expect(traefik.config['command']).not_to include('--entrypoints.influxdb.address=:8086')
      expect(traefik.ports).to contain_exactly('80:80', '443:443')
    end

    it 'adds no Traefik labels to influxdb' do
      compose = Compose.load
      influxdb = compose.services.find('influxdb')
      expect(Array(influxdb.config['labels']).grep(/traefik/)).to be_empty
    end
  end

  describe 'with SENEC local configured' do
    before do
      configuration.update('senec', {
                             'adapter' => 'local',
                             'host' => '192.168.1.100',
                             'schema' => 'https',
                             'language' => 'de',
                             'interval' => '5',
                           })
      configuration.update_sensor('inverter_power', { 'source' => 'senec' })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'includes senec-collector service' do
      compose = Compose.load
      expect(compose.services.names).to include('senec-collector')
    end

    it 'configures senec-collector with environment' do
      compose = Compose.load
      senec = compose.services.find('senec-collector')

      expect(senec.environment).to include('SENEC_ADAPTER', 'SENEC_HOST', 'SENEC_SCHEMA', 'SENEC_LANGUAGE')
    end

    it 'includes SENEC variables in .env' do
      env = Env.load
      expect(env['SENEC_ADAPTER']).to eq('local')
      expect(env['SENEC_HOST']).to eq('192.168.1.100')
    end

    it 'includes sensor mappings in .env' do
      content = File.read(env_path)
      expect(content).to include('INFLUX_SENSOR_INVERTER_POWER')
    end
  end

  describe 'with SENEC cloud configured' do
    before do
      configuration.update('senec', {
                             'adapter' => 'cloud',
                             'username' => 'user@example.com',
                             'password' => 'secret',
                             'totp_uri' => 'otpauth://totp/SENEC',
                             'system_id' => '12345',
                             'ignore' => 'wallbox',
                           })
      configuration.update_sensor('inverter_power', { 'source' => 'senec' })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'includes cloud credentials in .env' do
      env = Env.load
      expect(env['SENEC_ADAPTER']).to eq('cloud')
      expect(env['SENEC_USERNAME']).to eq('user@example.com')
      expect(env['SENEC_PASSWORD']).to eq('secret')
    end

    it 'includes optional cloud variables in .env' do
      env = Env.load
      expect(env['SENEC_TOTP_URI']).to eq('otpauth://totp/SENEC')
      expect(env['SENEC_SYSTEM_ID']).to eq('12345')
      expect(env['SENEC_IGNORE']).to eq('wallbox')
    end

    it 'includes cloud vars in senec-collector environment' do
      compose = Compose.load
      senec = compose.services.find('senec-collector')

      expect(senec.environment).to include('SENEC_USERNAME', 'SENEC_PASSWORD')
      expect(senec.environment).to include('SENEC_TOTP_URI', 'SENEC_SYSTEM_ID', 'SENEC_IGNORE')
    end

    it 'omits SENEC_REQUEST_MODE when not configured (default minimal)' do
      env = Env.load
      expect(env['SENEC_REQUEST_MODE']).to be_nil

      compose = Compose.load
      senec = compose.services.find('senec-collector')
      expect(senec.environment).not_to include('SENEC_REQUEST_MODE')
    end
  end

  describe 'with SENEC cloud and request_mode=full' do
    before do
      configuration.update('senec', {
                             'adapter' => 'cloud',
                             'username' => 'user@example.com',
                             'password' => 'secret',
                             'request_mode' => 'full',
                           })
      configuration.update_sensor('inverter_power', { 'source' => 'senec' })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'writes SENEC_REQUEST_MODE to .env' do
      env = Env.load
      expect(env['SENEC_REQUEST_MODE']).to eq('full')
    end

    it 'references SENEC_REQUEST_MODE in senec-collector environment' do
      compose = Compose.load
      senec = compose.services.find('senec-collector')
      expect(senec.environment).to include('SENEC_REQUEST_MODE')
    end
  end

  describe 'with forecast configured' do
    before do
      configuration.update('forecast', {
                             'forecast' => 'forecast.solar',
                             'forecast_latitude' => '51.3',
                             'forecast_longitude' => '9.5',
                             'forecast_declination1' => '30',
                             'forecast_azimuth1' => '180',
                             'forecast_kwp1' => '10',
                             'forecast_interval' => '900',
                             'forecast_solar_apikey' => 'abc123',
                           })
      configuration.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'includes forecast-collector service' do
      compose = Compose.load
      expect(compose.services.names).to include('forecast-collector')
    end

    it 'includes forecast variables in .env' do
      env = Env.load
      expect(env['FORECAST_PROVIDER']).to eq('forecast.solar')
      expect(env['FORECAST_LATITUDE']).to eq('51.3')
      expect(env['FORECAST_DECLINATION']).to eq('30')
      expect(env['FORECAST_KWP']).to eq('10')
      expect(env['FORECAST_SOLAR_APIKEY']).to eq('abc123')
    end

    it 'defaults INFLUX_MEASUREMENT_FORECAST to lowercase' do
      expect(Env.load['INFLUX_MEASUREMENT_FORECAST']).to eq('forecast')
    end

    it 'configures forecast-collector with environment' do
      compose = Compose.load
      forecast = compose.services.find('forecast-collector')

      expect(forecast.environment).to include(
        'FORECAST_PROVIDER', 'FORECAST_LATITUDE', 'FORECAST_LONGITUDE',
        'FORECAST_INTERVAL',
        'FORECAST_DECLINATION', 'FORECAST_AZIMUTH', 'FORECAST_KWP'
      )
    end
  end

  describe 'with forecast configured for pvnode' do
    before do
      configuration.update('forecast', {
                             'forecast' => 'pvnode',
                             'forecast_latitude' => '51.3',
                             'forecast_longitude' => '9.5',
                             'forecast_declination1' => '30',
                             'forecast_pvnode_azimuth1' => '180',
                             'forecast_kwp1' => '10',
                             'forecast_pvnode_apikey' => 'pvnode-key',
                           })
      configuration.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })
      described_class.new(Configuration.current).write!
    end

    it 'omits FORECAST_INTERVAL from .env (pvnode ignores it at runtime)' do
      expect(Env.load['FORECAST_INTERVAL']).to be_nil
    end

    it 'omits FORECAST_INTERVAL from the forecast-collector environment passthrough' do
      forecast = Compose.load.services.find('forecast-collector')
      expect(forecast.environment).not_to include('FORECAST_INTERVAL')
    end
  end

  describe 'with forecast configured for solcast without an explicit interval' do
    before do
      configuration.update('forecast', {
                             'forecast' => 'solcast',
                             'forecast_latitude' => '51.3',
                             'forecast_longitude' => '9.5',
                             'forecast_declination1' => '30',
                             'forecast_azimuth1' => '180',
                             'forecast_kwp1' => '10',
                             'forecast_solcast_api_key' => 'solcast-key',
                             'forecast_solcast_id1' => 'site-1',
                           })
      configuration.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })
      described_class.new(Configuration.current).write!
    end

    it 'falls back to the 900s baseline' do
      expect(Env.load['FORECAST_INTERVAL']).to eq('900')
    end

    it 'keeps FORECAST_INTERVAL in the forecast-collector environment passthrough' do
      forecast = Compose.load.services.find('forecast-collector')
      expect(forecast.environment).to include('FORECAST_INTERVAL')
    end
  end

  describe 'with custom forecast measurement' do
    before do
      configuration.update('forecast', {
                             'forecast' => 'forecast.solar',
                             'forecast_latitude' => '51.3',
                             'forecast_longitude' => '9.5',
                             'forecast_declination1' => '30',
                             'forecast_azimuth1' => '180',
                             'forecast_kwp1' => '10',
                             'measurement' => 'MyForecast',
                           })
      configuration.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })
      described_class.new(Configuration.current).write!
    end

    it 'writes configured measurement to .env' do
      expect(Env.load['INFLUX_MEASUREMENT_FORECAST']).to eq('MyForecast')
    end
  end

  describe 'with multi-roof forecast configured' do
    before do
      configuration.update('forecast', {
                             'forecast' => 'forecast.solar',
                             'forecast_latitude' => '51.3',
                             'forecast_longitude' => '9.5',
                             'forecast_roofs' => '2',
                             'forecast_declination1' => '30',
                             'forecast_azimuth1' => '180',
                             'forecast_kwp1' => '5',
                             'forecast_declination2' => '25',
                             'forecast_azimuth2' => '-90',
                             'forecast_kwp2' => '3',
                           })
      configuration.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'includes multi-roof configuration in .env' do
      env = Env.load
      expect(env['FORECAST_CONFIGURATIONS']).to eq('2')
      expect(env['FORECAST_0_DECLINATION']).to eq('30')
      expect(env['FORECAST_1_DECLINATION']).to eq('25')
    end

    it 'includes FORECAST_CONFIGURATIONS in compose environment' do
      compose = Compose.load
      forecast = compose.services.find('forecast-collector')

      expect(forecast.environment).to include('FORECAST_CONFIGURATIONS')
    end
  end

  describe 'with solcast forecast configured' do
    before do
      configuration.update('forecast', {
                             'forecast' => 'solcast',
                             'forecast_latitude' => '51.3',
                             'forecast_longitude' => '9.5',
                             'forecast_declination1' => '30',
                             'forecast_azimuth1' => '180',
                             'forecast_kwp1' => '10',
                             'forecast_solcast_api_key' => 'solcast-key',
                             'forecast_solcast_id1' => 'site-123',
                           })
      configuration.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'includes solcast variables in .env' do
      env = Env.load
      expect(env['SOLCAST_APIKEY']).to eq('solcast-key')
      expect(env['SOLCAST_SITE']).to eq('site-123')
    end
  end

  describe 'with pvnode forecast configured' do
    before do
      configuration.update('forecast', {
                             'forecast' => 'pvnode',
                             'forecast_latitude' => '51.3',
                             'forecast_longitude' => '9.5',
                             'forecast_declination1' => '30',
                             'forecast_pvnode_azimuth1' => '180',
                             'forecast_kwp1' => '10',
                             'forecast_pvnode_apikey' => 'pvnode-key',
                             'forecast_pvnode_paid' => 'true',
                             'forecast_pvnode_extra_params' => 'extra=1',
                           })
      configuration.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'includes pvnode variables in .env' do
      env = Env.load
      expect(env['PVNODE_APIKEY']).to eq('pvnode-key')
      expect(env['PVNODE_PAID']).to eq('true')
      expect(env['PVNODE_EXTRA_PARAMS']).to eq('extra=1')
    end

    it 'writes the pvnode azimuth (north-based) to FORECAST_AZIMUTH' do
      expect(Env.load['FORECAST_AZIMUTH']).to eq('180')
    end

    it 'includes pvnode vars in compose environment' do
      compose = Compose.load
      forecast = compose.services.find('forecast-collector')

      expect(forecast.environment).to include('PVNODE_APIKEY', 'PVNODE_PAID', 'PVNODE_EXTRA_PARAMS')
    end
  end

  describe 'with pvnode nowcast plan configured' do
    before do
      configuration.update('forecast', {
                             'forecast' => 'pvnode',
                             'forecast_latitude' => '51.3',
                             'forecast_longitude' => '9.5',
                             'forecast_declination1' => '30',
                             'forecast_pvnode_azimuth1' => '180',
                             'forecast_kwp1' => '10',
                             'forecast_pvnode_apikey' => 'pvnode-key',
                             'forecast_pvnode_paid' => 'nowcast',
                           })
      configuration.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'writes PVNODE_PAID=nowcast to .env' do
      expect(Env.load['PVNODE_PAID']).to eq('nowcast')
    end

    it 'lists PVNODE_PAID in the compose environment' do
      compose = Compose.load
      forecast = compose.services.find('forecast-collector')
      expect(forecast.environment).to include('PVNODE_PAID')
    end
  end

  describe 'with pvnode free plan configured' do
    before do
      configuration.update('forecast', {
                             'forecast' => 'pvnode',
                             'forecast_latitude' => '51.3',
                             'forecast_longitude' => '9.5',
                             'forecast_declination1' => '30',
                             'forecast_pvnode_azimuth1' => '180',
                             'forecast_kwp1' => '10',
                             'forecast_pvnode_apikey' => 'pvnode-key',
                             'forecast_pvnode_paid' => 'false',
                           })
      configuration.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'omits PVNODE_PAID from .env' do
      content = File.read(env_path)
      expect(content).not_to include('PVNODE_PAID')
    end

    it 'does not list PVNODE_PAID in the compose environment' do
      compose = Compose.load
      forecast = compose.services.find('forecast-collector')
      expect(forecast.environment).not_to include('PVNODE_PAID')
    end
  end

  describe 'with pvnode multi-roof forecast configured' do
    before do
      configuration.update('forecast', {
                             'forecast' => 'pvnode',
                             'forecast_latitude' => '51.3',
                             'forecast_longitude' => '9.5',
                             'forecast_roofs' => '2',
                             'forecast_declination1' => '30',
                             'forecast_pvnode_azimuth1' => '180',
                             'forecast_kwp1' => '10',
                             'forecast_declination2' => '20',
                             'forecast_pvnode_azimuth2' => '90',
                             'forecast_kwp2' => '5',
                             'forecast_pvnode_apikey' => 'pvnode-key',
                             'forecast_pvnode_extra_params' => 'global=1',
                             'forecast_pvnode_extra_params1' => 'roof1=a',
                             'forecast_pvnode_extra_params2' => 'roof2=b',
                           })
      configuration.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'includes per-roof pvnode extra params in .env' do
      env = Env.load
      expect(env['PVNODE_EXTRA_PARAMS']).to eq('global=1')
      expect(env['PVNODE_0_EXTRA_PARAMS']).to eq('roof1=a')
      expect(env['PVNODE_1_EXTRA_PARAMS']).to eq('roof2=b')
    end

    it 'includes per-roof pvnode vars in compose environment' do
      compose = Compose.load
      forecast = compose.services.find('forecast-collector')

      expect(forecast.environment).to include(
        'PVNODE_EXTRA_PARAMS',
        'PVNODE_0_EXTRA_PARAMS',
        'PVNODE_1_EXTRA_PARAMS',
      )
    end
  end

  describe 'with forecast optional fields configured' do
    before do
      configuration.update('forecast', {
                             'forecast' => 'forecast.solar',
                             'forecast_latitude' => '51.3',
                             'forecast_longitude' => '9.5',
                             'forecast_declination1' => '30',
                             'forecast_azimuth1' => '180',
                             'forecast_kwp1' => '10',
                             'forecast_damping_morning' => '0.5',
                             'forecast_damping_evening' => '0.8',
                             'forecast_horizon' => '24',
                             'forecast_inverter' => '0.95',
                           })
      configuration.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'includes optional forecast variables in .env' do
      env = Env.load
      expect(env['FORECAST_DAMPING_MORNING']).to eq('0.5')
      expect(env['FORECAST_DAMPING_EVENING']).to eq('0.8')
      expect(env['FORECAST_HORIZON']).to eq('24')
      expect(env['FORECAST_INVERTER']).to eq('0.95')
    end

    it 'includes optional vars in compose environment' do
      compose = Compose.load
      forecast = compose.services.find('forecast-collector')

      expect(forecast.environment).to include(
        'FORECAST_DAMPING_MORNING', 'FORECAST_DAMPING_EVENING',
        'FORECAST_HORIZON', 'FORECAST_INVERTER'
      )
    end
  end

  describe 'with shelly configured' do
    before do
      configuration.update('shelly', { 'interval' => '5' })
      configuration.update_sensor('heatpump_power', {
                                    'source' => 'shelly',
                                    'shelly_host' => 'shelly-hp.local',
                                    'measurement' => 'heatpump',
                                    'shelly_interval' => '5',
                                  })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'includes shelly-collector service' do
      compose = Compose.load
      expect(compose.services.names).to include('shelly-collector')
    end

    it 'configures shelly-collector with host environment' do
      compose = Compose.load
      shelly = compose.services.find('shelly-collector')

      expect(shelly.environment).to include('SHELLY_HOST', 'INFLUX_MEASUREMENT')
    end

    it 'includes shelly variables in .env' do
      env = Env.load
      expect(env['SHELLY_HOST']).to eq('shelly-hp.local')
      expect(env['INFLUX_MEASUREMENT']).to eq('heatpump')
    end
  end

  describe 'in collectors_only mode with cloud-shellies' do
    before do
      configuration.update('system', { 'installation_date' => '2024-01-15',
                                       'timezone' => 'Europe/Berlin' })
      configuration.update('deployment', { 'mode' => 'collectors_only' })
      configuration.update('influxdb', { 'host' => 'ingest.example.com', 'port' => '443',
                                         'schema' => 'https', 'org' => 'solectrus',
                                         'bucket' => 'solectrus', 'token' => 't' })
      configuration.update('shelly', {
                             'connection' => 'cloud',
                             'interval' => '5',
                             'cloud_server' => 'https://shelly-42-eu.shelly.cloud',
                             'auth_key' => 'cloud-key',
                             'devices' => [
                               { 'name' => 'heatpump', 'device_id' => 'aabbccdd0001',
                                 'measurement' => 'Heatpump' },
                               { 'name' => 'fridge', 'device_id' => 'aabbccdd0002',
                                 'measurement' => 'Fridge' },
                             ],
                           })
      described_class.new(Configuration.current).write!
    end

    it 'writes SHELLY_DEVICE_ID instead of SHELLY_HOST' do
      env = Env.load
      expect(env['SHELLY_DEVICE_ID']).to eq('aabbccdd0001,aabbccdd0002')
      expect(env['INFLUX_MEASUREMENT']).to eq('Heatpump,Fridge')
      expect(env['SHELLY_HOST']).to be_nil
    end

    it 'writes the cloud credentials' do
      env = Env.load
      expect(env['SHELLY_CLOUD_SERVER']).to eq('https://shelly-42-eu.shelly.cloud')
      expect(env['SHELLY_AUTH_KEY']).to eq('cloud-key')
    end

    it 'lists SHELLY_DEVICE_ID and the cloud vars in the compose environment' do
      compose = Compose.load
      shelly = compose.services.find('shelly-collector')
      expect(shelly.environment).to include('SHELLY_DEVICE_ID',
                                            'SHELLY_CLOUD_SERVER',
                                            'SHELLY_AUTH_KEY')
      expect(shelly.environment).not_to include('SHELLY_HOST')
    end
  end

  describe 'in collectors_only mode with per-device shelly options' do
    before do
      configuration.update('deployment', { 'mode' => 'collectors_only' })
      configuration.update('influxdb', { 'host' => 'ingest.example.com', 'port' => '443',
                                         'schema' => 'https', 'org' => 'solectrus',
                                         'bucket' => 'solectrus', 'token' => 't' })
      configuration.update('shelly', {
                             'connection' => 'local',
                             'interval' => '5',
                             'devices' => [
                               { 'name' => 'a', 'host' => 'a.local', 'measurement' => 'A',
                                 'password' => 'pa', 'invert_power' => true },
                               { 'name' => 'b', 'host' => 'b.local', 'measurement' => 'B',
                                 'password' => 'pb' },
                               { 'name' => 'c', 'host' => 'c.local', 'measurement' => 'C',
                                 'invert_power' => true },
                             ],
                           })
      described_class.new(Configuration.current).write!
    end

    it 'emits SHELLY_PASSWORD as a per-device CSV when devices carry their own' do
      env = Env.load
      expect(env['SHELLY_PASSWORD']).to eq('pa,pb,')
    end

    it 'emits SHELLY_INVERT_POWER aligned with the device order' do
      env = Env.load
      expect(env['SHELLY_INVERT_POWER']).to eq('true,,true')
    end
  end

  describe 'in collectors_only mode without per-device passwords' do
    before do
      configuration.update('deployment', { 'mode' => 'collectors_only' })
      configuration.update('influxdb', { 'host' => 'ingest.example.com', 'port' => '443',
                                         'schema' => 'https', 'org' => 'solectrus',
                                         'bucket' => 'solectrus', 'token' => 't' })
      configuration.update('shelly', {
                             'connection' => 'local',
                             'interval' => '5',
                             'password' => 'global',
                             'devices' => [
                               { 'name' => 'a', 'host' => 'a.local', 'measurement' => 'A' },
                               { 'name' => 'b', 'host' => 'b.local', 'measurement' => 'B' },
                             ],
                           })
      described_class.new(Configuration.current).write!
    end

    it 'falls back to the global password as a single value' do
      env = Env.load
      expect(env['SHELLY_PASSWORD']).to eq('global')
    end

    it 'omits SHELLY_INVERT_POWER when no device sets it' do
      env = Env.load
      expect(env['SHELLY_INVERT_POWER']).to be_nil
    end
  end

  describe 'in dashboard_only mode' do
    before do
      configuration.update('system', { 'installation_date' => '2024-01-15',
                                       'timezone' => 'Europe/Berlin' })
      configuration.update('deployment', { 'mode' => 'dashboard_only' })
      configuration.update('shelly', { 'connection' => 'local', 'interval' => '5' })
      configuration.update_sensor('custom_power_01',
                                  { 'source' => 'shelly', 'shelly_host' => 'shelly.local' })
      configuration.update('forecast', {
                             'forecast' => 'forecast.solar',
                             'forecast_latitude' => '51.3',
                             'forecast_longitude' => '9.5',
                             'forecast_declination1' => '30',
                             'forecast_azimuth1' => '180',
                             'forecast_kwp1' => '10',
                           })
      configuration.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'omits device collectors even when sensors reference them' do
      compose = Compose.load
      expect(compose.services.names).not_to include('shelly-collector', 'senec-collector',
                                                    'mqtt-collector')
    end

    it 'still ships the forecast-collector' do
      compose = Compose.load
      expect(compose.services.names).to include('forecast-collector')
    end

    it 'omits the Shelly collector section from .env' do
      expect(Env.load['SHELLY_HOST']).to be_nil
      expect(Env.load['SHELLY_INTERVAL']).to be_nil
    end
  end

  describe 'with MQTT configured' do
    before do
      configuration.update('mqtt', {
                             'mqtt_host' => '192.168.1.50',
                             'mqtt_port' => '1883',
                             'mqtt_username' => 'mqttuser',
                             'mqtt_password' => 'mqttpass',
                           })
      configuration.update_sensor('inverter_power', {
                                    'source' => 'mqtt',
                                    'mqtt_topic' => 'solar/inverter',
                                    'measurement' => 'PV',
                                    'field' => 'power',
                                    'mqtt_payload_type' => 'float',
                                    'mqtt_json_key' => 'value',
                                  })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'includes mqtt-collector service' do
      compose = Compose.load
      expect(compose.services.names).to include('mqtt-collector')
    end

    it 'includes MQTT variables in .env' do
      env = Env.load
      expect(env['MQTT_HOST']).to eq('192.168.1.50')
      expect(env['MQTT_PORT']).to eq('1883')
      expect(env['MQTT_USERNAME']).to eq('mqttuser')
    end

    it 'includes mapping variables in compose environment' do
      compose = Compose.load
      mqtt = compose.services.find('mqtt-collector')

      expect(mqtt.environment).to include(
        'MAPPING_0_TOPIC',
        'MAPPING_0_MEASUREMENT',
        'MAPPING_0_FIELD',
        'MAPPING_0_TYPE',
        'MAPPING_0_JSON_KEY',
      )
    end

    it 'includes mapping variables in .env' do
      env = Env.load
      expect(env['MAPPING_0_TOPIC']).to eq('solar/inverter')
      expect(env['MAPPING_0_MEASUREMENT']).to eq('PV')
      expect(env['MAPPING_0_FIELD']).to eq('power')
      expect(env['MAPPING_0_TYPE']).to eq('float')
      expect(env['MAPPING_0_JSON_KEY']).to eq('value')
    end
  end

  describe 'with MQTT advanced mapping features' do
    before do
      configuration.update('mqtt', { 'mqtt_host' => '192.168.1.50' })
      configuration.update_sensor('inverter_power', {
                                    'source' => 'mqtt',
                                    'mqtt_topic' => 'nested/json',
                                    'measurement' => 'PV',
                                    'field' => 'power',
                                    'mqtt_payload_type' => 'float',
                                    'mqtt_json_path' => '$.data.power',
                                    'mqtt_min' => 0,
                                    'mqtt_max' => 15_000,
                                    'mqtt_null_to_zero' => true,
                                  })
      configuration.update_sensor('heatpump_power', {
                                    'source' => 'mqtt',
                                    'mqtt_topic' => 'heatpump/power',
                                    'measurement' => 'Heatpump',
                                    'field' => 'power',
                                    'mqtt_payload_type' => 'integer',
                                    'mqtt_formula' => 'round({value} * 1000)',
                                  })
      configuration.update_sensor('heatpump_heating_power', {
                                    'source' => 'mqtt',
                                    'mqtt_topic' => 'heatpump/state',
                                    'measurement' => 'Heatpump',
                                    'field' => 'heating_power',
                                    'mqtt_payload_type' => 'float',
                                    'mqtt_json_formula' => 'round({power} / 1000)',
                                  })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'emits JSON_PATH, MIN, MAX and NULL_TO_ZERO for the first sensor' do
      env = Env.load
      expect(env['MAPPING_0_JSON_PATH']).to eq('$.data.power')
      expect(env['MAPPING_0_MIN']).to eq('0')
      expect(env['MAPPING_0_MAX']).to eq('15000')
      expect(env['MAPPING_0_NULL_TO_ZERO']).to eq('true')
    end

    it 'emits FORMULA (not JSON_FORMULA) for string-based formula' do
      env = Env.load
      expect(env['MAPPING_1_FORMULA']).to eq('round({value} * 1000)')
      expect(env['MAPPING_1_JSON_FORMULA']).to be_nil
    end

    it 'emits JSON_FORMULA for JSON-based formula' do
      env = Env.load
      expect(env['MAPPING_2_JSON_FORMULA']).to eq('round({power} / 1000)')
      expect(env['MAPPING_2_FORMULA']).to be_nil
    end

    it 'skips NULL_TO_ZERO when false' do
      updated = configuration.sensor_config('inverter_power').to_h.merge('mqtt_null_to_zero' => false)
      configuration.update_sensor('inverter_power', updated)
      described_class.new(Configuration.current).write!
      env = Env.load
      expect(env['MAPPING_0_NULL_TO_ZERO']).to be_nil
    end
  end

  describe 'with MQTT mappings but blank broker host' do
    before do
      configuration.update('mqtt', { 'mqtt_host' => '' })
      configuration.add_mqtt_topic({
                                     'topic' => 'foo/bar/baz',
                                     'measurement' => 'test',
                                     'field' => 'test',
                                     'type' => 'integer',
                                   })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'omits the mqtt-collector service from compose.yaml' do
      compose = Compose.load
      expect(compose.services.names).not_to include('mqtt-collector')
    end

    it 'omits the MQTT broker section from .env' do
      env = Env.load
      expect(env['MQTT_HOST']).to be_nil
      expect(env['MQTT_PORT']).to be_nil
      expect(env['MAPPING_0_TOPIC']).to be_nil
    end

    it 'retains the mapping in config.yaml for later UI editing' do
      expect(Configuration.current.mqtt_topics).to eq([
                                                        {
                                                          'topic' => 'foo/bar/baz',
                                                          'measurement' => 'test',
                                                          'field' => 'test',
                                                          'type' => 'integer',
                                                        },
                                                      ])
    end

    it 're-emits the collector once the host is filled in' do
      configuration.update('mqtt', configuration.mqtt.to_h.merge('mqtt_host' => '192.168.1.50'))
      described_class.new(Configuration.current).write!
      compose = Compose.load
      env = Env.load
      expect(compose.services.names).to include('mqtt-collector')
      expect(env['MQTT_HOST']).to eq('192.168.1.50')
      expect(env['MAPPING_0_TOPIC']).to eq('foo/bar/baz')
    end
  end

  describe 'power-splitter service' do
    before do
      configuration.update_sensor('grid_import_power', { 'source' => 'senec' })
      configuration.update_sensor('house_power', { 'source' => 'senec' })
      configuration.update_sensor('wallbox_power', { 'source' => 'senec' })
      configuration.update_sensor('heatpump_power', { 'source' => 'shelly', 'shelly_host' => '1.2.3.4' })
      configuration.update_sensor('custom_power_01', { 'source' => 'shelly', 'shelly_host' => '1.2.3.5' })
      configuration.update('senec', { 'adapter' => 'local', 'host' => '192.168.1.100' })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'is always included in the stack' do
      compose = Compose.load
      expect(compose.services.names).to include('power-splitter')
    end

    it 'receives sensor environment for the sensors it consumes' do
      compose = Compose.load
      splitter = compose.services.find('power-splitter')

      expect(splitter.environment).to include(
        'INFLUX_SENSOR_GRID_IMPORT_POWER',
        'INFLUX_SENSOR_HOUSE_POWER',
        'INFLUX_SENSOR_WALLBOX_POWER',
        'INFLUX_SENSOR_HEATPUMP_POWER',
        'INFLUX_SENSOR_CUSTOM_POWER_01',
      )
    end
  end

  describe 'with Ingest (balcony power plant)' do
    before do
      configuration.update('senec', {
                             'adapter' => 'local',
                             'host' => '192.168.1.100',
                             'schema' => 'https',
                             'language' => 'de',
                             'interval' => '5',
                           })
      configuration.update_sensor('inverter_power', { 'source' => 'senec' })
      configuration.update_sensor('grid_import_power', { 'source' => 'senec' })
      configuration.update_sensor('house_power', { 'source' => 'senec' })
      configuration.update_sensor('inverter_power_2', {
                                    'source' => 'external',
                                    'is_balcony' => true,
                                    'measurement' => 'balcony',
                                    'field' => 'power',
                                  })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'activates Configuration#ingest_required?' do
      expect(Configuration.current.ingest_required?).to be true
    end

    it 'includes ingest service' do
      compose = Compose.load
      expect(compose.services.names).to include('ingest')
    end

    it 'uses the default ingest image' do
      compose = Compose.load
      ingest = compose.services.find('ingest')
      expect(ingest.image).to eq('ghcr.io/solectrus/ingest:latest')
    end

    it 'mounts a bind volume for the SQLite buffer' do
      compose = Compose.load
      ingest = compose.services.find('ingest')
      expect(ingest.config['volumes']).to include('${INGEST_VOLUME_PATH}:/app/data')
      env = Env.load
      expect(env['INGEST_VOLUME_PATH']).to eq('./ingest')
    end

    it 'exposes the web UI on port 4567' do
      compose = Compose.load
      ingest = compose.services.find('ingest')
      expect(ingest.ports).to include('4567:4567')
      expect(ingest.public_port).to eq(4567)
    end

    it 'creates the ingest data directory' do
      expect(Dir.exist?(File.join(tmp_dir, 'ingest'))).to be true
    end

    it 'forwards measurements to the real InfluxDB' do
      compose = Compose.load
      ingest = compose.services.find('ingest')
      expect(ingest.environment).to include('INFLUX_HOST=influxdb')
    end

    it 'redirects the SENEC collector to ingest' do
      compose = Compose.load
      senec = compose.services.find('senec-collector')
      expect(senec.environment).to include('INFLUX_HOST=ingest', 'INFLUX_PORT=4567')
      expect(senec.depends_on.keys).to include('ingest')
      expect(senec.depends_on.keys).not_to include('influxdb')
    end

    it 'keeps dashboard pointing at InfluxDB directly' do
      compose = Compose.load
      dashboard = compose.services.find('dashboard')
      expect(dashboard.environment).to include('INFLUX_HOST=influxdb')
      expect(dashboard.environment).not_to include(a_string_starting_with('INFLUX_PORT='))
    end

    it 'keeps power-splitter pointing at InfluxDB directly' do
      compose = Compose.load
      splitter = compose.services.find('power-splitter')
      expect(splitter.environment).to include('INFLUX_HOST=influxdb')
      expect(splitter.environment).not_to include(a_string_starting_with('INFLUX_PORT='))
    end

    context 'when a forecast collector is also configured' do
      before do
        Configuration.current.update('forecast', {
                                       'forecast' => 'forecast.solar',
                                       'forecast_latitude' => '51.3',
                                       'forecast_longitude' => '9.5',
                                       'forecast_declination1' => '30',
                                       'forecast_azimuth1' => '180',
                                       'forecast_kwp1' => '10',
                                     })
        Configuration.current.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })
        described_class.new(Configuration.current).write!
      end

      it 'does not route forecast data through ingest' do
        compose = Compose.load
        forecast = compose.services.find('forecast-collector')
        expect(forecast.environment).to include('INFLUX_HOST=influxdb')
        expect(forecast.environment).not_to include(a_string_starting_with('INFLUX_PORT='))
        expect(forecast.depends_on.keys).to contain_exactly('influxdb')
      end
    end

    it 'does not emit a separate INFLUX_SENSOR_HOUSE_POWER_CALCULATED (Ingest overwrites house_power directly)' do
      content = File.read(env_path)
      expect(content).not_to include('INFLUX_SENSOR_HOUSE_POWER_CALCULATED')

      compose = Compose.load
      ingest = compose.services.find('ingest')
      expect(ingest.environment).not_to include('INFLUX_SENSOR_HOUSE_POWER_CALCULATED')
    end

    it 'persists ingest defaults (image) into config.yaml' do
      reloaded = Configuration.current
      expect(reloaded.ingest.image).to eq('ghcr.io/solectrus/ingest:latest')
    end

    it 'writes RETENTION_HOURS with the documented default of 12 hours' do
      env = Env.load
      expect(env['RETENTION_HOURS']).to eq('12')
    end

    it 'always lists RETENTION_HOURS in the ingest service environment' do
      compose = Compose.load
      ingest = compose.services.find('ingest')
      expect(ingest.environment).to include('RETENTION_HOURS')
    end

    context 'when unrelated sensors are configured' do
      before do
        Configuration.current.update_sensor('case_temp', { 'source' => 'senec' })
        Configuration.current.update_sensor('custom_power_01', {
                                              'source' => 'external',
                                              'measurement' => 'custom', 'field' => 'power'
                                            })
        described_class.new(Configuration.current).write!
      end

      it 'does not forward unrelated sensor mappings to ingest' do
        compose = Compose.load
        ingest = compose.services.find('ingest')
        expect(ingest.environment).not_to include('INFLUX_SENSOR_CASE_TEMP')
        expect(ingest.environment).not_to include('INFLUX_SENSOR_CUSTOM_POWER_01')
      end

      it 'forwards only sensors relevant to the house_power recalculation' do
        compose = Compose.load
        ingest = compose.services.find('ingest')
        sensor_vars = ingest.environment.grep(/\AINFLUX_SENSOR_/)
        expect(sensor_vars).to contain_exactly(
          'INFLUX_SENSOR_INVERTER_POWER',
          'INFLUX_SENSOR_INVERTER_POWER_2',
          'INFLUX_SENSOR_GRID_IMPORT_POWER',
          'INFLUX_SENSOR_HOUSE_POWER',
        )
      end
    end
  end

  describe 'without Ingest' do
    before do
      configuration.update_sensor('inverter_power', { 'source' => 'senec' })
      described_class.new(Configuration.current).write!
    end

    it 'does not include ingest service' do
      compose = Compose.load
      expect(compose.services.names).not_to include('ingest')
    end

    it 'does not create the ingest data directory' do
      expect(Dir.exist?(File.join(tmp_dir, 'ingest'))).to be false
    end
  end

  describe 'with Ingest and custom volume path' do
    before do
      configuration.update('ingest', { 'volume_path' => '/volume1/docker/solectrus/ingest' })
      configuration.update_sensor('inverter_power_1', { 'source' => 'external', 'is_balcony' => true })
      configuration.update_sensor('house_power', { 'source' => 'senec' })
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'mounts the configured host path in compose.yaml' do
      compose = Compose.load
      ingest = compose.services.find('ingest')
      expect(ingest.config['volumes']).to eq(['${INGEST_VOLUME_PATH}:/app/data'])
      env = Env.load
      expect(env['INGEST_VOLUME_PATH']).to eq('/volume1/docker/solectrus/ingest')
    end

    it 'does not create the default ingest data directory' do
      expect(Dir.exist?(File.join(tmp_dir, 'ingest'))).to be false
    end
  end

  describe 'with Ingest retention_hours tuning' do
    before do
      configuration.update('ingest', { 'retention_hours' => '24' })
      configuration.update_sensor('inverter_power_1', { 'source' => 'external', 'is_balcony' => true })
      configuration.update_sensor('house_power', { 'source' => 'senec' })
      described_class.new(Configuration.current).write!
    end

    it 'writes RETENTION_HOURS to .env' do
      env = Env.load
      expect(env['RETENTION_HOURS']).to eq('24')
    end

    it 'passes RETENTION_HOURS into the ingest service' do
      compose = Compose.load
      ingest = compose.services.find('ingest')
      expect(ingest.environment).to include('RETENTION_HOURS')
    end
  end

  describe 'Ingest stats password' do
    before do
      configuration.update_sensor('inverter_power_2', {
                                    'source' => 'external',
                                    'is_balcony' => true,
                                    'measurement' => 'balcony',
                                    'field' => 'power',
                                  })
      described_class.new(Configuration.current).write!
    end

    it 'reuses the admin password so the stats dashboard is protected' do
      compose = Compose.load
      ingest = compose.services.find('ingest')
      expect(ingest.environment).to include('STATS_PASSWORD=${ADMIN_PASSWORD}')
    end

    it 'does not emit a separate STATS_PASSWORD variable to .env' do
      content = File.read(env_path)
      expect(content).not_to include("\nSTATS_PASSWORD=")
    end
  end

  describe 'with custom volume paths' do
    before do
      configuration.update('postgresql',
                           configuration.postgresql.merge('volume_path' => '/volume1/docker/solectrus/postgresql'))
      configuration.update('influxdb',
                           configuration.influxdb.merge('volume_path' => '/volume1/docker/solectrus/influxdb'))
      configuration.update('redis', configuration.redis.merge('volume_path' => '/volume1/docker/solectrus/redis'))
      described_class.new(Configuration.current).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'mounts the configured host paths in compose.yaml' do # rubocop:disable RSpec/MultipleExpectations
      compose = Compose.load
      expect(compose.services.find('postgresql').config['volumes'])
        .to eq(['${DB_VOLUME_PATH}:/var/lib/postgresql'])
      expect(compose.services.find('influxdb').config['volumes'])
        .to eq([
                 '${INFLUX_VOLUME_PATH}:/var/lib/influxdb2',
                 './influx-backup-staging:/influx-backup-staging',
               ])
      expect(compose.services.find('redis').config['volumes'])
        .to eq(['${REDIS_VOLUME_PATH}:/data'])

      env = Env.load
      expect(env['DB_VOLUME_PATH']).to eq('/volume1/docker/solectrus/postgresql')
      expect(env['INFLUX_VOLUME_PATH']).to eq('/volume1/docker/solectrus/influxdb')
      expect(env['REDIS_VOLUME_PATH']).to eq('/volume1/docker/solectrus/redis')
    end

    it 'does not create default data directories when volume paths are external' do
      expect(Dir.exist?(File.join(tmp_dir, 'postgresql'))).to be false
      expect(Dir.exist?(File.join(tmp_dir, 'influxdb'))).to be false
      expect(Dir.exist?(File.join(tmp_dir, 'redis'))).to be false
    end
  end

  describe 'secret persistence' do
    it 'persists generated secrets to config.yaml' do
      described_class.new(configuration).write!

      reloaded = Configuration.current
      secrets = [
        reloaded.system.admin_password, reloaded.system.secret_key_base,
        reloaded.postgresql.password, reloaded.influxdb.password,
        reloaded.influxdb.token_admin, reloaded.influxdb.token_readwrite,
        reloaded.influxdb.token_write, reloaded.influxdb.token_read
      ]
      expect(secrets).to all(be_present)
    end

    it 'preserves secrets across multiple writes' do
      described_class.new(configuration).write!
      first_password = Configuration.current.postgresql.password

      # Reload configuration from disk for second write
      config2 = Configuration.current
      described_class.new(config2).write!
      second_password = Configuration.current.postgresql.password

      expect(second_password).to eq(first_password)
    end

    it 'uses existing secrets instead of generating new ones' do
      configuration.update(
        'postgresql',
        configuration.postgresql.merge('password' => 'my-existing-secret'),
      )

      described_class.new(Configuration.current).write!

      env = Env.load
      expect(env['POSTGRES_PASSWORD']).to eq('my-existing-secret')
    end
  end
end
