RSpec.describe 'Sensors', :with_admin_password do
  before do
    with_config_yaml
    login
  end

  describe 'GET /sensors' do
    it 'renders the sensors page' do
      get sensors_path

      expect(response).to have_http_status(:ok)
    end

    it 'displays sensor group headers' do
      cookies[:preferences] = { hide_unused: false }.to_json

      get sensors_path

      SensorRegistry::GROUPS.each_key do |group|
        title = I18n.t("sensor_groups.#{group}")
        expect(response.body).to include(title)
      end
    end

    it 'displays enabled sensors' do
      config = Configuration.current
      config.update_sensor('inverter_power', { 'source' => 'senec' })

      get sensors_path

      expect(response.body).to include('inverter_power')
    end
  end
end
