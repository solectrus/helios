RSpec.describe 'Datasources::MqttTopics::Readings', :with_admin_password do
  before do
    with_config_yaml(
      'mqtt' => {
        'mqtt_host' => 'broker.local', 'mqtt_port' => '1883',
        'mappings' => [
          { 'topic' => 'home/power', 'measurement' => 'MQTT', 'field' => 'power', 'type' => 'float' },
          # SKIP_WRITE keeps the value in memory only, so there is nothing to query.
          { 'topic' => 'home/aux', 'skip_write' => true },
        ]
      },
      'influxdb' => { 'host' => 'influxdb', 'port' => '8086', 'schema' => 'http',
                      'token_read' => 't', 'org' => 'o', 'bucket' => 'b' },
    )
    login
  end

  describe 'GET /datasources/mqtt-topics/readings' do
    it 'replaces the value cell of every topic that writes to InfluxDB' do
      stub_container_find('influxdb')
      stub_request(:post, 'http://influxdb:8086/api/v2/query?org=o')
        .to_return(status: 200, body: <<~CSV)
          ,result,table,_time,_value,_field,_measurement
          ,_result,0,2026-05-08T10:00:00Z,42.5,power,MQTT
        CSV

      get datasources_mqtt_topics_readings_path, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to have_http_status(:ok)
      # Both cells are replaced, but only the writing one carries a value —
      # a SKIP_WRITE mapping has no InfluxDB target to query.
      expect(response.body).to include('mqtt-topic-value-0', 'mqtt-topic-value-1', '42.50')
      expect(response.body).to include(Reading::EMPTY_DISPLAY)
    end
  end
end
