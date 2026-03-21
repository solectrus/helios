module SensorReadings
  extend ActiveSupport::Concern

  private

  def influxdb_running?
    Orchestration::Container.find('influxdb')&.running? || false
  rescue Orchestration::ConnectionError
    false
  end

  def fetch_readings(configuration:, with_stats: false)
    return {} unless @influxdb_running
    return {} if @sensor_mappings.blank?

    client = InfluxDb::Client.from_configuration(configuration)
    if with_stats
      client.query_all_with_stats(@sensor_mappings)
    else
      client.query_all_latest(@sensor_mappings)
    end
  rescue InfluxDb::ConnectionError => e
    Rails.logger.warn("InfluxDB query failed: #{e.message}")
    @influxdb_error = e.message
    {}
  end
end
