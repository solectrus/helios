require 'base64'
require 'digest'
require 'securerandom'

module Shelly
  # Builds the HTTP `Authorization` header for a Shelly device's auth
  # challenge. Gen2+ devices answer with Digest (SHA-256, qop=auth), Gen1
  # devices with Basic. The username is always `admin`. This mirrors the
  # auth handling in solectrus/shelly-collector.
  module Auth
    USERNAME = 'admin'.freeze

    # Digest header fields that carry a quoted value (the rest are bare).
    DIGEST_QUOTED_FIELDS = %i[username realm nonce uri cnonce response].freeze

    # Returns the Authorization header value for the given WWW-Authenticate
    # challenge, or nil when the scheme is unsupported or the challenge is
    # malformed.
    def self.authorization(challenge:, http_method:, uri:, password:)
      case challenge
      when /\ABasic/i then basic(password)
      when /\ADigest/i then digest(challenge, http_method, uri, password)
      end
    end

    def self.basic(password)
      "Basic #{Base64.strict_encode64("#{USERNAME}:#{password}")}"
    end

    def self.digest(challenge, http_method, uri, password)
      params = challenge.scan(/(\w+)="?([^",]+)"?/).to_h
      return if params['realm'].blank? || params['nonce'].blank?

      fields = digest_fields(params, http_method, uri, password)
      "Digest #{fields.map { |key, value| digest_field(key, value) }.join(', ')}"
    end

    def self.digest_fields(params, http_method, uri, password)
      nc = '00000001' # single request, so the nonce count never advances
      cnonce = SecureRandom.hex(8)
      qop = params['qop'] || 'auth'

      ha1 = Digest::SHA256.hexdigest("#{USERNAME}:#{params['realm']}:#{password}")
      ha2 = Digest::SHA256.hexdigest("#{http_method}:#{uri}")
      response = Digest::SHA256.hexdigest("#{ha1}:#{params['nonce']}:#{nc}:#{cnonce}:#{qop}:#{ha2}")

      {
        username: USERNAME, realm: params['realm'], nonce: params['nonce'], uri:,
        qop:, nc:, cnonce:, response:, algorithm: 'SHA-256'
      }
    end

    def self.digest_field(key, value)
      DIGEST_QUOTED_FIELDS.include?(key) ? %(#{key}="#{value}") : "#{key}=#{value}"
    end
  end
end
