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
  end
end
