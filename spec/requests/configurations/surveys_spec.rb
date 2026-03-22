RSpec.describe 'Configurations::Surveys', :with_admin_password do
  before { login }

  describe 'GET /configuration/surveys/:id' do
    (Configuration::ALL - Configuration::HIDDEN).each do |setting|
      next if setting == 'sensors' # sensors is dynamic, no survey file

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

    it 'shows fixed-source hint for senec sensors' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power' })

      survey = response.parsed_body
      mapping_page = survey['pages'].find { |p| p['name'] == 'p_mapping' }
      fixed_hint = mapping_page['elements'].find { |e| e['name'] == 'mapping_hint_fixed' }

      expect(mapping_page).not_to have_key('description')
      expect(fixed_hint['visibleIf']).to eq("{source} = 'senec'")
      expect(fixed_hint['html']['de']).to include('SENEC-Collector')
    end

    it 'shows editable hint for non-fixed sources' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power' })

      survey = response.parsed_body
      mapping_page = survey['pages'].find { |p| p['name'] == 'p_mapping' }
      editable_hint = mapping_page['elements'].find { |e| e['name'] == 'mapping_hint_editable' }

      expect(editable_hint['visibleIf']).to eq("{source} != 'senec'")
      expect(editable_hint['html']['de']).to include('⚠️')
    end

    it 'keeps static description for sensors without fixed sources' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'heatpump_power' })

      survey = response.parsed_body
      mapping_page = survey['pages'].find { |p| p['name'] == 'p_mapping' }

      expect(mapping_page['description']).to be_present
      expect(mapping_page['elements'].none? { |e| e['name'] == 'mapping_hint_fixed' }).to be true
    end

    it 'locks measurement and field for senec sensors' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power' })

      survey = response.parsed_body
      mapping_page = survey['pages'].find { |p| p['name'] == 'p_mapping' }
      measurement_element = mapping_page['elements'].find { |e| e['name'] == 'measurement' }
      field_element = mapping_page['elements'].find { |e| e['name'] == 'field' }

      # Both measurement and field are locked for senec
      expect(measurement_element['enableIf']).to eq("{source} != 'senec'")
      expect(measurement_element['setValueIf']).to eq("{source} = 'senec'")
      expect(field_element['enableIf']).to eq("{source} != 'senec'")
      expect(field_element['setValueIf']).to eq("{source} = 'senec'")
    end

    it 'uses default SENEC measurement when no collector config exists' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power' })

      survey = response.parsed_body
      mapping_page = survey['pages'].find { |p| p['name'] == 'p_mapping' }
      measurement_element = mapping_page['elements'].find { |e| e['name'] == 'measurement' }

      expect(measurement_element['setValueExpression']).to include("'SENEC'")
    end

    it 'does not lock mapping for sensors without fixed-field sources' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'heatpump_power' })

      survey = response.parsed_body
      mapping_page = survey['pages'].find { |p| p['name'] == 'p_mapping' }
      measurement_element = mapping_page['elements'].find { |e| e['name'] == 'measurement' }
      field_element = mapping_page['elements'].find { |e| e['name'] == 'field' }

      expect(measurement_element).not_to have_key('enableIf')
      expect(field_element).not_to have_key('enableIf')
    end

    it 'locks measurement and field for forecast sensors' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power_forecast' })

      survey = response.parsed_body
      mapping_page = survey['pages'].find { |p| p['name'] == 'p_mapping' }
      measurement_element = mapping_page['elements'].find { |e| e['name'] == 'measurement' }
      field_element = mapping_page['elements'].find { |e| e['name'] == 'field' }

      expect(measurement_element['enableIf']).to eq("{source} != 'forecast'")
      expect(measurement_element['setValueExpression']).to include("'Forecast'")
      expect(field_element['enableIf']).to eq("{source} != 'forecast'")
    end

    it 'shows Forecast-Collector in hint for forecast sensors' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power_forecast' })

      survey = response.parsed_body
      mapping_page = survey['pages'].find { |p| p['name'] == 'p_mapping' }
      fixed_hint = mapping_page['elements'].find { |e| e['name'] == 'mapping_hint_fixed' }

      expect(fixed_hint['html']['de']).to include('Forecast-Collector')
      expect(fixed_hint['html']['de']).not_to include('SENEC')
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
