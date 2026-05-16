require 'socket'
require 'openssl'

module Mqtt
  # Minimal MQTT 3.1.1 client — just enough to perform a CONNECT/CONNACK
  # handshake for the survey connection test. Not a general-purpose client: it
  # never subscribes, publishes, or holds the connection open.
  class Probe
    CONNECT_PACKET_TYPE = 0x10
    CONNACK_PACKET_TYPE = 0x20
    CONNACK_REMAINING_LENGTH = 2

    # Variable header prefix: protocol name "MQTT" (length-prefixed) followed
    # by protocol level 4 (MQTT 3.1.1).
    PROTOCOL_HEADER = "\x00\x04MQTT\x04".b.freeze

    CLIENT_ID = 'helios-connection-test'.freeze
    KEEP_ALIVE = 10 # seconds

    # Connect flags.
    CLEAN_SESSION = 0x02
    USERNAME_FLAG = 0x80
    PASSWORD_FLAG = 0x40

    OPEN_TIMEOUT = 3 # seconds
    READ_TIMEOUT = 5 # seconds

    # Raised when the peer answers, but not with a well-formed CONNACK — e.g.
    # an HTTP server listening on the probed port.
    class NotABroker < StandardError
    end

    # Raised when the broker closes the connection during the handshake
    # without sending a CONNACK. After authentication fails, many brokers do
    # exactly this instead of replying with a rejection return code.
    class ConnectionClosed < StandardError
    end

    # Failures that mean the broker itself could not be contacted.
    CONNECTION_ERRORS = [
      SocketError,
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::EHOSTUNREACH,
      Errno::ENETUNREACH,
      Errno::ETIMEDOUT,
      Errno::EPIPE,
      IO::TimeoutError,
      OpenSSL::SSL::SSLError,
      EOFError,
    ].freeze

    def initialize(host:, port:, ssl:)
      @host = host
      @port = port.to_i
      @ssl = ssl
    end

    # True when a connection to the broker can be established. The reachability
    # check runs before any credentials are entered, so it cannot perform a
    # full MQTT handshake — it only confirms the host accepts connections on
    # the MQTT port (including the TLS handshake when SSL is enabled).
    def reachable?
      socket = open_socket
      true
    rescue *CONNECTION_ERRORS
      false
    ensure
      socket&.close
    end

    # Performs the handshake and returns the CONNACK return code (0 = accepted,
    # 4 = bad username/password, 5 = not authorized, …). Raises NotABroker when
    # the reply is not a CONNACK packet, or ConnectionClosed when the broker
    # drops the connection mid-handshake.
    def connect(username: nil, password: nil)
      socket = open_socket
      socket.write(connect_packet(username, password))
      read_return_code(socket)
    ensure
      socket&.close
    end

    private

    attr_reader :host, :port, :ssl

    def open_socket
      tcp = Socket.tcp(host, port, connect_timeout: OPEN_TIMEOUT)
      tcp.timeout = READ_TIMEOUT
      ssl ? ssl_socket(tcp) : tcp
    end

    # The broker may use a self-signed certificate; the connection test only
    # cares about reachability and credentials, not certificate trust.
    def ssl_socket(tcp)
      context = OpenSSL::SSL::SSLContext.new
      context.verify_mode = OpenSSL::SSL::VERIFY_NONE

      OpenSSL::SSL::SSLSocket.new(tcp, context).tap do |ssl_socket|
        ssl_socket.sync_close = true
        ssl_socket.hostname = host # SNI
        ssl_socket.connect
      end
    end

    def connect_packet(username, password)
      flags = CLEAN_SESSION
      payload = +encode_string(CLIENT_ID)

      if username.present?
        flags |= USERNAME_FLAG
        payload << encode_string(username)

        if password.present?
          flags |= PASSWORD_FLAG
          payload << encode_string(password)
        end
      end

      variable_header = PROTOCOL_HEADER + [flags].pack('C') + [KEEP_ALIVE].pack('n')
      body = variable_header + payload

      [CONNECT_PACKET_TYPE].pack('C') + encode_remaining_length(body.bytesize) + body
    end

    # MQTT length-prefixed UTF-8 string: a 16-bit big-endian length, then the
    # bytes.
    def encode_string(string)
      bytes = string.to_s.b
      [bytes.bytesize].pack('n') + bytes
    end

    # MQTT "remaining length" variable-byte integer. The probe's CONNECT
    # packet stays small, but encode it properly so longer credentials work.
    def encode_remaining_length(length)
      bytes = +''.b
      loop do
        digit = length & 0x7F
        length >>= 7
        digit |= 0x80 if length.positive?
        bytes << digit
        break unless length.positive?
      end
      bytes
    end

    def read_return_code(socket)
      header = read_bytes(socket, 2)
      unless header.getbyte(0) == CONNACK_PACKET_TYPE && header.getbyte(1) == CONNACK_REMAINING_LENGTH
        raise NotABroker
      end

      # CONNACK body: acknowledge flags, then the connect return code.
      read_bytes(socket, 2).getbyte(1)
    end

    # Reads exactly `count` bytes. A short read means the broker closed the
    # connection before completing the CONNACK — a rejected login, not a
    # missing broker.
    def read_bytes(socket, count)
      data = socket.read(count)
      raise ConnectionClosed if data.nil? || data.bytesize < count

      data
    end
  end
end
