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

    it 'configures dashboard with depends_on' do
      compose = Compose.load
      dashboard = compose.services.find('dashboard')

      expect(dashboard.depends_on.keys).to include(
        'postgresql',
        'redis',
        'influxdb',
      )
    end

    it 'includes a generated-by header comment' do
      content = File.read(compose_path)
      expect(content).to include('Generated by HELIOS')
      expect(content).to include('DO NOT EDIT MANUALLY')
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
      expect(env['POSTGRES_PASSWORD']).to be_present
      expect(env['INFLUX_PASSWORD']).to be_present
      expect(env['INFLUX_TOKEN']).to be_present
      expect(env['SECRET_KEY_BASE']).to be_present
      expect(env['ADMIN_PASSWORD']).to be_present
    end

    it 'generates secrets with correct lengths' do
      env = Env.load
      expect(env['POSTGRES_PASSWORD'].length).to eq(32)
      expect(env['SECRET_KEY_BASE'].length).to eq(128)
      expect(env['INFLUX_TOKEN'].length).to eq(64)
      expect(env['ADMIN_PASSWORD'].length).to eq(32)
    end

    it 'sets InfluxDB configuration' do
      env = Env.load
      expect(env['INFLUX_ORG']).to eq('solectrus')
      expect(env['INFLUX_BUCKET']).to eq('solectrus')
    end

    it 'includes a generated-by header comment' do
      content = File.read(env_path)
      expect(content).to include('Generated by HELIOS')
      expect(content).to include('DO NOT EDIT MANUALLY')
    end

    it 'includes inline comments for each variable' do
      content = File.read(env_path)
      expect(content).to include('# Timezone for all services')
      expect(content).to include('# Admin password')
      expect(content).to include('# Database password')
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
        expect(File.read(compose_path)).to include('Generated by HELIOS')
        expect(File.read(env_path)).to include('Generated by HELIOS')
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

    it 'sets FORCE_SSL on dashboard' do
      compose = Compose.load
      dashboard = compose.services.find('dashboard')
      expect(dashboard.environment).to include('FORCE_SSL=true')
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
      expect(traefik.config['volumes']).to include('./traefik:/letsencrypt')
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
      expect(traefik.config['volumes']).to include('/volume1/docker/solectrus/traefik:/letsencrypt')
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

  describe 'with backup configured' do
    before do
      configuration.update('backup', {
                             'aws_access_key_id' => 'AKIAEXAMPLE',
                             'aws_secret_access_key' => 'secret123',
                             'aws_region' => 'eu-central-1',
                             'aws_bucket' => 'my-bucket',
                           })
      described_class.new(configuration).write!
    end

    it_behaves_like 'valid Docker Compose configuration'

    it 'includes postgresql-backup service' do
      compose = Compose.load
      expect(compose.services.names).to include('postgresql-backup')
    end

    it 'includes influxdb-backup service' do
      compose = Compose.load
      expect(compose.services.names).to include('influxdb-backup')
    end

    it 'uses unless-stopped restart policies for backup services' do
      compose = Compose.load

      expect(compose.services.find('postgresql-backup').restart).to eq('unless-stopped')
      expect(compose.services.find('influxdb-backup').restart).to eq('unless-stopped')
    end

    it 'configures influxdb-backup with required environment' do
      compose = Compose.load
      influxdb_backup = compose.services.find('influxdb-backup')

      expect(influxdb_backup.environment).to include(
        'INFLUXDB_HOST=influxdb',
        'INFLUXDB_ORG=${INFLUX_ORG}',
        'INFLUXDB_TOKEN=${INFLUX_TOKEN}',
        'S3_BUCKET=${AWS_BUCKET}',
        'S3_PREFIX=influxdb_backup',
        'CRON=0 0 * * 0',
      )
      expect(influxdb_backup.environment).not_to include('AWS_REGION')
      expect(influxdb_backup.environment).not_to include('AWS_BUCKET' => '${AWS_BUCKET}')
    end

    it 'includes AWS credentials in .env' do
      env = Env.load
      expect(env['AWS_ACCESS_KEY_ID']).to eq('AKIAEXAMPLE')
      expect(env['AWS_SECRET_ACCESS_KEY']).to eq('secret123')
      expect(env['AWS_REGION']).to eq('eu-central-1')
      expect(env['AWS_BUCKET']).to eq('my-bucket')
    end
  end

  describe 'without backup configured' do
    before { described_class.new(configuration).write! }

    it 'does not include backup services' do
      compose = Compose.load
      expect(compose.services.names).not_to include('postgresql-backup', 'influxdb-backup')
    end

    it 'does not include AWS credentials in .env' do
      content = File.read(env_path)
      expect(content).not_to include('AWS_ACCESS_KEY_ID')
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
        'FORECAST_DECLINATION', 'FORECAST_AZIMUTH', 'FORECAST_KWP'
      )
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
                             'forecast_azimuth1' => '180',
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
                             'forecast_azimuth1' => '180',
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
                             'forecast_azimuth1' => '180',
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
                             'forecast_azimuth1' => '180',
                             'forecast_kwp1' => '10',
                             'forecast_declination2' => '20',
                             'forecast_azimuth2' => '90',
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
      expect(ingest.config['volumes']).to include('./ingest:/app/data')
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
      expect(ingest.config['volumes']).to eq(['/volume1/docker/solectrus/ingest:/app/data'])
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

    it 'mounts the configured host paths in compose.yaml' do
      compose = Compose.load
      expect(compose.services.find('postgresql').config['volumes'])
        .to eq(['/volume1/docker/solectrus/postgresql:/var/lib/postgresql'])
      expect(compose.services.find('influxdb').config['volumes'])
        .to eq(['/volume1/docker/solectrus/influxdb:/var/lib/influxdb2'])
      expect(compose.services.find('redis').config['volumes'])
        .to eq(['/volume1/docker/solectrus/redis:/data'])
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
      expect(reloaded.system.admin_password).to be_present
      expect(reloaded.system.secret_key_base).to be_present
      expect(reloaded.postgresql.password).to be_present
      expect(reloaded.influxdb.password).to be_present
      expect(reloaded.influxdb.token).to be_present
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
