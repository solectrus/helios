RSpec.describe Senec::ConnectionTest do
  subject(:tester) { described_class.new }

  describe 'reachability check' do
    let(:values) { { 'schema' => 'https', 'host' => 'senec.test' } }
    let(:probe_url) { 'https://senec.test/lala.cgi' }
    let(:senec_body) { { 'ENERGY' => { 'STAT_STATE' => 'u8_03' } }.to_json }

    def reachability(custom = {})
      tester.call(check: 'reachability', values: values.merge(custom))
    end

    it 'reports reachable when /lala.cgi echoes the ENERGY section' do
      stub_request(:post, probe_url).to_return(status: 200, body: senec_body)

      expect(reachability).to have_attributes(ok: true, reason: :senec_reachable)
    end

    it 'reports not_senec when the response is not SENEC-shaped JSON' do
      stub_request(:post, probe_url).to_return(status: 200, body: '{"foo":"bar"}')

      expect(reachability).to have_attributes(ok: false, reason: :senec_not_senec)
    end

    it 'reports not_senec when the response is not JSON' do
      stub_request(:post, probe_url).to_return(status: 200, body: '<html>nope</html>')

      expect(reachability).to have_attributes(ok: false, reason: :senec_not_senec)
    end

    it 'reports not_senec on a non-success status' do
      stub_request(:post, probe_url).to_return(status: 404)

      expect(reachability).to have_attributes(ok: false, reason: :senec_not_senec)
    end

    it 'reports unreachable when the host cannot be contacted' do
      stub_request(:post, probe_url).to_raise(Errno::EHOSTUNREACH)

      expect(reachability).to have_attributes(ok: false, reason: :senec_unreachable)
    end

    it 'reports not_senec when the host resets the connection after connecting' do
      stub_request(:post, probe_url).to_raise(Errno::ECONNRESET)

      expect(reachability).to have_attributes(ok: false, reason: :senec_not_senec)
    end

    it 'reports incomplete when the host is blank, without probing' do
      expect(reachability('host' => '')).to have_attributes(ok: false, reason: :incomplete)
      expect(a_request(:post, probe_url)).not_to have_been_made
    end

    it 'probes the http port for the http schema' do
      stub = stub_request(:post, 'http://senec.test/lala.cgi').to_return(status: 200, body: senec_body)

      reachability('schema' => 'http')

      expect(stub).to have_been_requested
    end

    it 'sends the JSON-RPC probe body' do
      stub = stub_request(:post, probe_url)
             .with(
               body: { 'ENERGY' => { 'STAT_STATE' => '' } }.to_json,
               headers: { 'Content-Type' => 'application/json' },
             )
             .to_return(status: 200, body: senec_body)

      reachability

      expect(stub).to have_been_requested
    end
  end

  it 'reports an error for an unknown check' do
    expect(tester.call(check: 'bogus', values: {})).to have_attributes(ok: false, reason: :error)
  end
end
