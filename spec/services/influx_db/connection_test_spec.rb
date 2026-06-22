RSpec.describe InfluxDb::ConnectionTest do
  subject(:tester) { described_class.new }

  describe 'reachability check' do
    let(:values) { { 'schema' => 'http', 'host' => 'influxdb.test', 'port' => '8086' } }
    let(:ping_url) { 'http://influxdb.test:8086/ping' }
    let(:influxdb_headers) { { 'X-Influxdb-Version' => '2.7.5' } }

    def reachability(custom = {})
      tester.call(check: 'reachability', values: values.merge(custom))
    end

    it 'reports reachable when /ping responds with an InfluxDB version header' do
      stub_request(:get, ping_url).to_return(status: 204, headers: influxdb_headers)

      expect(reachability).to have_attributes(ok: true, reason: :reachable)
    end

    it 'reports not_influxdb when no InfluxDB version header is present' do
      stub_request(:get, ping_url).to_return(status: 204)

      expect(reachability).to have_attributes(ok: false, reason: :not_influxdb)
    end

    it 'reports not_influxdb on a non-success status' do
      stub_request(:get, ping_url).to_return(status: 404)

      expect(reachability).to have_attributes(ok: false, reason: :not_influxdb)
    end

    it 'reports unreachable when the host cannot be contacted' do
      stub_request(:get, ping_url).to_raise(Errno::ECONNREFUSED)

      expect(reachability).to have_attributes(ok: false, reason: :unreachable)
    end

    it 'reports incomplete when a field is blank, without probing' do
      expect(reachability('host' => '')).to have_attributes(ok: false, reason: :incomplete)
      expect(a_request(:get, ping_url)).not_to have_been_made
    end

    it 'reports an error on an unexpected failure (e.g. TLS handshake)' do
      stub_request(:get, ping_url).to_raise(OpenSSL::SSL::SSLError)

      expect(reachability).to have_attributes(ok: false, reason: :error)
    end

    it 'uses TLS for the https schema' do
      stub = stub_request(:get, 'https://influxdb.test:8443/ping')
             .to_return(status: 204, headers: influxdb_headers)

      reachability('schema' => 'https', 'port' => '8443')

      expect(stub).to have_been_requested
    end
  end

  describe 'credentials check' do
    let(:values) do
      {
        'schema' => 'http', 'host' => 'influxdb.test', 'port' => '8086',
        'org' => 'solectrus', 'bucket' => 'solectrus', 'token_write' => 'tok'
      }
    end

    def credentials(custom = {})
      tester.call(check: 'credentials', values: values.merge(custom))
    end

    def stub_write
      stub_request(:post, 'http://influxdb.test:8086/api/v2/write')
        .with(query: { org: 'solectrus', bucket: 'solectrus' })
    end

    it 'reports valid on a 204 (empty write accepted)' do
      stub_write.to_return(status: 204)

      expect(credentials).to have_attributes(ok: true, reason: :credentials_valid)
    end

    it 'reports valid on a 400 — token and org/bucket are validated before the body' do
      stub_write.to_return(status: 400)

      expect(credentials).to have_attributes(ok: true, reason: :credentials_valid)
    end

    it 'reports unauthorized on a 401' do
      stub_write.to_return(status: 401)

      expect(credentials).to have_attributes(ok: false, reason: :unauthorized)
    end

    it 'reports not_found on a 404' do
      stub_write.to_return(status: 404)

      expect(credentials).to have_attributes(ok: false, reason: :not_found)
    end

    it 'reports unreachable when the host cannot be contacted' do
      stub_write.to_raise(SocketError)

      expect(credentials).to have_attributes(ok: false, reason: :unreachable)
    end

    it 'reports an error on an unexpected server status (e.g. 500)' do
      stub_write.to_return(status: 500)

      expect(credentials).to have_attributes(ok: false, reason: :error)
    end

    it 'reports an error on an unexpected failure (e.g. TLS handshake)' do
      stub_write.to_raise(OpenSSL::SSL::SSLError)

      expect(credentials).to have_attributes(ok: false, reason: :error)
    end

    it 'reports incomplete when the token is blank' do
      expect(credentials('token_write' => '')).to have_attributes(ok: false, reason: :incomplete)
    end

    it 'sends the token as an InfluxDB Authorization header and an empty body' do
      stub = stub_write.with(headers: { 'Authorization' => 'Token tok' }, body: '')
                       .to_return(status: 204)

      credentials

      expect(stub).to have_been_requested
    end
  end

  it 'reports an error for an unknown check' do
    expect(tester.call(check: 'bogus', values: {})).to have_attributes(ok: false, reason: :error)
  end
end
