module SensorReadings
  extend ActiveSupport::Concern

  private

  def influxdb_running?
    Orchestration::Container.find('influxdb')&.running? || false
  rescue Orchestration::ConnectionError
    false
  end

  def fetch_readings(configuration:)
    sensor_mappings = configuration.effective_sensor_mappings
    return {} unless influxdb_running?
    return {} if sensor_mappings.blank?

    InfluxDb::Client.from_configuration(configuration).query_all_latest(sensor_mappings)
  rescue InfluxDb::ConnectionError => e
    Rails.logger.warn("InfluxDB query failed: #{e.message}")
    {}
  end
end
