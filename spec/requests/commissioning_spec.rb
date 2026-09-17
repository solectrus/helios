RSpec.describe 'Commissioning' do
  describe 'GET /commissioning' do
    context 'when config.yaml does not exist' do
      before { without_config_yaml }

      it 'asks for the basics' do
        get commissioning_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t('commissioning.show.subtitle'))
        expect(response.body).to include(configuration_survey_path('system_general', format: :json))
      end

      it 'renders without the app chrome' do
        get commissioning_path

        expect(response.body).not_to include(%(href="#{backups_path}"))
      end
    end

    # An import brings in whatever the adopted .env carried. A stack whose
    # dashboard ran always names the date, so this is the rare leftover.
    context 'when an import left the commissioning date behind' do
      before { with_config_yaml('system' => { 'installation_date' => nil }) }

      it 'asks for the basics' do
        get commissioning_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(configuration_survey_path('system_general', format: :json))
      end
    end

    # The date belongs to the dashboard, which runs on another host here. What
    # this mode cannot do without is the address its collectors write to, and
    # the deployment survey is where that is entered.
    context 'when a collectors-only installation names no database' do
      before { with_config_yaml('deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY }) }

      it 'asks for the deployment mode instead' do
        get commissioning_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(configuration_survey_path('deployment', format: :json))
      end
    end

    context 'when the mode has what it needs' do
      before { with_config_yaml }

      it 'redirects to the configuration' do
        get commissioning_path

        expect(response).to redirect_to(sensors_path)
      end
    end
  end

  describe 'POST /commissioning' do
    it 'saves the basics and moves on to the data sources' do
      without_config_yaml

      post commissioning_path,
           params: {
             data: { installation_date: '2024-03-15', timezone: 'Europe/Berlin', currency: 'EUR' }.to_json,
           }

      expect(response).to redirect_to(datasources_path)
      expect(Configuration.current.system.installation_date).to eq('2024-03-15')
      expect(Configuration.current.system.timezone).to eq('Europe/Berlin')
    end

    # The address is a borrowed field of the deployment survey, so the same
    # payload carries the mode and the target (see Configuration::BORROWED_FIELDS).
    it 'saves the external database of a collectors-only installation' do
      with_config_yaml('deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY })

      post commissioning_path,
           params: {
             data: {
               mode: ConfigSchema::MODE_COLLECTORS_ONLY,
               host: 'influx.example.com', schema: 'https', port: '443',
               org: 'acme', bucket: 'solar', token_write: 'secret'
             }.to_json,
           }

      expect(response).to redirect_to(datasources_path)
      expect(Configuration.current.influxdb.host).to eq('influx.example.com')
    end

    it 'refuses a payload that is not JSON' do
      without_config_yaml

      post commissioning_path, params: { data: 'not json' }

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'the gate in front of every other screen' do
    it 'sends a fresh installation to the commissioning screen' do
      without_config_yaml

      get services_path

      expect(response).to redirect_to(commissioning_path)
    end

    # Whatever wrote the configuration, the gate reads the state. So an import
    # that left a gap lands here too, and no screen behind it has to mark one.
    it 'sends an installation that still owes an answer here' do
      with_config_yaml('system' => { 'installation_date' => nil })

      get settings_path

      expect(response).to redirect_to(commissioning_path)
    end

    it 'offers an existing stack for import first' do
      dir = without_config_yaml
      File.write(File.join(dir, 'compose.yaml'),
                 "services:\n  dashboard:\n    image: ghcr.io/solectrus/solectrus:latest\n")
      File.write(File.join(dir, '.env'), "TZ=Europe/Berlin\n")

      get services_path

      expect(response).to redirect_to(start_path)
    end

    it 'lets the login through' do
      without_config_yaml

      get new_session_path

      expect(response).to redirect_to(root_path)
    end
  end
end
