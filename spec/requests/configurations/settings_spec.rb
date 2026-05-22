RSpec.describe 'Configurations::Settings', :with_admin_password do
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

    it 'merges a mini-survey into its parent singleton without dropping siblings' do
      Configuration.current.update('system', { 'admin_password' => 'secret', 'timezone' => 'UTC' })

      post configuration_settings_path,
           params: { setting: 'system_security', data: { admin_password: 'new-secret' }.to_json }

      config = Configuration.current
      expect(config.system.admin_password).to eq('new-secret')
      expect(config.system.timezone).to eq('UTC')
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
end
