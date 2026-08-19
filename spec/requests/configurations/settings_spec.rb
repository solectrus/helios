RSpec.describe 'Configurations::Settings', :with_admin_password do
  include ActiveSupport::Testing::TimeHelpers

  before do
    with_config_yaml
    login
  end

  describe 'GET /configuration/settings/new' do
    it 'renders the survey form for a sensor' do
      get new_configuration_setting_path(setting: 'sensor', name: 'inverter_power'),
          headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('survey')
    end

    it 'renders the survey form for a singleton' do
      get new_configuration_setting_path(setting: 'system_general'), headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('survey')
    end

    it 'renders the survey form for the backup schedule' do
      get new_configuration_setting_path(setting: 'backup_schedule'), headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('survey')
    end

    it 'redirects for invalid setting' do
      get new_configuration_setting_path(setting: 'nonexistent')

      expect(response).to redirect_to(sensors_path)
    end

    it 'redirects non-frame requests to the sensor page for sensor settings' do
      get new_configuration_setting_path(setting: 'sensor', name: 'inverter_power')

      expect(response).to redirect_to(sensors_path)
    end

    it 'redirects non-frame requests to the advanced page for singleton settings' do
      get new_configuration_setting_path(setting: 'system_general')

      expect(response).to redirect_to(advanced_path)
    end
  end

  describe 'POST /configuration/settings' do
    it 'creates a sensor' do
      sensor_data = { 'source' => 'senec' }

      post configuration_settings_path,
           params: { setting: 'sensor', name: 'inverter_power', data: sensor_data.to_json }

      expect(response).to redirect_to(sensors_path)

      config = Configuration.current
      expect(config.sensor_config('inverter_power').source).to eq('senec')
    end

    it 'normalizes measurement and field for fixed-source sensors on save' do
      sensor_data = { 'source' => 'senec', 'measurement' => 'WRONG', 'field' => 'wrong' }

      post configuration_settings_path,
           params: { setting: 'sensor', name: 'inverter_power', data: sensor_data.to_json }

      config = Configuration.current
      expect(config.sensor_config('inverter_power').measurement).to eq('SENEC')
      expect(config.sensor_config('inverter_power').field).to eq('inverter_power')
    end

    it 'keeps a measurement holding a space, which line protocol escapes' do
      sensor_data = { 'source' => 'external', 'measurement' => 'PQ Inverter', 'field' => 'power' }

      post configuration_settings_path,
           params: { setting: 'sensor', name: 'inverter_power', data: sensor_data.to_json }

      expect(Configuration.current.sensor_config('inverter_power').measurement).to eq('PQ Inverter')
    end

    # The survey refuses these client-side; this covers a request going around
    # the UI. A comma would split INFLUX_MEASUREMENT, a colon the sensor
    # mapping, and InfluxDB reserves the leading underscore for itself.
    ['PQ,Inverter', 'PQ:Inverter', '_inverter'].each do |measurement|
      it "refuses to store the measurement #{measurement.inspect}" do
        sensor_data = { 'source' => 'external', 'measurement' => measurement, 'field' => 'power' }

        post configuration_settings_path,
             params: { setting: 'sensor', name: 'inverter_power', data: sensor_data.to_json }

        expect(response).to redirect_to(sensors_path)
        expect(flash[:alert]).to include(measurement)
        expect(Configuration.current.sensor_config('inverter_power').measurement).to be_nil
      end
    end

    it 'refuses a field starting with the reserved underscore' do
      sensor_data = { 'source' => 'external', 'measurement' => 'inverter', 'field' => '_power' }

      post configuration_settings_path,
           params: { setting: 'sensor', name: 'inverter_power', data: sensor_data.to_json }

      expect(flash[:alert]).to include('_power')
      expect(Configuration.current.sensor_config('inverter_power').field).to be_nil
    end

    # A fixed source overwrites measurement and field on save, so the payload's
    # names never reach storage and must not block the save either.
    it 'accepts an unusable measurement when the source overwrites it anyway' do
      sensor_data = { 'source' => 'senec', 'measurement' => 'a,b', 'field' => 'c' }

      post configuration_settings_path,
           params: { setting: 'sensor', name: 'inverter_power', data: sensor_data.to_json }

      expect(Configuration.current.sensor_config('inverter_power').measurement).to eq('SENEC')
    end

    it 'auto-activates other SENEC-capable sensors that are not yet configured' do
      post configuration_settings_path,
           params: { setting: 'sensor', name: 'inverter_power', data: { 'source' => 'senec' }.to_json }

      config = Configuration.current
      expect(config.sensor_config('grid_import_power').source).to eq('senec')
      expect(config.sensor_config('battery_soc').source).to eq('senec')
    end

    it 'creates a singleton and redirects to the advanced page' do
      post configuration_settings_path,
           params: { setting: 'system_general', data: { timezone: 'Europe/Berlin', currency: 'CHF' }.to_json }

      expect(response).to redirect_to(advanced_path)

      config = Configuration.current
      expect(config.system.timezone).to eq('Europe/Berlin')
      expect(config.system.currency).to eq('CHF')
    end

    it 'persists the automatic-backup schedule in its own section' do
      post configuration_settings_path,
           params: { setting: 'backup_schedule',
                     data: { schedule_enabled: true, schedule_time: '04:15' }.to_json }

      config = Configuration.current
      expect(config.backup_schedule.schedule_enabled).to be(true)
      expect(config.backup_schedule.schedule_time).to eq('04:15')
    end

    it 'anchors a still-ahead time to run today' do
      # 09:00 in the app timezone; reschedule! reads Time.current in that zone
      travel_to Time.zone.local(2026, 5, 29, 9, 0, 0) do
        BackupScheduler.send(:mark_handled!, Date.new(2026, 5, 29))

        post configuration_settings_path,
             params: { setting: 'backup_schedule', data: { schedule_enabled: true, schedule_time: '10:00' }.to_json }

        expect(BackupScheduler.last_handled_date).to be_nil
      end
    end

    it 'anchors an already-passed time to tomorrow' do
      # 09:00 in the app timezone; reschedule! reads Time.current in that zone
      travel_to Time.zone.local(2026, 5, 29, 9, 0, 0) do
        post configuration_settings_path,
             params: { setting: 'backup_schedule', data: { schedule_enabled: true, schedule_time: '03:00' }.to_json }

        expect(BackupScheduler.last_handled_date).to eq(Date.new(2026, 5, 29))
      end
    end

    it 'edits the schedule without touching the backup destination section' do
      Configuration.current.update('backup', { 'destination' => 'external', 'external_path' => '/mnt/nas' })

      post configuration_settings_path,
           params: { setting: 'backup_schedule', data: { schedule_enabled: true, schedule_time: '02:00' }.to_json }

      config = Configuration.current
      expect(config.backup.destination).to eq('external')
      expect(config.backup.external_path).to eq('/mnt/nas')
      expect(config.backup_schedule.schedule_time).to eq('02:00')
    end

    it 'merges a mini-survey into its parent singleton without dropping siblings' do
      Configuration.current.update('system', { 'admin_password' => 'secret', 'timezone' => 'UTC' })

      post configuration_settings_path,
           params: { setting: 'system_security', data: { admin_password: 'new-secret' }.to_json }

      config = Configuration.current
      expect(config.system.admin_password).to eq('new-secret')
      expect(config.system.timezone).to eq('UTC')
    end
  end

  describe 'POST /configuration/settings for the reverse_proxy mode' do
    it 'stores app_domain for the internal Traefik mode' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'internal', app_domain: 'demo.example.com' }.to_json }

      config = Configuration.current
      expect(config.reverse_proxy.app_domain).to eq('demo.example.com')
      expect(config.reverse_proxy.bind_ip).to be_blank
    end

    it 'stores bind_ip for the external Traefik mode and drops app_domain' do
      Configuration.current.update('reverse_proxy', { 'app_domain' => 'old.example.com' })

      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'external', bind_ip: '10.0.0.5', app_domain: 'old.example.com' }.to_json }

      config = Configuration.current
      expect(config.reverse_proxy.bind_ip).to eq('10.0.0.5')
      expect(config.reverse_proxy.app_domain).to be_blank
    end

    it 'clears the section for mode none' do
      Configuration.current.update('reverse_proxy', { 'app_domain' => 'old.example.com' })

      post configuration_settings_path,
           params: { setting: 'reverse_proxy', data: { mode: 'none' }.to_json }

      expect(Configuration.current.reverse_proxy.app_domain).to be_blank
    end

    it 'keeps the external Traefik mode even without a bind_ip' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy', data: { mode: 'external' }.to_json }

      config = Configuration.current
      expect(config.reverse_proxy.mode).to eq('external')
      expect(config.reverse_proxy_external?).to be true
    end

    it 'preselects the external mode on reload after saving it without a bind_ip' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy', data: { mode: 'external' }.to_json }

      get edit_configuration_setting_path(setting: 'reverse_proxy', name: 'reverse_proxy'),
          headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('&quot;mode&quot;:&quot;external&quot;')
    end

    # FORCE_SSL is a dashboard variable, so the survey borrows the field into
    # the `dashboard` section (issue #416).
    it 'stores force_ssl for the external mode' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'external', bind_ip: '10.0.0.5', force_ssl: true }.to_json }

      config = Configuration.current
      expect(config.dashboard.force_ssl).to be true
      expect(config.reverse_proxy.force_ssl).to be_blank
    end

    # A proxy can terminate TLS without HELIOS knowing a domain, so the flag
    # outlives the section it is edited in.
    it 'keeps force_ssl for mode none' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy', data: { mode: 'none', force_ssl: true }.to_json }

      config = Configuration.current
      expect(config.dashboard.force_ssl).to be true
      expect(config.reverse_proxy.app_domain).to be_blank
    end

    it 'drops force_ssl for the internal mode, which implies HTTPS' do
      Configuration.current.update('dashboard', { 'force_ssl' => true })

      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'internal', app_domain: 'demo.example.com', force_ssl: true }.to_json }

      expect(Configuration.current.dashboard.force_ssl).to be_blank
    end

    it 'derives mode=external from a stored bind_ip when editing' do
      Configuration.current.update('reverse_proxy', { 'bind_ip' => '10.0.0.5' })

      get edit_configuration_setting_path(setting: 'reverse_proxy', name: 'reverse_proxy'),
          headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('&quot;10.0.0.5&quot;')
    end
  end

  describe 'POST /configuration/settings for the dynamic electricity prices' do
    # The survey drives two services: the Tibber collector (its own section) and,
    # where a local battery and a forecast collector exist, the SENEC charger
    # (borrowed fields).
    def with_charging_preconditions
      with_config_yaml(
        'senec' => { 'adapter' => 'local' },
        'forecast' => { 'forecast' => 'forecast.solar' },
        'sensors' => { 'inverter_power_forecast' => { 'source' => 'forecast', 'measurement' => 'Forecast' } },
      )
    end

    def survey_params(**overrides)
      { enabled: true, charging: true, token: 'abc', measurement: 'Prices', interval: '900',
        price_max: '80', price_time_range: '4', forecast_threshold: '15', dry_run: false }.merge(overrides)
    end

    def post_survey(**overrides)
      post configuration_settings_path, params: { setting: 'tibber', data: survey_params(**overrides).to_json }
    end

    it 'splits the survey into the tibber credentials and the charger tuning' do
      with_charging_preconditions

      post_survey

      config = Configuration.current
      expect(config.tibber.to_h).to eq('token' => 'abc', 'measurement' => 'Prices')
      # dry_run is left out: a blank value clears its key, and the export falls
      # back to the same `false` default.
      expect(config.senec_charger.to_h).to eq(
        'interval' => '900', 'price_max' => '80', 'price_time_range' => '4',
        'forecast_threshold' => '15'
      )
      expect(config.senec_charger_available?).to be(true)
      expect(response).to redirect_to(advanced_path)
    end

    it 'stores the test mode when it is switched on' do
      with_charging_preconditions

      post_survey(dry_run: true)

      expect(Configuration.current.senec_charger.dry_run).to be(true)
    end

    it 'collects the prices alone when charging stays off' do
      with_charging_preconditions

      post_survey(charging: false)

      config = Configuration.current
      expect(config.tibber_enabled?).to be(true)
      expect(config.senec_charger_enabled?).to be(false)
    end

    it 'drops the charger tuning when charging is switched back off' do
      with_charging_preconditions
      post_survey

      post_survey(charging: false)

      expect(Configuration.current.senec_charger_enabled?).to be(false)
    end

    it 'supports a stack with no SENEC battery at all, collecting prices for later use' do
      with_config_yaml

      post_survey(charging: false)

      config = Configuration.current
      expect(config.tibber_enabled?).to be(true)
      expect(config.senec_charger_enabled?).to be(false)
    end

    # The charging pages are dropped server-side once a dependency goes, so the
    # payload arrives without a `charging` flag. That is the question never
    # having been asked — reading it as "switched off" would wipe a tuning the
    # user can neither see nor re-enter until the dependency returns.
    it 'keeps the charger tuning when a dependency disappears and the prices are edited' do
      # A configured charger whose forecast collector has since gone: the survey
      # renders the prices half only, so this save carries neither `charging`
      # nor the tuning.
      with_config_yaml(
        'senec' => { 'adapter' => 'local' },
        'tibber' => { 'token' => 'abc', 'measurement' => 'Prices' },
        'senec_charger' => { 'interval' => '900', 'price_max' => '80' },
      )

      post configuration_settings_path,
           params: { setting: 'tibber', data: { enabled: true, token: 'xyz', measurement: 'Prices' }.to_json }

      config = Configuration.current
      expect(config.tibber.token).to eq('xyz')
      expect(config.senec_charger.to_h).to eq('interval' => '900', 'price_max' => '80')
    end

    it 'drops both services when the prices are switched off' do
      with_charging_preconditions
      post_survey

      post configuration_settings_path, params: { setting: 'tibber', data: { enabled: false }.to_json }

      config = Configuration.current
      expect(config.tibber_enabled?).to be(false)
      expect(config.senec_charger_enabled?).to be(false)
    end

    it 'derives both flags from the two sections when editing' do
      with_charging_preconditions
      post_survey

      get edit_configuration_setting_path(setting: 'tibber', name: 'tibber'), headers: turbo_frame_headers

      expect(response.body).to include('&quot;enabled&quot;:true')
      expect(response.body).to include('&quot;charging&quot;:true')
      expect(response.body).to include('&quot;token&quot;:&quot;abc&quot;')
    end

    it 'reports a tibber-only stack as not charging' do
      with_charging_preconditions
      Configuration.current.update('tibber', { 'token' => 'abc' })

      get edit_configuration_setting_path(setting: 'tibber', name: 'tibber'), headers: turbo_frame_headers

      expect(response.body).to include('&quot;enabled&quot;:true')
      expect(response.body).to include('&quot;charging&quot;:false')
    end
  end

  describe 'GET /configuration/:setting/:name/edit' do
    it 'renders the survey form for an existing sensor' do
      config = Configuration.current
      config.update_sensor('inverter_power', { 'source' => 'senec' })

      get edit_configuration_setting_path(setting: 'sensor', name: 'inverter_power'),
          headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
    end

    it 'normalizes measurement and field for fixed-source sensors' do
      config = Configuration.current
      config.update_sensor('inverter_power', {
                             'source' => 'senec',
                             'measurement' => 'WRONG',
                             'field' => 'wrong_field',
                           })

      get edit_configuration_setting_path(setting: 'sensor', name: 'inverter_power'),
          headers: turbo_frame_headers

      expect(response.body).to include('&quot;SENEC&quot;')
      expect(response.body).to include('&quot;inverter_power&quot;')
      expect(response.body).not_to include('&quot;WRONG&quot;')
    end

    it 'uses collector measurement when configured' do
      config = Configuration.current
      config.update('senec', { 'measurement' => 'MySENEC', 'adapter' => 'local', 'host' => '1.2.3.4' })
      config.update_sensor('inverter_power', {
                             'source' => 'senec',
                             'measurement' => 'SENEC',
                             'field' => 'inverter_power',
                           })

      get edit_configuration_setting_path(setting: 'sensor', name: 'inverter_power'),
          headers: turbo_frame_headers

      expect(response.body).to include('&quot;MySENEC&quot;')
    end

    it 'renders the survey form for an existing singleton' do
      config = Configuration.current
      config.update('system', { 'timezone' => 'UTC' })

      get edit_configuration_setting_path(setting: 'system_general', name: 'system_general'),
          headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'PATCH /configuration/:setting/:name' do
    it 'updates a sensor' do
      config = Configuration.current
      config.update_sensor('inverter_power', { 'source' => 'senec' })

      sensor_data = { 'source' => 'mqtt', 'mqtt_topic' => 'pv/power' }

      patch configuration_setting_path(setting: 'sensor', name: 'inverter_power'),
            params: { data: sensor_data.to_json }

      expect(response).to redirect_to(sensors_path)

      config = Configuration.current
      expect(config.sensor_config('inverter_power').source).to eq('mqtt')
    end

    # Switching the source hides the whole MQTT page, so SurveyJS clears the
    # name and the survey's own mandatory-field rule cannot bite.
    it 'refuses a source change that would drop an MQTT name a formula reads' do
      config = Configuration.current
      config.update_sensor('house_power',
                           { 'source' => 'mqtt', 'measurement' => 'm', 'field' => 'f',
                             'mqtt_topic' => 'h/p', 'mqtt_name' => 'house' })
      config.add_mqtt_topic('measurement' => 'm', 'field' => 'rest', 'type' => 'integer',
                            'formula' => '{house} - 100', 'name' => 'rest')

      patch configuration_setting_path(setting: 'sensor', name: 'house_power'),
            params: { data: { 'source' => 'external', 'measurement' => 'm', 'field' => 'f' }.to_json }

      expect(Configuration.current.sensor_config('house_power').source).to eq('mqtt')
      expect(flash[:alert]).to include('rest')
    end

    it 'allows renaming, the formulas follow' do
      config = Configuration.current
      config.update_sensor('house_power',
                           { 'source' => 'mqtt', 'measurement' => 'm', 'field' => 'f',
                             'mqtt_topic' => 'h/p', 'mqtt_name' => 'house' })
      config.add_mqtt_topic('measurement' => 'm', 'field' => 'rest', 'type' => 'integer',
                            'formula' => '{house} - 100', 'name' => 'rest')

      patch configuration_setting_path(setting: 'sensor', name: 'house_power'),
            params: { data: { 'source' => 'mqtt', 'measurement' => 'm', 'field' => 'f',
                              'mqtt_topic' => 'h/p', 'mqtt_name' => 'house_total' }.to_json }

      expect(Configuration.current.mqtt_topic(0)['formula']).to eq('{house_total} - 100')
    end

    it 'updates a singleton without changing name' do
      setting_data = { 'app_host' => 'example.com' }

      patch configuration_setting_path(setting: 'system_network', name: 'system_network'),
            params: { data: setting_data.to_json }

      expect(response).to redirect_to(advanced_path)

      config = Configuration.current
      expect(config.system.app_host).to eq('example.com')
    end

    it 'stores the dashboard theme `user` sentinel as an empty string' do
      patch configuration_setting_path(setting: 'dashboard_theme', name: 'dashboard_theme'),
            params: { data: { 'ui_theme' => 'user' }.to_json }

      expect(response).to redirect_to(advanced_path)
      expect(Configuration.current.dashboard.ui_theme).to eq('')
    end

    it 'stores a fixed dashboard theme verbatim' do
      patch configuration_setting_path(setting: 'dashboard_theme', name: 'dashboard_theme'),
            params: { data: { 'ui_theme' => 'dark' }.to_json }

      expect(Configuration.current.dashboard.ui_theme).to eq('dark')
    end

    it 'redirects to the backups page after saving the backup destination' do
      patch configuration_setting_path(setting: 'backup', name: 'backup'),
            params: { data: { 'destination' => 'local' }.to_json }

      expect(response).to redirect_to(backups_path)
      expect(Configuration.current.backup.destination).to eq('local')
    end

    it 'preserves existing Backup rows when the destination changes' do
      Configuration.current.update('backup', { 'destination' => 'local' })
      Backup.create!(filename: 'solectrus-backup-20260508-110000.tar', bytes: 100,
                     created_at: Time.zone.parse('2026-05-08 11:00:00'), destination: 'local')

      patch configuration_setting_path(setting: 'backup', name: 'backup'),
            params: { data: { 'destination' => 'external', 'external_path' => '/mnt/nas' }.to_json }

      expect(Backup.where(destination: 'local').count).to eq(1)
    end

    it 'rescopes the visible list to the new destination on switch' do
      Configuration.current.update('backup', { 'destination' => 'local' })
      Backup.create!(filename: 'solectrus-backup-20260508-110000.tar', bytes: 100,
                     created_at: Time.zone.parse('2026-05-08 11:00:00'), destination: 'local')

      patch configuration_setting_path(setting: 'backup', name: 'backup'),
            params: { data: { 'destination' => 'external', 'external_path' => '/mnt/nas' }.to_json }

      expect(BackupRepository.all).to be_empty
      expect(Backup.where(destination: 'local').count).to eq(1)
    end
  end

  describe 'DELETE /configuration/:setting/:name' do
    it 'deletes a sensor' do
      config = Configuration.current
      config.update_sensor('inverter_power', { 'source' => 'senec' })

      delete configuration_setting_path(setting: 'sensor', name: 'inverter_power')

      expect(response).to redirect_to(sensors_path)
      expect(Configuration.current.sensor_enabled?('inverter_power')).to be false
    end

    # A formula reads the sensor by its MAPPING_X_NAME. Disabling it leaves a
    # reference that no mapping defines, and mqtt-collector refuses to start.
    it 'refuses while a formula reads the MQTT name' do
      config = Configuration.current
      config.update_sensor('house_power',
                           { 'source' => 'mqtt', 'measurement' => 'm', 'field' => 'f',
                             'mqtt_topic' => 'h/p', 'mqtt_name' => 'house' })
      config.add_mqtt_topic('measurement' => 'm', 'field' => 'rest', 'type' => 'integer',
                            'formula' => '{house} - 100', 'name' => 'rest')

      delete configuration_setting_path(setting: 'sensor', name: 'house_power')

      expect(Configuration.current.sensor_enabled?('house_power')).to be true
      expect(flash[:alert]).to include('rest')
    end
  end

  describe 'read-only settings (storage)' do
    it 'renders the edit form' do
      get edit_configuration_setting_path(setting: 'storage', name: 'storage'),
          headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('survey')
    end

    it 'refuses POST' do
      post configuration_settings_path,
           params: { setting: 'storage', data: { 'postgresql' => '/evil' }.to_json }

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses PATCH' do
      patch configuration_setting_path(setting: 'storage', name: 'storage'),
            params: { setting: 'storage', data: { 'postgresql' => '/evil' }.to_json }

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses DELETE' do
      delete configuration_setting_path(setting: 'storage', name: 'storage')

      expect(response).to have_http_status(:forbidden)
    end
  end
end
