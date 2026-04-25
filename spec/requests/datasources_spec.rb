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

    it 'flags an unconfigured source with sensors as incomplete' do
      Configuration.current.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })

      get datasources_path

      expect(response.body).to include(I18n.t('configurations.show.incomplete'))
      expect(response.body).to include(I18n.t('configurations.settings.forecast.title'))
      expect(response.body).to match(/fa-triangle-exclamation/)
    end

    it 'still flags incomplete when only auxiliary forecast fields are set' do
      config = Configuration.current
      config.update_sensor('inverter_power_forecast', { 'source' => 'forecast' })
      config.update(:forecast, { 'measurement' => 'forecast' })

      expect(config.incomplete_sources).to eq(['forecast'])

      get datasources_path

      expect(response.body).to include(I18n.t('configurations.show.incomplete'))
    end
  end
end
