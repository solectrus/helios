RSpec.describe 'Datasources', :with_admin_password do
  before do
    with_config_yaml
    login
  end

  describe 'GET /datasources' do
    it 'renders the datasources page' do
      get datasources_path

      expect(response).to have_http_status(:ok)
    end

    it 'shows source settings for active sources' do
      config = Configuration.current
      config.update_sensor('inverter_power', { 'source' => 'senec' })

      get datasources_path

      title = I18n.t('configurations.settings.senec.title')
      expect(response.body).to include(title)
    end

    # A source has to be set up before a sensor can read through it, so every
    # source stands on the screen from the start.
    it 'offers every source although nothing reads through them' do
      get datasources_path

      Configuration::SOURCE_CONFIGS.each do |source|
        expect(response.body).to include(I18n.t("configurations.settings.#{source}.title"))
      end
    end

    # The cards are an offer, not a gap: a source nothing reads through must
    # never hold the stack back.
    it 'counts the offered sources as neither active nor incomplete' do
      config = Configuration.current

      expect(config.offered_sources).to eq(Configuration::ALL_SOURCES)
      expect(config.active_sources).to be_empty
      expect(config.incomplete_sources).to be_empty
    end

    # It has no settings to make, so it is not switched on here: a sensor is
    # put on this source on the sensors screen.
    it 'offers the external input although no sensor is fed that way' do
      get datasources_path

      expect(response.body).to include(I18n.t('external_input_info.component.title'))
    end

    # A CSV import fills sensors that exist, so it waits, dimmed, until some do.
    it 'offers the CSV import before a sensor can be filled' do
      get datasources_path

      expect(response.body).to include(I18n.t('datasources.show.csv_import.title'))
    end

    it 'dims a source that is not set up' do
      get datasources_path

      expect(response.body).to include('opacity-55')
    end

    it 'shows a source that is set up at full strength' do
      config = Configuration.current
      config.update('senec', { 'version' => '4', 'host' => 'senec.local' })
      config.update('shelly', { 'connection' => 'local' })
      config.update('forecast', { 'forecast' => 'pvnode' })
      config.update('mqtt', { 'mqtt_host' => 'broker.local' })
      config.update_sensor('inverter_power_4', { 'source' => 'external', 'measurement' => 'm', 'field' => 'f' })

      get datasources_path

      expect(response.body).not_to include('opacity-55')
    end

    # Switching a source off takes the sensors that read through it along, so
    # the question on the card says how many.
    it 'names the sensors that a switch off would take along' do
      config = Configuration.current
      config.update('senec', { 'version' => '4', 'host' => 'senec.local' })
      config.update_sensor('inverter_power', { 'source' => 'senec' })

      get datasources_path

      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t('configurations.settings.toggle_confirm_sensors', count: 1)),
      )
    end

    # A sensor is what puts these sources to work, and that step lives on the
    # sensors screen.
    it 'leads from a sensor-driven source to the sensors' do
      get datasources_path

      expect(response.body).to include(I18n.t('datasources.inline.sensors'))
      expect(response.body).to include("href=\"#{sensors_path}\"")
    end

    # In dashboard_only mode the device collectors run on a remote host.
    it 'offers only the sources the mode allows' do
      with_config_yaml('deployment' => { 'mode' => 'dashboard_only' })

      expect(Configuration.current.offered_sources).to eq(%w[forecast external])
    end

    it 'flags an unconfigured source with sensors as incomplete' do
      Configuration.current.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })

      get datasources_path

      expect(response.body).to include(I18n.t('configurations.show.incomplete'))
      expect(response.body).to include(I18n.t('configurations.settings.forecast.title'))
      expect(response.body).to include('fa-triangle-exclamation')
    end

    it 'still flags incomplete when only auxiliary forecast fields are set' do
      config = Configuration.current
      config.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })
      config.update(:forecast, { 'measurement' => 'forecast' })

      expect(config.incomplete_sources).to eq(['forecast'])

      get datasources_path

      expect(response.body).to include(I18n.t('configurations.show.incomplete'))
    end

    # A managed broker has no host to fill in, so the card must not nag for one.
    it 'treats MQTT as complete once HELIOS runs the broker' do
      config = Configuration.current
      config.update_sensor('house_power', { 'source' => 'mqtt', 'mqtt_topic' => 'home/power' })
      config.update(:mqtt, { 'broker_managed' => true })

      expect(config.incomplete_sources).to be_empty
    end

    it 'shows the Sensors nav tab in full mode' do
      get datasources_path

      expect(response.body).to include("href=\"#{sensors_path}\"")
    end

    it 'hides the Sensors nav tab in collectors_only mode' do
      with_config_yaml('deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY },
                       'influxdb' => { 'host' => 'influx.example.com' })

      get datasources_path

      expect(response.body).not_to include("href=\"#{sensors_path}\"")
    end

    context 'when in collectors_only mode' do
      before do
        with_config_yaml('deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY },
                         'influxdb' => { 'host' => 'influx.example.com' })
      end

      it 'shows all four collector cards regardless of active_sources' do
        expect(Configuration.current.active_sources).to be_empty

        get datasources_path

        Configuration::SOURCE_CONFIGS.each do |source|
          title = I18n.t("configurations.settings.#{source}.title")
          expect(response.body).to include(title)
        end
      end

      it 'links to the Shelly devices CRUD inside the Shelly card' do
        get datasources_path

        expect(response.body).to include("href=\"#{datasources_shelly_devices_path}\"")
      end
    end

    it 'does not link to the Shelly devices CRUD in full mode without devices' do
      get datasources_path

      expect(response.body).not_to include("href=\"#{datasources_shelly_devices_path}\"")
    end

    it 'shows the Shelly card and device CRUD in full mode with standalone devices' do
      with_config_yaml(
        'shelly' => {
          'connection' => 'local',
          'devices' => [{ 'name' => 'Oven', 'host' => 'oven.local', 'measurement' => 'oven' }],
        },
      )

      get datasources_path

      expect(response.body).to include(I18n.t('configurations.settings.shelly.title'))
      expect(response.body).to include("href=\"#{datasources_shelly_devices_path}\"")
    end
  end
end
