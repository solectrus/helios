module SensorReadings
  extend ActiveSupport::Concern

  private

  # In collectors_only mode the configured target is whatever the user
  # points the collectors at — often a write-only Ingest service, sometimes
  # a reverse proxy that exposes only /api/v1, occasionally a reachable
  # InfluxDB. We have no way to tell from outside, and an unreachable read
  # endpoint produces one 404 per mapping per request. Skip polling
  # entirely; values live in the remote dashboard.
  # In full mode we still gate on the local InfluxDB container so a stopped
  # DB does not produce a flood of connection errors.
  def readings_available?(configuration)
    return false if configuration.collectors_only?

    Orchestration::Container.find('influxdb')&.running? || false
  rescue Orchestration::ConnectionError
    false
  end

  def fetch_readings(configuration:)
    fetch_readings_for(configuration.effective_sensor_mappings, configuration:)
  end

  def fetch_topic_readings(configuration:)
    mappings = configuration.mqtt_topics.each_with_index.to_h do |topic, index|
      [index.to_s, "#{topic['measurement']}:#{topic['field']}"]
    end
    fetch_readings_for(mappings, configuration:)
  end

  def fetch_readings_for(mappings, configuration:)
    return {} unless readings_available?(configuration)
    return {} if mappings.blank?

    InfluxDb::Client.from_configuration(configuration).query_all_latest(mappings)
  rescue InfluxDb::ConnectionError => e
    Rails.logger.warn("InfluxDB query failed: #{e.message}")
    {}
  end
end
