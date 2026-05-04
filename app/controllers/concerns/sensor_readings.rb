module SensorReadings
  extend ActiveSupport::Concern

  private

  # Skipped in collectors_only mode: there is no local InfluxDB container,
  # the target lives on a remote host. Connection failures degrade gracefully
  # via InfluxDb::Client's CONNECTION_ERRORS rescue, so the gate is unneeded.
  def influxdb_reachable?(configuration)
    return true if configuration.collectors_only?

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
    return {} unless influxdb_reachable?(configuration)
    return {} if mappings.blank?

    InfluxDb::Client.from_configuration(configuration).query_all_latest(mappings)
  rescue InfluxDb::ConnectionError => e
    Rails.logger.warn("InfluxDB query failed: #{e.message}")
    {}
  end
end
