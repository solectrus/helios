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

    # On the initial (shell) request the body is deferred to a lazy turbo
    # frame so navigation paints instantly; the readings query only runs on
    # the follow-up content-frame request.
    it 'renders a lazy content frame on the shell request and defers the table' do
      Configuration.current.update_sensor('inverter_power', { 'source' => 'senec' })

      get sensors_path

      aggregate_failures do
        expect(response.body).to include('id="configuration-content"')
        expect(response.body).to match(/loading="lazy"/)
        expect(response.body).to match(/src="#{Regexp.escape(sensors_path)}"/)
        expect(response.body).not_to include('inverter_power')
      end
    end

    it 'displays sensor group headers' do
      cookies[:preferences] = { hide_unused: false }.to_json

      get sensors_path, headers: turbo_frame_headers('configuration-content')

      SensorRegistry::GROUPS.each_key do |group|
        title = I18n.t("sensor_groups.#{group}")
        expect(response.body).to include(title)
      end
    end

    it 'displays enabled sensors' do
      config = Configuration.current
      config.update_sensor('inverter_power', { 'source' => 'senec' })

      get sensors_path, headers: turbo_frame_headers('configuration-content')

      expect(response.body).to include('inverter_power')
    end

    it 'shows the services nav tab but no start button when no sensors are configured' do
      get sensors_path

      expect(response.body).to match(/href="#{services_path}"/)
      expect(response.body).not_to match(/fa-solid fa-play/)
    end

    it 'shows the services nav tab and start button once the configuration is complete' do
      Configuration.current.update_sensor('inverter_power', { 'source' => 'senec' })
      Configuration.current.update(:senec, { 'version' => 4 })
      Configuration.current.update('system_general', { 'installation_date' => '2024-01-15' })

      get sensors_path

      expect(response.body).to match(/href="#{services_path}"/)
      expect(response.body).to match(/fa-solid fa-play/)
    end

    it 'hides the compose.yaml/.env file links when no sensors are configured' do
      get sensors_path

      aggregate_failures do
        expect(response.body).not_to include(file_path('compose'))
        expect(response.body).not_to include(file_path('env'))
      end
    end

    it 'shows the compose.yaml/.env file links once a sensor is configured' do
      Configuration.current.update_sensor('inverter_power', { 'source' => 'senec' })

      get sensors_path

      aggregate_failures do
        expect(response.body).to include(file_path('compose'))
        expect(response.body).to include(file_path('env'))
      end
    end

    # The remote read endpoint is often unavailable (write-only Ingest
    # service, reverse proxy without /api/v2, etc.) — skipping the query
    # avoids one 404 per mapping per request.
    it 'does not query InfluxDB in collectors_only mode' do
      with_config_yaml(
        'deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY },
        'influxdb' => { 'host' => 'remote.example', 'port' => '443', 'schema' => 'https',
                        'token' => 't', 'org' => 'o', 'bucket' => 'b' },
        'sensors' => { 'inverter_power' => { 'source' => 'senec' } },
      )

      get sensors_path

      expect(WebMock).not_to have_requested(:post, /remote\.example/)
    end

    # Sensor canonicalization happens on the remote dashboard host in
    # collectors_only mode, so /sensors has no meaning locally.
    it 'redirects to datasources in collectors_only mode' do
      with_config_yaml('deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY })

      get sensors_path

      expect(response).to redirect_to(datasources_path)
    end
  end
end
