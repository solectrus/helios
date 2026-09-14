RSpec.describe 'Configurations::Surveys', :with_admin_password do
  before do
    with_config_yaml
    login
  end

  # A sensor can only be put on a source that is set up, so a spec about the
  # choices themselves has to switch the sources on first.
  def set_up_all_sources
    config = Configuration.current
    config.update('senec', { 'version' => '4', 'host' => 'senec.local' })
    config.update('shelly', { 'connection' => 'local' })
    config.update('mqtt', { 'broker_managed' => true })
  end

  def source_element_of(survey)
    survey['pages'].flat_map { |page| page['elements'] || [] }.find { |element| element['name'] == 'source' }
  end

  describe 'GET /configuration/surveys/:id' do
    (Configuration::ALL - Configuration::HIDDEN).each do |setting|
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

    describe 'the MQTT survey' do
      def broker_settings_elements
        get configuration_survey_path(id: 'mqtt')
        page = response.parsed_body['pages'].find { |p| p['name'] == 'p_mqtt_broker_settings' }
        page['elements']
      end

      def broker_page_elements
        broker_settings_elements.pluck('name')
      end

      def broker_port_validators
        broker_settings_elements.find { |element| element['name'] == 'port' }['validators']
      end

      # The reverse proxy can be switched on after the port is set, so the
      # check must not ask whether it runs today.
      it 'keeps the broker off the ports the stack claims for itself' do
        expect(broker_port_validators.pluck('expression')).to eq(
          ['{port} <> 80 and {port} <> 443 and {port} <> 3000 and {port} <> 3999 and ' \
           '{port} <> 4567 and {port} <> 8086 and {port} <> 8883'],
        )
      end

      # The dashboard and InfluxDB ports are picked by the user, in surveys
      # of their own, so the list has to read them rather than name them.
      it 'reads the ports the user picked for the other services' do
        with_config_yaml(
          'dashboard' => { 'host_port' => '3001' },
          'influxdb' => { 'host_port' => '1884' },
        )

        expect(broker_port_validators.pluck('expression')).to eq(
          ['{port} <> 80 and {port} <> 443 and {port} <> 1884 and {port} <> 3001 and {port} <> 3999 and ' \
           '{port} <> 4567 and {port} <> 8883'],
        )
      end

      # The page asks for the broker and nothing else. Where devices reach it
      # is answered by the card on the datasources screen.
      it 'asks for the broker itself, without hints around it' do
        expect(broker_page_elements).to eq(%w[port username password])
      end

      # A broker HELIOS runs never takes messages from anyone. The survey is
      # where that is settled, so neither half of the login can be skipped
      # (see Export::Services::Mosquitto#config_lines).
      it 'demands both halves of the broker login' do
        required = broker_settings_elements.select { |element| element['isRequired'] }

        expect(required.pluck('name')).to include('username', 'password')
      end

      def broker_external_default
        get configuration_survey_path(id: 'mqtt')
        page = response.parsed_body['pages'].find { |p| p['name'] == 'p_mqtt_broker' }
        page['elements'].find { |element| element['name'] == 'broker_external' }['defaultValue']
      end

      it 'assumes a broker of the user by default' do
        expect(broker_external_default).to be(true)
      end

      it 'reopens on the managed broker once HELIOS runs one' do
        with_config_yaml('mqtt' => { 'broker_managed' => true })

        expect(broker_external_default).to be(false)
      end
    end

    describe 'the storage survey' do
      def storage_rows
        get configuration_survey_path(id: 'storage')
        response.parsed_body['pages'].first['elements'].pluck('name')
      end

      it 'lists the broker folder once HELIOS runs the broker' do
        with_config_yaml('mqtt' => { 'broker_managed' => true })

        expect(storage_rows).to include('mosquitto')
      end

      it 'leaves it out for a foreign broker' do
        expect(storage_rows).not_to include('mosquitto')
      end
    end

    describe 'the dynamic-prices survey' do
      it 'asks for the prices alone without a locally-queried SENEC battery' do
        get configuration_survey_path(id: 'tibber')

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['pages'].pluck('name')).to eq(%w[p_enable p_token])
      end

      it 'adds the charging questions once a local battery and a forecast exist' do
        with_config_yaml(
          'senec' => { 'adapter' => 'local' },
          'forecast' => { 'forecast' => 'forecast.solar' },
          'sensors' => { 'inverter_power_forecast' => { 'source' => 'forecast', 'measurement' => 'Forecast' } },
        )

        get configuration_survey_path(id: 'tibber')

        expect(response.parsed_body['pages'].pluck('name'))
          .to eq(%w[p_enable p_token p_charging p_price p_forecast p_options])
      end
    end

    # A sensor can only be put on a source that is set up, so the choices
    # follow the data sources screen.
    it 'returns sensor survey with dynamic source choices' do
      Configuration.current.update('senec', { 'version' => '4', 'host' => 'senec.local' })

      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power' })

      expect(response).to have_http_status(:ok)
      survey = response.parsed_body
      source_page = survey['pages'].first
      source_element = source_page['elements'].find { |e| e['name'] == 'source' }

      expect(source_element['choices']).to be_present
      expect(source_element['choices'].pluck('value')).to include('senec')
    end

    # A sensor can no longer bring a source into being: the source has to be
    # switched on under Data Sources first.
    it 'leaves out a source that is not set up' do
      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power' })

      element = source_element_of(response.parsed_body)

      expect(element['choices'].pluck('value')).to eq(['external'])
      expect(element['description']['de']).to include('Datenquellen')
    end

    it 'says nothing about missing sources once they are all set up' do
      config = Configuration.current
      config.update('senec', { 'version' => '4', 'host' => 'senec.local' })
      config.update('mqtt', { 'broker_managed' => true })

      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power' })

      element = source_element_of(response.parsed_body)

      expect(element['choices'].pluck('value')).to eq(%w[senec mqtt external])
      expect(element['description']).to be_nil
    end

    # Opening the survey of such a sensor must not silently drop its source.
    it 'keeps the source a sensor already reads through' do
      Configuration.current.update_sensor('inverter_power', { 'source' => 'senec' })

      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power' })

      element = source_element_of(response.parsed_body)

      expect(element['choices'].pluck('value')).to eq(%w[senec external])
    end

    it 'adds inline explanations to dynamic sensor source choices' do
      set_up_all_sources

      get configuration_survey_path(id: 'sensor', format: :json, params: { sensor: 'inverter_power_2' })

      choices = source_element_of(response.parsed_body)['choices'].index_by { |choice| choice['value'] }

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
