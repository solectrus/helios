RSpec.describe Import::ConfigurationImporter do
  subject(:importer) { described_class.new(stack_reader) }

  let(:stack_reader) { Import::StackReader.new(compose_path:, env_path:) }
  let(:scenario_path) { Rails.root.join('spec/fixtures/scenarios', scenario) }
  let(:compose_path) { scenario_path.join('compose.yaml') }
  let(:env_path) { scenario_path.join('.env') }

  before { with_config_yaml }

  context 'with senec3 scenario' do
    let(:scenario) { 'senec3' }

    it 'returns a hash with setting data' do
      expect(importer.result).to include(:system, :dashboard, :postgresql, :influxdb, :redis,
                                         :watchtower, :sensors, :devices)
    end

    describe 'system data' do
      subject(:system) { importer.result[:system] }

      it { is_expected.to include('timezone' => 'Europe/Berlin') }
      it { is_expected.to include('installation_date' => '2020-01-01') }
      it { is_expected.to include('admin_password' => 'secret') }
      it { is_expected.to include('secret_key_base') }
      it { is_expected.to include('app_host' => 'pi') }
      it { is_expected.not_to include('influx_poll_interval') } # deprecated, not imported
      it { is_expected.to include('co2_emission_factor' => '500') }
    end

    describe 'dashboard data' do
      subject(:dashboard) { importer.result[:dashboard] }

      it { is_expected.to include('image') }
    end

    describe 'postgresql data' do
      subject(:postgresql) { importer.result[:postgresql] }

      it 'includes password' do
        expect(postgresql).to include('password' => 'my-secret-db-password')
      end

      it 'includes image' do
        expect(postgresql).to include('image')
      end
    end

    describe 'influxdb data' do
      subject(:influxdb) { importer.result[:influxdb] }

      it 'includes influxdb settings without prefix' do
        expect(influxdb).to include(
          'password' => 'example-influx-password',
          'org' => 'solectrus',
          'bucket' => 'solectrus',
        )
      end

      it 'imports token via INFLUX_ADMIN_TOKEN aliasing' do
        expect(influxdb).to include('token' => 'my-super-secret-admin-token')
      end

      it 'includes image' do
        expect(influxdb).to include('image')
      end
    end

    describe 'device data' do
      subject(:devices) { importer.result[:devices] }

      it 'detects exactly one SENEC inverter' do
        expect(devices.size).to eq(1)
      end

      it 'maps SENEC_ADAPTER=local to battery_vendor senec3' do
        expect(devices.first[:data]).to include('battery_vendor' => 'senec3')
      end

      it 'includes SENEC connection settings' do
        expect(devices.first[:data]).to include(
          'senec_host' => '192.168.178.42',
          'senec_schema' => 'https',
          'senec_language' => 'de',
          'senec_interval' => '5',
        )
      end

      it 'sets type and name' do
        expect(devices.first).to include(type: 'inverter', name: 'SENEC')
      end
    end

    describe 'sensor data' do
      subject(:sensors) { importer.result[:sensors] }

      it 'includes non-empty sensor mappings with lowercase keys' do
        expect(sensors).to include(
          'inverter_power' => 'SENEC:inverter_power',
          'inverter_power_1' => 'SENEC:mpp1_power',
          'inverter_power_2' => 'SENEC:mpp2_power',
          'inverter_power_3' => 'SENEC:mpp3_power',
          'house_power' => 'SENEC:house_power',
          'grid_import_power' => 'SENEC:grid_power_plus',
          'grid_export_power' => 'SENEC:grid_power_minus',
          'battery_charging_power' => 'SENEC:bat_power_plus',
          'battery_discharging_power' => 'SENEC:bat_power_minus',
          'battery_soc' => 'SENEC:bat_fuel_charge',
          'case_temp' => 'SENEC:case_temp',
          'system_status' => 'SENEC:current_state',
          'system_status_ok' => 'SENEC:current_state_ok',
          'grid_export_limit' => 'SENEC:power_ratio',
        )
      end

      it 'excludes empty sensor mappings' do
        expect(sensors.keys).not_to include(
          'wallbox_power',
          'inverter_power_4',
          'inverter_power_5',
          'heatpump_power',
          'car_battery_soc',
        )
      end
    end

    describe 'unmanaged data' do
      subject(:unmanaged) { importer.result[:unmanaged] }

      it 'classifies well-known infrastructure vars as managed (not unmanaged)' do
        env_vars = unmanaged&.dig('env_vars') || {}
        expect(env_vars.keys).not_to include(
          'INFLUX_HOST', 'INFLUX_SCHEMA', 'INFLUX_PORT', 'INFLUX_VOLUME_PATH',
          'INFLUX_USERNAME', 'DB_VOLUME_PATH', 'REDIS_VOLUME_PATH', 'REDIS_URL',
          'APP_HOST', 'INFLUX_POLL_INTERVAL', 'CO2_EMISSION_FACTOR'
        )
      end
    end

    describe '#import!' do
      subject(:config) { importer.import! }

      it 'returns a Configuration' do
        expect(config).to be_a(Configuration)
      end

      it 'persists system settings' do
        expect(config.system).to include('timezone' => 'Europe/Berlin')
      end

      it 'persists SENEC sensors' do
        expect(config.sensor_enabled?('inverter_power')).to be true
        expect(config.sensor_config('inverter_power').source).to eq('senec')
      end

      it 'persists SENEC shared config' do
        expect(config.senec).to be_present
      end
    end
  end

  context 'with with_unknown scenario' do
    let(:scenario) { 'with_unknown' }

    describe 'unmanaged data' do
      subject(:unmanaged) { importer.result[:unmanaged] }

      it 'detects unmanaged services' do
        expect(unmanaged['services']).to include('dozzle', 'nginx')
      end

      it 'detects unmanaged env vars' do
        expect(unmanaged['env_vars']).to include('MY_CUSTOM_VAR' => 'custom-value')
      end
    end

    describe '#import!' do
      subject(:config) { importer.import! }

      it 'still imports managed data' do
        expect(config.system).to include('timezone' => 'Europe/Berlin')
      end

      it 'persists unmanaged services' do
        expect(config.unmanaged.services).to include('dozzle', 'nginx')
      end

      it 'persists unmanaged env vars' do
        expect(config.unmanaged.env_vars).to include('MY_CUSTOM_VAR' => 'custom-value')
      end
    end
  end

  context 'with with_tibber scenario' do
    let(:scenario) { 'with_tibber' }

    describe 'unmanaged data' do
      subject(:unmanaged) { importer.result[:unmanaged] }

      it 'detects tibber-collector as unmanaged service' do
        expect(unmanaged['services']).to include('tibber-collector')
      end

      it 'preserves the full tibber-collector service block' do
        tibber = unmanaged.dig('services', 'tibber-collector')
        expect(tibber).to include(
          'image' => 'ghcr.io/solectrus/tibber-collector:latest',
          'restart' => 'unless-stopped',
        )
        expect(tibber['environment']).to include('TIBBER_TOKEN', 'TIBBER_INTERVAL')
      end

      it 'detects tibber-specific env vars as unmanaged' do
        expect(unmanaged['env_vars']).to include(
          'TIBBER_TOKEN' => 'tibber-api-token-xyz',
          'TIBBER_INTERVAL' => '3600',
          'INFLUX_MEASUREMENT_TIBBER' => 'Tibber',
        )
      end
    end

    describe '#import!' do
      subject(:config) { importer.import! }

      it 'persists tibber-collector as unmanaged' do
        expect(config.unmanaged.services).to include('tibber-collector')
      end

      it 'persists tibber env vars' do
        expect(config.unmanaged.env_vars).to include(
          'TIBBER_TOKEN' => 'tibber-api-token-xyz',
          'TIBBER_INTERVAL' => '3600',
          'INFLUX_MEASUREMENT_TIBBER' => 'Tibber',
        )
      end
    end
  end

  context 'with with_senec_charger scenario' do
    let(:scenario) { 'with_senec_charger' }

    describe 'unmanaged data' do
      subject(:unmanaged) { importer.result[:unmanaged] }

      it 'detects senec-charger as unmanaged service' do
        expect(unmanaged['services']).to include('senec-charger')
      end

      it 'does not classify senec-collector or forecast-collector as unmanaged' do
        expect(unmanaged['services'].keys).not_to include('senec-collector', 'forecast-collector')
      end

      it 'preserves the full senec-charger service block' do
        charger = unmanaged.dig('services', 'senec-charger')
        expect(charger).to include(
          'image' => 'ghcr.io/solectrus/senec-charger:latest',
          'restart' => 'unless-stopped',
        )
        expect(charger['environment']).to include(
          'CHARGER_INTERVAL', 'CHARGER_PRICE_MAX', 'CHARGER_PRICE_TIME_RANGE',
          'CHARGER_FORECAST_THRESHOLD', 'CHARGER_DRY_RUN',
          'INFLUX_MEASUREMENT_PRICES=Tibber'
        )
      end

      it 'detects charger-specific env vars as unmanaged' do
        expect(unmanaged['env_vars']).to include(
          'CHARGER_INTERVAL' => '3600',
          'CHARGER_PRICE_MAX' => '70',
          'CHARGER_PRICE_TIME_RANGE' => '4',
          'CHARGER_FORECAST_THRESHOLD' => '20',
          'CHARGER_DRY_RUN' => 'false',
        )
      end

      it 'does not classify shared SENEC/forecast env vars as unmanaged' do
        expect(unmanaged['env_vars'].keys).not_to include(
          'SENEC_HOST', 'SENEC_SCHEMA',
          'INFLUX_MEASUREMENT_SENEC', 'INFLUX_MEASUREMENT_FORECAST'
        )
      end
    end

    describe '#import!' do
      subject(:config) { importer.import! }

      it 'persists senec-charger as unmanaged' do
        expect(config.unmanaged.services).to include('senec-charger')
      end

      it 'persists charger env vars' do
        expect(config.unmanaged.env_vars).to include(
          'CHARGER_INTERVAL' => '3600',
          'CHARGER_PRICE_MAX' => '70',
        )
      end

      it 'still imports senec-collector as managed' do
        expect(config.senec).to include('host' => '192.168.178.42')
      end
    end
  end

  context 'with with_traefik_and_backup scenario' do
    let(:scenario) { 'with_traefik_and_backup' }

    describe 'reverse_proxy data' do
      subject(:reverse_proxy) { importer.result[:reverse_proxy] }

      it 'detects traefik as reverse proxy' do
        expect(reverse_proxy).to include(
          'app_domain' => 'solar.example.com',
        )
      end

      it 'imports letsencrypt email' do
        expect(reverse_proxy).to include(
          'letsencrypt_email' => 'webmaster@solar.example.com',
        )
      end
    end

    describe 'backup data' do
      subject(:backup) { importer.result[:backup] }

      it 'detects backup services' do
        expect(backup).to include(
          'aws_access_key_id' => 'AKIAEXAMPLE',
          'aws_secret_access_key' => 'secret123',
          'aws_region' => 'eu-central-1',
          'aws_bucket' => 'my-backup-bucket',
        )
      end
    end

    describe '#import!' do
      subject(:config) { importer.import! }

      it 'persists reverse_proxy settings' do
        expect(config.reverse_proxy).to include(
          'app_domain' => 'solar.example.com',
        )
      end

      it 'persists backup settings' do
        expect(config.backup).to include(
          'aws_bucket' => 'my-backup-bucket',
        )
      end
    end
  end

  context 'with with_mqtt scenario' do
    let(:scenario) { 'with_mqtt' }

    describe 'mqtt broker data' do
      subject(:mqtt) { importer.result[:mqtt] }

      it 'imports MQTT broker settings' do
        expect(mqtt).to include(
          'mqtt_host' => 'mqtt-broker.local',
          'mqtt_port' => '1883',
          'mqtt_username' => 'mqttuser',
          'mqtt_password' => 'mqttpass',
        )
      end
    end

    describe 'device data' do
      subject(:devices) { importer.result[:devices] }

      it 'detects SENEC inverter plus three MQTT devices' do
        expect(devices.size).to eq(4)
      end

      it 'infers wallbox from sensor mapping with per-sensor topics' do
        wb = devices.find { |d| d[:type] == 'wallbox' }
        expect(wb).to be_present
        expect(wb[:name]).to eq('go-eCharger')
        expect(wb[:data]).to include(
          'wallbox_vendor' => 'mqtt',
          'mqtt_topic' => 'go-eCharger/123456/nrg',
          'mqtt_topic_car_connected' => 'go-eCharger/123456/car',
        )
      end

      it 'infers heatpump from ALTHERMA sensor mappings' do
        hp = devices.find { |d| d[:type] == 'heatpump' }
        expect(hp).to be_present
        expect(hp[:name]).to eq('ALTHERMA')
        expect(hp[:data]).to include(
          'heatpump_access' => 'mqtt',
          'mqtt_topic_tank_temp' => 'espaltherma/ATTR',
          'mqtt_topic_outdoor_temp' => 'espaltherma/ATTR',
          'mqtt_topic_heating_power' => 'espaltherma/ATTR',
          'mqtt_topic_heatpump_status' => 'espaltherma/ATTR',
        )
      end

      it 'infers car from sensor mapping' do
        car = devices.find { |d| d[:type] == 'car' }
        expect(car).to be_present
        expect(car[:name]).to eq('MyTesla')
        expect(car[:data]).to include(
          'data_source' => 'mqtt',
          'mqtt_topic' => 'tesla/battery',
        )
      end

      it 'applies house power exclusion to wallbox' do
        wb = devices.find { |d| d[:type] == 'wallbox' }
        expect(wb[:data]['exclude_from_house_power']).to be true
      end
    end

    describe 'unmanaged data' do
      subject(:unmanaged) { importer.result[:unmanaged] }

      it 'does not classify MQTT env vars as unmanaged' do
        env_vars = unmanaged&.dig('env_vars') || {}
        expect(env_vars.keys).not_to include(
          'MQTT_HOST', 'MQTT_PORT', 'MQTT_USERNAME', 'MQTT_PASSWORD',
          'MAPPING_0_TOPIC', 'MAPPING_5_JSON_KEY', 'MAPPING_23_JSON_FORMULA'
        )
      end

      it 'does not classify mqtt-collector as unmanaged service' do
        services = unmanaged&.dig('services') || {}
        expect(services.keys).not_to include('mqtt-collector')
      end
    end

    describe '#import!' do
      subject(:config) { importer.import! }

      it 'persists MQTT broker settings' do
        expect(config.mqtt).to include('mqtt_host' => 'mqtt-broker.local')
      end

      it 'persists MQTT sensors' do
        # The import should create sensor entries for MQTT-sourced data
        mqtt_sensors = config.sensors_with_source('mqtt')
        expect(mqtt_sensors).to be_present
      end
    end
  end

  context 'with with_forecast_and_shelly scenario' do
    let(:scenario) { 'with_forecast_and_shelly' }

    describe 'system data' do
      subject(:system) { importer.result[:system] }

      it 'imports dashboard-specific settings' do
        expect(system).to include(
          'app_host' => 'myhost',
          'co2_emission_factor' => '500',
        )
        expect(system).not_to include('influx_poll_interval')
      end
    end

    describe 'forecast data' do
      subject(:forecast) { importer.result[:forecast] }

      it 'imports forecast provider and location' do
        expect(forecast).to include(
          'forecast' => 'forecast.solar',
          'forecast_latitude' => '51.5',
          'forecast_longitude' => '7.5',
        )
      end

      it 'imports single-roof configuration' do
        expect(forecast).to include(
          'forecast_roofs' => '1',
          'forecast_declination1' => '30',
          'forecast_azimuth1' => '-10',
          'forecast_kwp1' => '8.4',
        )
      end

      it 'imports forecast extras (damping, horizon, inverter)' do
        expect(forecast).to include(
          'forecast_damping_morning' => '0',
          'forecast_damping_evening' => '0',
          'forecast_horizon' => '24',
          'forecast_inverter' => '1',
        )
      end

      it 'imports forecast.solar API key' do
        expect(forecast).to include(
          'forecast_solar_apikey' => 'my-solar-api-key',
        )
      end

      it 'imports forecast interval' do
        expect(forecast).to include('forecast_interval' => '900')
      end

      it 'preserves INFLUX_MEASUREMENT_FORECAST from existing .env' do
        expect(forecast).to include('measurement' => 'Forecast')
      end
    end

    describe 'device data' do
      subject(:devices) { importer.result[:devices] }

      it 'detects SENEC inverter with senec_ignore' do
        senec = devices.find { |d| d[:type] == 'inverter' }
        expect(senec[:data]).to include(
          'battery_vendor' => 'senec3',
          'senec_ignore' => 'wallbox_charge_power,grid_power_minus',
        )
      end

      it 'detects three shelly devices' do
        shellys = devices.reject { |d| d[:type] == 'inverter' }
        expect(shellys.size).to eq(3)
      end

      it 'infers heatpump from sensor mapping' do
        hp = devices.find { |d| d[:type] == 'heatpump' }
        expect(hp).to be_present
        expect(hp[:data]).to include(
          'heatpump_access' => 'shelly',
          'shelly_host' => 'shelly-hp.local',
        )
      end

      it 'infers wallbox from sensor mapping' do
        wb = devices.find { |d| d[:type] == 'wallbox' }
        expect(wb).to be_present
        expect(wb[:data]).to include(
          'wallbox_vendor' => 'shelly',
          'shelly_host' => 'shelly-wb.local',
          'shelly_password' => 'secret',
        )
      end

      it 'defaults unknown shelly to consumer' do
        consumer = devices.find { |d| d[:type] == 'consumer' }
        expect(consumer).to be_present
        expect(consumer[:name]).to eq('Fridge')
        expect(consumer[:data]).to include(
          'data_source' => 'shelly',
          'shelly_host' => 'shelly-fridge.local',
        )
      end
    end

    describe '#import!' do
      subject(:config) { importer.import! }

      it 'persists forecast settings' do
        expect(config.forecast).to include(
          'forecast' => 'forecast.solar',
          'forecast_damping_morning' => '0',
        )
      end

      it 'persists shelly sensors' do
        shelly_sensors = config.sensors_with_source('shelly')
        expect(shelly_sensors).to be_present
      end

      it 'persists SENEC shared config with senec_ignore' do
        expect(config.senec.ignore).to eq('wallbox_charge_power,grid_power_minus')
      end
    end
  end

  context 'with with_external scenario' do
    let(:scenario) { 'with_external' }

    describe 'sensor data' do
      subject(:sensors) { importer.result[:sensors] }

      it 'includes sensor mappings with custom measurements' do
        expect(sensors).to include(
          'inverter_power' => 'inverter:power',
          'house_power' => 'house:power',
          'grid_import_power' => 'grid:import_power',
          'grid_export_power' => 'grid:export_power',
          'battery_charging_power' => 'battery:charging_power',
          'battery_discharging_power' => 'battery:discharging_power',
          'battery_soc' => 'battery:soc',
        )
      end
    end

    describe 'device data' do
      subject(:devices) { importer.result[:devices] }

      it 'detects no devices (no SENEC, no MQTT, no Shelly)' do
        expect(devices).to be_empty
      end
    end

    describe '#import!' do
      subject(:config) { importer.import! }

      it 'persists sensors as external source' do
        external_sensors = config.sensors_with_source('external')
        expect(external_sensors.keys).to include('inverter_power', 'house_power')
      end

      it 'preserves custom measurement:field mappings' do
        expect(config.sensor_config('inverter_power').measurement).to eq('inverter')
        expect(config.sensor_config('inverter_power').field).to eq('power')
      end

      it 'preserves forecast sensor mappings' do
        expect(config.sensor_config('inverter_power_forecast').measurement).to eq('inverter_forecast')
        expect(config.sensor_config('inverter_power_forecast').field).to eq('power')
      end

      it 'produces correct effective sensor mappings' do
        mappings = config.effective_sensor_mappings
        expect(mappings['inverter_power']).to eq('inverter:power')
        expect(mappings['house_power']).to eq('house:power')
        expect(mappings['battery_soc']).to eq('battery:soc')
        expect(mappings['inverter_power_forecast']).to eq('inverter_forecast:power')
      end

      it 'produces a config.yaml matching the expected configuration' do
        importer.import!

        imported_data = YAML.safe_load_file(
          Configuration.path,
          permitted_classes: [Date],
        )
        expected_config = YAML.safe_load_file(
          scenario_path.join('expected_config.yaml'),
          permitted_classes: [Date],
        )

        expect(imported_data).to eq(expected_config)
      end
    end
  end

  context 'with full_stack scenario (round-trip)' do
    let(:scenario) { 'full_stack' }

    it 'produces a config.yaml matching the expected configuration' do
      importer.import!

      imported_data = YAML.safe_load_file(
        Configuration.path,
        permitted_classes: [Date],
      )
      expected_config = YAML.safe_load_file(
        scenario_path.join('expected_config.yaml'),
        permitted_classes: [Date],
      )

      expect(imported_data).to eq(expected_config)
    end
  end

  context 'with an Ingest service in the stack' do
    subject(:importer) { described_class.new(stack_reader) }

    let(:stack_reader) do
      services_hash = {
        'dashboard' => {
          'environment' => {
            'INFLUX_SENSOR_INVERTER_POWER_2' => 'SENEC:mpp2_power',
            'INFLUX_SENSOR_HOUSE_POWER' => 'SENEC:house_power',
            'INFLUX_SENSOR_HOUSE_POWER_CALCULATED' => 'SENEC:house_power_calculated',
          },
        },
        'ingest' => {
          'image' => 'ghcr.io/solectrus/ingest:latest',
          'environment' => { 'RETENTION_HOURS' => '48' },
        },
        'power-splitter' => { 'environment' => {} },
      }

      instance_double(
        Import::StackReader,
        services: services_hash,
        service: nil,
        raw_env: { 'INFLUX_TOKEN' => 'token', 'INFLUX_ORG' => 'solectrus', 'INFLUX_BUCKET' => 'solectrus' },
        raw_compose: { 'services' => services_hash },
      ).tap do |double|
        allow(double).to receive(:service) { |name| double.services[name] }
      end
    end

    describe 'ingest section data' do
      subject(:ingest_data) { importer.result[:ingest] }

      it 'imports retention hours' do
        expect(ingest_data).to include('retention_hours' => '48')
      end

      it 'imports the ingest image' do
        expect(ingest_data).to include('image' => 'ghcr.io/solectrus/ingest:latest')
      end

      it 'does not carry over STATS_PASSWORD (auto-linked to ADMIN_PASSWORD on export)' do
        expect(ingest_data.keys).not_to include('stats_password')
      end
    end

    describe 'sensor data' do
      subject(:sensors) { importer.result[:sensors] }

      it 'drops INFLUX_SENSOR_HOUSE_POWER_CALCULATED because it is not a real sensor' do
        expect(sensors.keys).not_to include('house_power_calculated')
      end

      it 'keeps regular sensor mappings' do
        expect(sensors).to include(
          'inverter_power_2' => 'SENEC:mpp2_power',
          'house_power' => 'SENEC:house_power',
        )
      end
    end

    describe '#import!' do
      subject(:config) { importer.import! }

      it 'flags the first individual inverter sensor as balcony power plant' do
        expect(config.sensor_config('inverter_power_2').is_balcony).to be true
      end

      it 'makes ingest_required? true after import' do
        importer.import!
        expect(Configuration.current.ingest_required?).to be true
      end

      it 'persists the ingest section' do
        expect(config.ingest.retention_hours).to eq('48')
      end
    end
  end

  context 'with an Ingest service but no individual inverter sensors' do
    subject(:importer) { described_class.new(stack_reader) }

    let(:stack_reader) do
      services_hash = {
        'dashboard' => {
          'environment' => {
            'INFLUX_SENSOR_INVERTER_POWER' => 'SENEC:inverter_power',
            'INFLUX_SENSOR_HOUSE_POWER' => 'SENEC:house_power',
          },
        },
        'ingest' => {
          'image' => 'ghcr.io/solectrus/ingest:latest',
          'environment' => { 'RETENTION_HOURS' => '48' },
        },
      }

      instance_double(
        Import::StackReader,
        services: services_hash,
        service: nil,
        raw_env: { 'INFLUX_TOKEN' => 'token', 'INFLUX_ORG' => 'solectrus', 'INFLUX_BUCKET' => 'solectrus' },
        raw_compose: { 'services' => services_hash },
      ).tap do |double|
        allow(double).to receive(:service) { |name| double.services[name] }
      end
    end

    it 'skips the ingest section (inconsistent stack — Ingest needs split inverters)' do
      expect(importer.result[:ingest]).to be_nil
    end

    it 'does not flag any sensor as balcony power plant' do
      config = importer.import!
      expect(config.sensor_config('inverter_power').is_balcony).to be_nil
    end

    it 'results in ingest_required? being false' do
      importer.import!
      expect(Configuration.current.ingest_required?).to be false
    end
  end
end
