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

    it 'auto-activates other SENEC-capable sensors that are not yet configured' do
      post configuration_settings_path,
           params: { setting: 'sensor', name: 'inverter_power', data: { 'source' => 'senec' }.to_json }

      config = Configuration.current
      expect(config.sensor_config('grid_import_power').source).to eq('senec')
      expect(config.sensor_config('battery_soc').source).to eq('senec')
    end

    it 'creates a singleton and redirects to the advanced page' do
      post configuration_settings_path,
           params: { setting: 'system_general', data: { timezone: 'Europe/Berlin' }.to_json }

      expect(response).to redirect_to(advanced_path)

      config = Configuration.current
      expect(config.system.timezone).to eq('Europe/Berlin')
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

    it 'derives mode=external from a stored bind_ip when editing' do
      Configuration.current.update('reverse_proxy', { 'bind_ip' => '10.0.0.5' })

      get edit_configuration_setting_path(setting: 'reverse_proxy', name: 'reverse_proxy'),
          headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('&quot;10.0.0.5&quot;')
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
