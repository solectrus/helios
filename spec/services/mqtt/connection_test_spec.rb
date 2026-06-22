require 'socket'

RSpec.describe Mqtt::ConnectionTest do
  subject(:tester) { described_class.new }

  # Tiny in-process MQTT broker: accepts one connection, reads the CONNECT
  # packet, and replies with a CONNACK carrying `return_code`. `raw_reply`
  # sends an arbitrary byte string instead — used to fake a non-broker. The
  # captured CONNECT bytes are yielded for assertions.
  def with_fake_broker(return_code: 0, raw_reply: nil)
    server = TCPServer.new('127.0.0.1', 0)
    captured = []
    thread = Thread.new do # rubocop:disable ThreadSafety/NewThread
      client = server.accept
      captured << client.readpartial(1024)
      client.write(raw_reply || [0x20, 0x02, 0x00, return_code].pack('C*'))
      client.close
    rescue IOError, Errno::ECONNRESET, Errno::EPIPE
      nil
    end
    yield(server.addr[1], captured)
  ensure
    thread&.join(2)
    server&.close
  end

  # A plain TCP listener that accepts connections and closes them again — just
  # enough for the reachability check, which performs no MQTT handshake.
  def with_listening_port
    server = TCPServer.new('127.0.0.1', 0)
    thread = Thread.new do # rubocop:disable ThreadSafety/NewThread
      loop { server.accept.close }
    rescue IOError, Errno::ECONNRESET, Errno::EPIPE
      nil
    end
    yield(server.addr[1])
  ensure
    thread&.kill
    server&.close
  end

  # An ephemeral port that nothing listens on (the server is closed again
  # right away), so a connection attempt is refused.
  def free_port
    server = TCPServer.new('127.0.0.1', 0)
    server.addr[1].tap { server.close }
  end

  describe 'reachability check' do
    def reachability(port)
      tester.call(
        check: 'reachability',
        values: { 'mqtt_host' => '127.0.0.1', 'mqtt_port' => port.to_s },
      )
    end

    it 'reports reachable when the host accepts a connection' do
      with_listening_port do |port|
        expect(reachability(port)).to have_attributes(ok: true, reason: :mqtt_reachable)
      end
    end

    it 'reports unreachable when nothing listens on the port' do
      expect(reachability(free_port)).to have_attributes(ok: false, reason: :mqtt_unreachable)
    end

    it 'reports incomplete when the host is blank' do
      expect(tester.call(check: 'reachability', values: { 'mqtt_host' => '' }))
        .to have_attributes(ok: false, reason: :incomplete)
    end
  end

  describe 'credentials check' do
    def credentials(port, custom = {})
      tester.call(check: 'credentials', values: {
        'mqtt_host' => '127.0.0.1', 'mqtt_port' => port.to_s,
        'mqtt_username' => 'collector', 'mqtt_password' => 's3cret'
      }.merge(custom))
    end

    it 'reports valid when the broker accepts the credentials' do
      with_fake_broker(return_code: 0) do |port|
        expect(credentials(port)).to have_attributes(ok: true, reason: :mqtt_credentials_valid)
      end
    end

    it 'reports unauthorized on return code 4 (bad username/password)' do
      with_fake_broker(return_code: 4) do |port|
        expect(credentials(port)).to have_attributes(ok: false, reason: :mqtt_unauthorized)
      end
    end

    it 'reports unauthorized on return code 5 (not authorized)' do
      with_fake_broker(return_code: 5) do |port|
        expect(credentials(port)).to have_attributes(ok: false, reason: :mqtt_unauthorized)
      end
    end

    it 'reports unauthorized when the broker closes the connection without a CONNACK' do
      with_fake_broker(raw_reply: '') do |port|
        expect(credentials(port)).to have_attributes(ok: false, reason: :mqtt_unauthorized)
      end
    end

    it 'reports not_broker when the reply is not a CONNACK at all' do
      with_fake_broker(raw_reply: "HTTP/1.1 200 OK\r\n\r\n") do |port|
        expect(credentials(port)).to have_attributes(ok: false, reason: :mqtt_not_broker)
      end
    end

    it 'reports an error on an unexpected CONNACK return code' do
      with_fake_broker(return_code: 2) do |port|
        expect(credentials(port)).to have_attributes(ok: false, reason: :error)
      end
    end

    it 'reports unreachable when the broker connection is refused' do
      expect(credentials(free_port)).to have_attributes(ok: false, reason: :mqtt_unreachable)
    end

    it 'reports incomplete when the username is blank, without connecting' do
      result = tester.call(check: 'credentials', values: {
                             'mqtt_host' => '127.0.0.1', 'mqtt_port' => '1883', 'mqtt_username' => ''
                           })

      expect(result).to have_attributes(ok: false, reason: :incomplete)
    end

    it 'sends the username and password in the CONNECT packet' do
      with_fake_broker do |port, captured|
        credentials(port)

        expect(captured.first).to include('collector').and include('s3cret')
      end
    end
  end

  it 'reports an error for an unknown check' do
    expect(tester.call(check: 'bogus', values: {})).to have_attributes(ok: false, reason: :error)
  end
end
