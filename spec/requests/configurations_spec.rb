RSpec.describe 'Configurations', :with_admin do
  before do
    with_config_yaml
    login
  end

  describe 'GET /configuration' do
    it 'renders the configuration page' do
      get configuration_path

      expect(response).to have_http_status(:ok)
    end

    it 'displays sensor group headers' do
      get configuration_path

      SensorRegistry::GROUPS.each_key do |group|
        title = I18n.t("sensor_groups.#{group}")
        expect(response.body).to include(title)
      end
    end

    it 'displays setting section titles' do
      get configuration_path

      Configuration::SETTINGS.each do |setting|
        title = I18n.t("configurations.settings.#{setting}.title")
        expect(response.body).to include(title)
      end
    end

    it 'displays enabled sensors' do
      config = Configuration.current
      config.update_sensor('inverter_power', { 'source' => 'senec' })

      get configuration_path

      expect(response.body).to include('inverter_power')
    end
  end
end
