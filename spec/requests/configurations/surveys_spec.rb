RSpec.describe 'Configurations::Surveys', :with_admin_password do
  before do
    with_config_yaml
    login
  end

  describe 'GET /configuration/surveys/:id' do
    (Configuration::ALL - Configuration::HIDDEN).each do |setting|
      next if setting == 'sensors' # sensors is dynamic, no survey file
      next if setting == 'service_overrides' # advanced overrides edited inline, no survey
      next if setting == 'system' # split into system_* mini-surveys
      next if setting == 'dashboard' # split into dashboard_* mini-surveys
      next if setting == 'ingest' # split into ingest_settings (+ image via software survey)

      it "returns JSON for #{setting} survey" do
        get configuration_survey_path(id: setting)

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq('application/json')
      end
    end

    it 'returns 404 for invalid setting' do
      get configuration_survey_path(id: 'nonexistent')

      expect(response).to have_http_status(:not_found)
    end

    it 'returns sensor survey with dynamic source choices' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power' })

      expect(response).to have_http_status(:ok)
      survey = response.parsed_body
      source_page = survey['pages'].first
      source_element = source_page['elements'].find { |e| e['name'] == 'source' }

      expect(source_element['choices']).to be_present
      expect(source_element['choices'].pluck('value')).to include('senec')
    end

    it 'adds inline explanations to dynamic sensor source choices' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power_2' })

      survey = response.parsed_body
      source_element = survey['pages'].first['elements'].find { |e| e['name'] == 'source' }
      choices = source_element['choices'].index_by { |choice| choice['value'] }

      expect(choices['senec']['text']).to include(
        'default' => include("SENEC Collector\n\nRuns as its own service"),
        'de' => include("SENEC-Collector\n\nLäuft als eigener Dienst"),
      )
      expect(choices['shelly']['text']).to include(
        'default' => include("Shelly Collector\n\nRuns as its own service"),
        'de' => include("Shelly-Collector\n\nLäuft als eigener Dienst"),
      )
      expect(choices['mqtt']['text']).to include(
        'default' => include("MQTT Collector\n\nRuns as its own service"),
        'de' => include("MQTT-Collector\n\nLäuft als eigener Dienst"),
      )
      expect(choices['external']['text']).to include(
        'default' => include("External\n\nAnother software"),
        'de' => include("Extern\n\nEine andere Software"),
      )
    end

    it 'hides mapping page when source is senec' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power' })

      survey = response.parsed_body
      mapping_page = survey['pages'].find { |p| p['name'] == 'p_mapping' }

      expect(mapping_page['visibleIf']).to eq("{source} != 'senec'")
    end

    it 'hides mapping page when source is forecast' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power_forecast' })

      survey = response.parsed_body
      mapping_page = survey['pages'].find { |p| p['name'] == 'p_mapping' }

      expect(mapping_page['visibleIf']).to eq("{source} != 'forecast'")
    end

    it 'always shows mapping page for sensors without fixed sources' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'heatpump_power' })

      survey = response.parsed_body
      mapping_page = survey['pages'].find { |p| p['name'] == 'p_mapping' }

      expect(mapping_page).not_to have_key('visibleIf')
      expect(mapping_page['description']).to be_present
    end

    it 'injects default measurement expression for non-fixed sources' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'heatpump_power' })

      survey = response.parsed_body
      mapping_page = survey['pages'].find { |p| p['name'] == 'p_mapping' }
      measurement_element = mapping_page['elements'].find { |e| e['name'] == 'measurement' }
      field_element = mapping_page['elements'].find { |e| e['name'] == 'field' }

      expect(measurement_element['defaultValueExpression']).to be_present
      expect(field_element['defaultValueExpression']).to be_present
    end

    it 'injects balcony page before the mapping page for balcony-capable sensors' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power_2' })

      survey = response.parsed_body
      names = survey['pages'].pluck('name')
      expect(names.index('p_balcony')).to be < names.index('p_mapping')
    end

    it 'hides balcony page when source is senec' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power_2' })

      survey = response.parsed_body
      balcony_page = survey['pages'].find { |p| p['name'] == 'p_balcony' }

      expect(balcony_page['visibleIf']).to eq("{source} <> 'senec'")
    end

    it 'does not inject balcony page for non-balcony-capable sensors' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power' })

      survey = response.parsed_body
      expect(survey['pages'].pluck('name')).not_to include('p_balcony')
    end

    it 'returns 404 for sensor survey without sensor param' do
      get configuration_survey_path(id: 'sensor')

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for sensor survey with invalid sensor' do
      get configuration_survey_path(id: 'sensor', params: { sensor: 'invalid_sensor' })

      expect(response).to have_http_status(:not_found)
    end
  end
end
