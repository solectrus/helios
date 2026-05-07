require 'net/http'
require 'uri'

module InfluxDb
  class Client
    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 10

    # Connection-level errors abort the whole batch — once name resolution
    # or TCP connect fails, retrying for every remaining sensor only stacks
    # up timeouts (with ~25 sensors, that turns a 2s outage into 30s+ per
    # poll). Per-query failures (HTTP 5xx, parse errors) are rescued below
    # and degrade just that one sensor.
    CONNECTION_ERRORS = [
      SocketError,
      Errno::ECONNREFUSED,
      Errno::EHOSTUNREACH,
      Errno::ENETUNREACH,
      Errno::ETIMEDOUT,
      Net::OpenTimeout,
      Net::ReadTimeout,
    ].freeze

    def initialize(token:, org:, bucket:, host: nil, port: nil, schema: nil) # rubocop:disable Metrics/ParameterLists
      @token = token
      @org = org
      @bucket = bucket
      @host = host.presence || ENV.fetch('INFLUX_HOST', default_host)
      @port = (port.presence || ENV.fetch('INFLUX_PORT', 8086)).to_i
      @schema = (schema.presence || ENV.fetch('INFLUX_SCHEMA', 'http')).to_s
    end

    # config.yaml is the single source of truth: host/port/schema are read
    # straight from the `influxdb` section so credential or URL edits take
    # effect immediately, without recreating the HELIOS container. In full
    # mode the section has no host/port/schema and the constructor falls
    # back to the in-stack defaults (container name `influxdb` on http:8086).
    def self.from_configuration(configuration = Configuration.current)
      influx = configuration.influxdb

      new(
        token: influx.token_read,
        org: influx.org,
        bucket: influx.bucket,
        host: influx.host,
        port: influx.port,
        schema: influx.schema,
      )
    end

    # Fast query: only latest value per sensor (for polling)
    def query_all_latest(sensor_mappings)
      return {} if sensor_mappings.blank?

      with_http do |http|
        each_sensor(sensor_mappings) { |m, f| query_latest(http, m, f) }
      end
    end

    private

    attr_reader :token, :org, :bucket, :host, :port, :schema

    # One Net::HTTP session is reused across the whole batch: saves N-1 DNS
    # lookups and TCP handshakes per poll, and turns an outage into a single
    # fast-fail instead of N timeouts back-to-back.
    def with_http(&)
      Net::HTTP.start(
        host, port,
        use_ssl: schema == 'https',
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT,
        &
      )
    rescue *CONNECTION_ERRORS => e
      Rails.logger.warn("InfluxDB unreachable at #{schema}://#{host}:#{port}: #{e.message}")
      {}
    end

    def each_sensor(sensor_mappings)
      sensor_mappings.each_with_object({}) do |(sensor_name, mapping), results|
        measurement, field = mapping.split(':', 2)
        next if measurement.blank? || field.blank?

        results[sensor_name] = yield(measurement, field)
      end
    end

    def query_latest(http, measurement, field)
      rows = execute_query(http, flux_latest_query(measurement, field))
      return nil if rows.empty?

      row = rows.first
      Reading.new(value: parse_value(row['_value']), time: Time.zone.parse(row['_time']))
    rescue *CONNECTION_ERRORS
      raise
    rescue StandardError => e
      Rails.logger.warn("InfluxDB query failed for #{measurement}:#{field}: #{e.message}")
      nil
    end

    def execute_query(http, flux)
      response = http.request(build_request(flux))
      raise InfluxDb::ConnectionError, "InfluxDB returned #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      parse_csv(response.body)
    end

    def build_request(flux)
      Net::HTTP::Post.new(query_uri).tap do |req|
        req['Authorization'] = "Token #{token}"
        req['Content-Type'] = 'application/vnd.flux'
        req.body = flux
      end
    end

    def query_uri
      URI("#{schema}://#{host}:#{port}/api/v2/query").tap do |uri|
        uri.query = URI.encode_www_form(org:)
      end
    end

    def flux_latest_query(measurement, field)
      <<~FLUX
        from(bucket: "#{bucket}")
          |> range(start: -24h, stop: 1h)
          |> filter(fn: (r) => r._measurement == "#{measurement}" and r._field == "#{field}")
          |> last()
      FLUX
    end

    def parse_csv(body)
      return [] if body.blank?

      # Net::HTTP returns ASCII-8BIT; InfluxDB sends UTF-8. `scrub` guards
      # against malformed bytes so a bad response cannot crash ERB rendering.
      utf8_body = body.dup.force_encoding(Encoding::UTF_8).scrub
      lines = utf8_body.lines.map(&:strip).reject { |l| l.empty? || l.start_with?('#') }
      return [] if lines.size < 2

      headers = lines.first.split(',')
      lines[1..].map { |line| headers.zip(line.split(',', -1)).to_h }
    end

    def default_host
      Rails.env.local? ? 'localhost' : 'influxdb'
    end

    def parse_value(value)
      return nil if value.blank?

      Float(value)
    rescue ArgumentError, TypeError
      value
    end
  end
end
