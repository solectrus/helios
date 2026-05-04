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

    it 'hides the services nav tab and start button when no sensors are configured' do
      get sensors_path

      expect(response.body).not_to match(/href="#{services_path}"/)
      expect(response.body).not_to match(/fa-solid fa-play/)
    end

    it 'shows the services nav tab and start button once a sensor is configured' do
      Configuration.current.update_sensor('inverter_power', { 'source' => 'senec' })
      Configuration.current.update(:senec, { 'version' => 4 })

      get sensors_path

      expect(response.body).to match(/href="#{services_path}"/)
      expect(response.body).to match(/fa-solid fa-play/)
    end

    # The remote read endpoint is often unavailable (write-only Ingest
    # service, reverse proxy without /api/v2, etc.) — skipping the query
    # avoids one 404 per mapping per request.
    it 'does not query InfluxDB in collectors_only mode' do
      with_config_yaml(
        'system' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY },
        'influxdb' => { 'host' => 'remote.example', 'port' => '443', 'schema' => 'https',
                        'token' => 't', 'org' => 'o', 'bucket' => 'b' },
        'sensors' => { 'inverter_power' => { 'source' => 'senec' } },
      )

      get sensors_path

      expect(WebMock).not_to have_requested(:post, /remote\.example/)
    end
  end
end
