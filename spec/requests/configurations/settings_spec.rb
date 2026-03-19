RSpec.describe 'Configurations::Settings', :with_admin do
  before do
    with_config_yaml
    login
  end

  describe 'GET /configuration/settings/new' do
    it 'renders the survey form for a valid device type' do
      get new_configuration_setting_path(setting: 'inverter')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('survey')
    end

    it 'redirects for invalid setting' do
      get new_configuration_setting_path(setting: 'nonexistent')

      expect(response).to redirect_to(configuration_path)
    end
  end

  describe 'POST /configuration/settings' do
    it 'creates a device with identifier as YAML key' do
      setting_data = {
        'name' => 'Dach Süd',
        'identifier' => 'dach-sued',
        'data_source' => 'senec_local',
        'senec_host' => '192.168.1.42',
      }

      post configuration_settings_path,
           params: { setting: 'inverter', data: setting_data.to_json }

      expect(response).to redirect_to(configuration_path)

      config = Configuration.current
      expect(config.inverter('dach-sued')).to eq(
        'name' => 'Dach Süd',
        'data_source' => 'senec_local',
        'senec_host' => '192.168.1.42',
      )
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
    it 'renders the survey form for an existing device' do
      config = Configuration.current
      config.add('inverter', 'dach-sued', { 'name' => 'Dach Süd' })

      get edit_configuration_setting_path(setting: 'inverter', name: 'dach-sued')

      expect(response).to have_http_status(:ok)
    end

    it 'renders the survey form for an existing singleton' do
      config = Configuration.current
      config.update('system', { 'timezone' => 'UTC' })

      get edit_configuration_setting_path(setting: 'system', name: 'system')

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'PATCH /configuration/:setting/:name' do
    it 'updates a device including identifier change' do
      config = Configuration.current
      config.add('inverter', 'dach-sued', { 'name' => 'Dach Süd' })

      setting_data = {
        'name' => 'Dach Nord',
        'identifier' => 'dach-nord',
        'data_source' => 'senec_local',
        'senec_host' => '192.168.1.42',
      }

      patch configuration_setting_path(setting: 'inverter', name: 'dach-sued'),
            params: { data: setting_data.to_json }

      expect(response).to redirect_to(configuration_path)

      config = Configuration.current
      expect(config.inverter('dach-nord')).to eq(
        'name' => 'Dach Nord',
        'data_source' => 'senec_local',
        'senec_host' => '192.168.1.42',
      )
      expect(config.inverter('dach-sued')).to eq({})
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
    it 'deletes the device' do
      config = Configuration.current
      config.add('inverter', 'dach-sued', { 'name' => 'Dach Süd' })

      delete configuration_setting_path(setting: 'inverter', name: 'dach-sued')

      expect(response).to redirect_to(configuration_path)
      expect(Configuration.current.inverter('dach-sued')).to eq({})
    end
  end
end
