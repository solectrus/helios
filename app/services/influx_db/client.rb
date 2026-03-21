require 'net/http'
require 'uri'

module InfluxDb
  class Client
    TIMEOUT = 10

    def initialize(token:, org:, bucket:, host: nil, port: 8086)
      @token = token
      @org = org
      @bucket = bucket
      @host = host || ENV.fetch('INFLUX_HOST', default_host)
      @port = port
    end

    def self.from_configuration(configuration = Configuration.current)
      influx = configuration.influxdb

      new(
        token: influx.token,
        org: influx.org,
        bucket: influx.bucket,
      )
    end

    # Fast query: only latest value per sensor (for polling)
    def query_all_latest(sensor_mappings)
      each_sensor(sensor_mappings) { |m, f| query_latest(m, f) }
    end

    private

    attr_reader :token, :org, :bucket, :host, :port

    def each_sensor(sensor_mappings)
      sensor_mappings.each_with_object({}) do |(sensor_name, mapping), results|
        measurement, field = mapping.split(':', 2)
        next if measurement.blank? || field.blank?

        results[sensor_name] = yield(measurement, field)
      end
    end

    def query_latest(measurement, field)
      rows = execute_query(flux_latest_query(measurement, field))
      return nil if rows.empty?

      row = rows.first
      { value: parse_value(row['_value']), time: Time.zone.parse(row['_time']) }
    rescue StandardError => e
      Rails.logger.warn("InfluxDB query failed for #{measurement}:#{field}: #{e.message}")
      nil
    end

    def flux_latest_query(measurement, field)
      <<~FLUX
        from(bucket: "#{bucket}")
          |> range(start: -24h)
          |> filter(fn: (r) => r._measurement == "#{measurement}" and r._field == "#{field}")
          |> last()
      FLUX
    end

    def execute_query(flux)
      response = perform_request(flux)

      unless response.is_a?(Net::HTTPSuccess)
        raise InfluxDb::ConnectionError, "InfluxDB returned #{response.code}: #{response.body}"
      end

      parse_csv(response.body)
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Net::OpenTimeout, Net::ReadTimeout => e
      raise InfluxDb::ConnectionError, "Cannot connect to InfluxDB: #{e.message}"
    end

    def perform_request(flux)
      uri = query_uri
      request = build_request(uri, flux)

      Net::HTTP.start(uri.hostname, uri.port, read_timeout: TIMEOUT, open_timeout: TIMEOUT) do |http|
        http.request(request)
      end
    end

    def query_uri
      URI("http://#{host}:#{port}/api/v2/query").tap do |uri|
        uri.query = URI.encode_www_form(org:)
      end
    end

    def build_request(uri, flux)
      Net::HTTP::Post.new(uri).tap do |req|
        req['Authorization'] = "Token #{token}"
        req['Content-Type'] = 'application/vnd.flux'
        req.body = flux
      end
    end

    def parse_csv(body)
      return [] if body.blank?

      lines = body.lines.map(&:strip).reject { |l| l.empty? || l.start_with?('#') }
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
