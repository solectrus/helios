RSpec.describe 'Sensors::Readings', :with_admin_password do
  subject(:poll) { get sensors_readings_path, headers: { 'Accept' => 'text/vnd.turbo-stream.html' } }

  before do
    with_config_yaml('sensors' => { 'inverter_power' => { 'source' => 'senec' } },
                     'influxdb' => { 'host' => 'influxdb', 'port' => '8086', 'schema' => 'http',
                                     'token_read' => 't', 'org' => 'o', 'bucket' => 'b' })
    login
  end

  describe 'GET /sensors/readings' do
    # The polling controller asks for a turbo stream and morphs each value
    # cell in place, so the row keeps its DOM and no scroll position is lost.
    it 'replaces every sensor value cell with the latest reading' do
      stub_container_find('influxdb')
      stub_request(:post, 'http://influxdb:8086/api/v2/query?org=o')
        .to_return(status: 200, body: <<~CSV)
          ,result,table,_time,_value,_field,_measurement
          ,_result,0,2026-05-08T10:00:00Z,1234.5,inverter_power,SENEC
        CSV

      poll

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('sensor-value-inverter_power', 'method="morph"', '1234.5')
    end

    # Nothing upstream is worth an error page: the cells stay empty until the
    # next poll finds InfluxDB again.
    it 'renders empty cells while InfluxDB is down, without querying it' do
      stub_container_find('influxdb', running: nil)

      poll

      expect(response).to have_http_status(:ok)
      expect(WebMock).not_to have_requested(:post, /influxdb:8086/)
    end

    it 'renders empty cells when Docker cannot be reached' do
      allow(Orchestration::Container).to receive(:find)
        .with('influxdb').and_raise(Orchestration::ConnectionError, 'no socket')

      poll

      expect(response).to have_http_status(:ok)
      expect(WebMock).not_to have_requested(:post, /influxdb:8086/)
    end

    it 'renders empty cells when the InfluxDB query itself fails' do
      stub_container_find('influxdb')
      allow(InfluxDb::Client).to receive(:from_configuration)
        .and_raise(InfluxDb::ConnectionError, 'connection refused')

      poll

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('1234.5')
    end
  end
end
