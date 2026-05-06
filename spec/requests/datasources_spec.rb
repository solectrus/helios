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

    it 'shows the Sensors nav tab in full mode' do
      get datasources_path

      expect(response.body).to match(/href="#{sensors_path}"/)
    end

    it 'hides the Sensors nav tab in collectors_only mode' do
      with_config_yaml('system' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY })

      get datasources_path

      expect(response.body).not_to match(/href="#{sensors_path}"/)
    end

    context 'when in collectors_only mode' do
      before { with_config_yaml('system' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY }) }

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

        expect(response.body).to match(/href="#{datasources_shelly_devices_path}"/)
      end
    end

    it 'does not link to the Shelly devices CRUD in full mode' do
      get datasources_path

      expect(response.body).not_to match(/href="#{datasources_shelly_devices_path}"/)
    end
  end
end
