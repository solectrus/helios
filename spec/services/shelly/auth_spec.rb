require 'base64'

RSpec.describe Shelly::Auth do
  describe '.authorization' do
    it 'builds a Basic header for a Basic challenge' do
      header = described_class.authorization(
        challenge: 'Basic realm="shelly"', http_method: 'GET', uri: '/status', password: 'secret',
      )

      expect(header).to start_with('Basic ')
      expect(Base64.decode64(header.delete_prefix('Basic '))).to eq('admin:secret')
    end

    it 'builds a SHA-256 Digest header for a Digest challenge' do
      challenge = 'Digest qop="auth", realm="shellyplus1pm-abc", nonce="deadbeef", algorithm=SHA-256'

      header = described_class.authorization(
        challenge:, http_method: 'GET', uri: '/rpc/Shelly.GetStatus', password: 'secret',
      )

      expect(header).to start_with('Digest ')
      expect(header).to include(
        'username="admin"', 'realm="shellyplus1pm-abc"', 'nonce="deadbeef"',
        'uri="/rpc/Shelly.GetStatus"', 'qop=auth', 'algorithm=SHA-256'
      )
      expect(header).to match(/response="[0-9a-f]{64}"/)
    end

    it 'returns nil for an unsupported scheme' do
      expect(
        described_class.authorization(challenge: 'Bearer xyz', http_method: 'GET', uri: '/x', password: 'p'),
      ).to be_nil
    end

    it 'returns nil for a malformed Digest challenge missing realm and nonce' do
      expect(
        described_class.authorization(
          challenge: 'Digest algorithm=SHA-256', http_method: 'GET', uri: '/x', password: 'p',
        ),
      ).to be_nil
    end
  end
end
