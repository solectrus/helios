RSpec.describe Shelly::ConnectionTest do
  subject(:tester) { described_class.new }

  describe 'reachability check' do
    let(:shelly_url) { 'http://shelly.test/shelly' }

    def reachability(values = {})
      tester.call(check: 'reachability', values: { 'host' => 'shelly.test' }.merge(values))
    end

    context 'without authentication' do
      it 'reports reachable when /shelly returns device info with a MAC' do
        stub_request(:get, shelly_url)
          .to_return(status: 200, body: { 'mac' => 'AABBCCDDEEFF', 'gen' => 2, 'auth_en' => false }.to_json)

        expect(reachability).to have_attributes(ok: true, reason: :shelly_reachable)
      end

      it 'reports not_shelly when the JSON lacks a MAC' do
        stub_request(:get, shelly_url).to_return(status: 200, body: '{"foo":"bar"}')

        expect(reachability).to have_attributes(ok: false, reason: :shelly_not_shelly)
      end

      it 'reports not_shelly when the response is not JSON' do
        stub_request(:get, shelly_url).to_return(status: 200, body: 'not json')

        expect(reachability).to have_attributes(ok: false, reason: :shelly_not_shelly)
      end

      it 'reports not_shelly on a non-success status' do
        stub_request(:get, shelly_url).to_return(status: 500)

        expect(reachability).to have_attributes(ok: false, reason: :shelly_not_shelly)
      end

      it 'reports unreachable when the host cannot be contacted' do
        stub_request(:get, shelly_url).to_raise(SocketError)

        expect(reachability).to have_attributes(ok: false, reason: :shelly_unreachable)
      end

      it 'reports not_shelly when the host resets the connection after connecting' do
        stub_request(:get, shelly_url).to_raise(Errno::ECONNRESET)

        expect(reachability).to have_attributes(ok: false, reason: :shelly_not_shelly)
      end

      it 'reports incomplete when the host is blank, without probing' do
        expect(tester.call(check: 'reachability', values: { 'host' => '' }))
          .to have_attributes(ok: false, reason: :incomplete)
        expect(a_request(:get, shelly_url)).not_to have_been_made
      end
    end

    context 'with a password-protected Gen2+ device (Digest auth)' do
      let(:status_url) { 'http://shelly.test/rpc/Shelly.GetStatus' }
      let(:digest_challenge) do
        'Digest qop="auth", realm="shellyplus1pm-abc", nonce="0011223344", algorithm=SHA-256'
      end

      before do
        stub_request(:get, shelly_url)
          .to_return(status: 200, body: { 'mac' => 'AABBCCDDEEFF', 'gen' => 2, 'auth_en' => true }.to_json)
      end

      def stub_challenge
        stub_request(:get, status_url)
          .with { |request| !request.headers.key?('Authorization') }
          .to_return(status: 401, headers: { 'WWW-Authenticate' => digest_challenge })
      end

      def stub_authenticated(status:)
        stub_request(:get, status_url)
          .with(headers: { 'Authorization' => /\ADigest / })
          .to_return(status:, body: '{}')
      end

      it 'reports password_required when no password is given, without probing the status endpoint' do
        expect(reachability).to have_attributes(ok: false, reason: :shelly_password_required)
        expect(a_request(:get, status_url)).not_to have_been_made
      end

      it 'reports reachable when the password is accepted' do
        stub_challenge
        stub_authenticated(status: 200)

        expect(reachability('password' => 'secret')).to have_attributes(ok: true, reason: :shelly_reachable)
      end

      it 'reports unauthorized when the password is rejected' do
        stub_challenge
        stub_authenticated(status: 401)

        expect(reachability('password' => 'wrong')).to have_attributes(ok: false, reason: :shelly_unauthorized)
      end
    end

    context 'with a password-protected Gen1 device (Basic auth)' do
      let(:status_url) { 'http://shelly.test/status' }

      before do
        stub_request(:get, shelly_url)
          .to_return(status: 200, body: { 'mac' => 'AABBCCDDEEFF', 'auth' => true }.to_json)
      end

      it 'authenticates with Basic auth and reports reachable' do
        stub_request(:get, status_url)
          .with { |request| !request.headers.key?('Authorization') }
          .to_return(status: 401, headers: { 'WWW-Authenticate' => 'Basic realm="shelly"' })
        stub_request(:get, status_url)
          .with(headers: { 'Authorization' => /\ABasic / })
          .to_return(status: 200, body: '{}')

        expect(reachability('password' => 'secret')).to have_attributes(ok: true, reason: :shelly_reachable)
      end
    end
  end

  describe 'cloud check' do
    let(:server) { 'https://shelly-42-eu.shelly.cloud' }
    let(:cloud_url) { "#{server}/v2/devices/api/get" }

    def cloud(values = {})
      tester.call(check: 'cloud', values: { 'cloud_server' => server, 'auth_key' => 'key-123' }.merge(values))
    end

    def stub_cloud
      stub_request(:post, cloud_url).with(query: { auth_key: 'key-123' })
    end

    it 'reports reachable when the cloud accepts the request' do
      stub_cloud.to_return(status: 200, body: '[]')

      expect(cloud).to have_attributes(ok: true, reason: :shelly_cloud_reachable)
    end

    it 'reports reachable on a 400 — the auth key is validated before the body' do
      stub_cloud.to_return(status: 400)

      expect(cloud).to have_attributes(ok: true, reason: :shelly_cloud_reachable)
    end

    it 'reports unauthorized on a 401' do
      stub_cloud.to_return(status: 401)

      expect(cloud).to have_attributes(ok: false, reason: :shelly_cloud_unauthorized)
    end

    it 'reports unreachable on a 404 (wrong server URL)' do
      stub_cloud.to_return(status: 404)

      expect(cloud).to have_attributes(ok: false, reason: :shelly_cloud_unreachable)
    end

    it 'reports unreachable when the server cannot be contacted' do
      stub_cloud.to_raise(SocketError)

      expect(cloud).to have_attributes(ok: false, reason: :shelly_cloud_unreachable)
    end

    it 'reports incomplete when the auth key is blank, without probing' do
      expect(cloud('auth_key' => '')).to have_attributes(ok: false, reason: :incomplete)
      expect(a_request(:post, cloud_url)).not_to have_been_made
    end

    it 'sends the auth key as a query param and an empty ids probe body' do
      stub = stub_request(:post, cloud_url)
             .with(query: { auth_key: 'key-123' }, body: { ids: [], select: ['status'] }.to_json)
             .to_return(status: 200, body: '[]')

      cloud

      expect(stub).to have_been_requested
    end

    it 'defaults to https when the server URL has no scheme' do
      stub = stub_request(:post, 'https://shelly-42-eu.shelly.cloud/v2/devices/api/get')
             .with(query: { auth_key: 'key-123' }).to_return(status: 200, body: '[]')

      cloud('cloud_server' => 'shelly-42-eu.shelly.cloud')

      expect(stub).to have_been_requested
    end
  end

  it 'reports an error for an unknown check' do
    expect(tester.call(check: 'bogus', values: {})).to have_attributes(ok: false, reason: :error)
  end
end
