RSpec.describe 'Configurations::ConnectionTests', :with_admin_password do
  before do
    with_config_yaml
    login
  end

  describe 'POST /configuration/connection_test' do
    it 'reports a reachable InfluxDB' do
      stub_request(:get, 'http://influxdb.test:8086/ping')
        .to_return(status: 204, headers: { 'X-Influxdb-Version' => '2.7.5' })

      post configuration_connection_test_path, params: {
        target: 'influxdb', check: 'reachability',
        values: { schema: 'http', host: 'influxdb.test', port: '8086' }
      }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['ok']).to be true
      expect(response.parsed_body['message']).to be_present
    end

    it 'reports an unreachable InfluxDB' do
      stub_request(:get, 'http://nope.test:8086/ping').to_raise(Errno::ECONNREFUSED)

      post configuration_connection_test_path, params: {
        target: 'influxdb', check: 'reachability',
        values: { schema: 'http', host: 'nope.test', port: '8086' }
      }

      expect(response.parsed_body['ok']).to be false
    end

    it 'validates credentials with an empty write probe' do
      stub_request(:post, 'http://influxdb.test:8086/api/v2/write')
        .with(query: { org: 'solectrus', bucket: 'solectrus' })
        .to_return(status: 204)

      post configuration_connection_test_path, params: {
        target: 'influxdb', check: 'credentials',
        values: {
          schema: 'http', host: 'influxdb.test', port: '8086',
          org: 'solectrus', bucket: 'solectrus', token_write: 'tok'
        }
      }

      expect(response.parsed_body['ok']).to be true
    end

    it 'reports invalid credentials on a 401' do
      stub_request(:post, 'http://influxdb.test:8086/api/v2/write')
        .with(query: { org: 'solectrus', bucket: 'solectrus' })
        .to_return(status: 401)

      post configuration_connection_test_path, params: {
        target: 'influxdb', check: 'credentials',
        values: {
          schema: 'http', host: 'influxdb.test', port: '8086',
          org: 'solectrus', bucket: 'solectrus', token_write: 'bad'
        }
      }

      expect(response.parsed_body['ok']).to be false
    end

    it 'reports a reachable SENEC device' do
      stub_request(:post, 'https://senec.test/lala.cgi')
        .to_return(status: 200, body: { 'ENERGY' => { 'STAT_STATE' => 'u8_03' } }.to_json)

      post configuration_connection_test_path, params: {
        target: 'senec', check: 'reachability',
        values: { schema: 'https', host: 'senec.test' }
      }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['ok']).to be true
      expect(response.parsed_body['message']).to be_present
    end

    it 'reports a reachable Shelly device' do
      stub_request(:get, 'http://shelly.test/shelly')
        .to_return(status: 200, body: { 'mac' => 'AABBCCDDEEFF' }.to_json)

      post configuration_connection_test_path, params: {
        target: 'shelly', check: 'reachability',
        values: { host: 'shelly.test' }
      }

      expect(response.parsed_body['ok']).to be true
      expect(response.parsed_body['message']).to be_present
    end

    it 'reports a reachable Shelly Cloud' do
      stub_request(:post, 'https://shelly-99-eu.shelly.cloud/v2/devices/api/get')
        .with(query: { auth_key: 'cloud-key' })
        .to_return(status: 200, body: '[]')

      post configuration_connection_test_path, params: {
        target: 'shelly', check: 'cloud',
        values: { cloud_server: 'https://shelly-99-eu.shelly.cloud', auth_key: 'cloud-key' }
      }

      expect(response.parsed_body['ok']).to be true
      expect(response.parsed_body['message']).to be_present
    end

    it 'reports an error for an unknown target without probing' do
      post configuration_connection_test_path, params: {
        target: 'spaceship', check: 'reachability', values: { host: 'x' }
      }

      expect(response.parsed_body['ok']).to be false
      expect(response.parsed_body['message']).to be_present
    end
  end
end
