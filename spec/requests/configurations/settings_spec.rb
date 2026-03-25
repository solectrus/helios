RSpec.describe 'Configurations::Settings', :with_admin_password do
  before do
    with_config_yaml
    login
  end

  describe 'GET /configuration/settings/new' do
    it 'renders the survey form for a sensor' do
      get new_configuration_setting_path(setting: 'sensor', name: 'inverter_power')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('survey')
    end

    it 'renders the survey form for a singleton' do
      get new_configuration_setting_path(setting: 'system')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('survey')
    end

    it 'redirects for invalid setting' do
      get new_configuration_setting_path(setting: 'nonexistent')

      expect(response).to redirect_to(configuration_path)
    end
  end

  describe 'POST /configuration/settings' do
    it 'creates a sensor' do
      sensor_data = { 'source' => 'senec' }

      post configuration_settings_path,
           params: { setting: 'sensor', name: 'inverter_power', data: sensor_data.to_json }

      expect(response).to redirect_to(configuration_path)

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

    it 'creates a singleton and redirects to configuration' do
      post configuration_settings_path,
           params: { setting: 'system', data: { timezone: 'Europe/Berlin' }.to_json }

      expect(response).to redirect_to(configuration_path)

      config = Configuration.current
      expect(config.system.timezone).to eq('Europe/Berlin')
    end
  end

  describe 'GET /configuration/:setting/:name/edit' do
    it 'renders the survey form for an existing sensor' do
      config = Configuration.current
      config.update_sensor('inverter_power', { 'source' => 'senec' })

      get edit_configuration_setting_path(setting: 'sensor', name: 'inverter_power')

      expect(response).to have_http_status(:ok)
    end

    it 'normalizes measurement and field for fixed-source sensors' do
      config = Configuration.current
      config.update_sensor('inverter_power', {
                             'source' => 'senec',
                             'measurement' => 'WRONG',
                             'field' => 'wrong_field',
                           })

      get edit_configuration_setting_path(setting: 'sensor', name: 'inverter_power')

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

      get edit_configuration_setting_path(setting: 'sensor', name: 'inverter_power')

      expect(response.body).to include('&quot;MySENEC&quot;')
    end

    it 'renders the survey form for an existing singleton' do
      config = Configuration.current
      config.update('system', { 'timezone' => 'UTC' })

      get edit_configuration_setting_path(setting: 'system', name: 'system')

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

      expect(response).to redirect_to(configuration_path)

      config = Configuration.current
      expect(config.sensor_config('inverter_power').source).to eq('mqtt')
    end

    it 'updates a singleton without changing name' do
      setting_data = { 'app_host' => 'example.com' }

      patch configuration_setting_path(setting: 'system', name: 'system'),
            params: { data: setting_data.to_json }

      expect(response).to redirect_to(configuration_path)

      config = Configuration.current
      expect(config.system.app_host).to eq('example.com')
    end
  end

  describe 'DELETE /configuration/:setting/:name' do
    it 'deletes a sensor' do
      config = Configuration.current
      config.update_sensor('inverter_power', { 'source' => 'senec' })

      delete configuration_setting_path(setting: 'sensor', name: 'inverter_power')

      expect(response).to redirect_to(configuration_path)
      expect(Configuration.current.sensor_enabled?('inverter_power')).to be false
    end
  end
end
