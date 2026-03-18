module SensorTable
  class Component < ViewComponent::Base
    DURATION_THRESHOLDS = [
      [60, :seconds],
      [3_600, :minutes, 60],
      [86_400, :hours, 3_600],
      [30 * 86_400, :days, 86_400],
      [365 * 86_400, :months, 30 * 86_400],
    ].freeze

    attr_reader :sensor_mappings, :device_names, :readings, :influxdb_running, :influxdb_error

    def initialize(sensor_mappings:, device_names:, readings:, influxdb_running:, influxdb_error: nil)
      super()
      @sensor_mappings = sensor_mappings
      @device_names = device_names
      @readings = readings
      @influxdb_running = influxdb_running
      @influxdb_error = influxdb_error
    end

    def sensors_configured?
      sensor_mappings.present?
    end

    # Returns: { 'SENEC' => [row, row, ...], 'Geschirrspüler' => [row], ... }
    def grouped_sensor_rows
      sensor_rows.group_by { |row| row[:device_name] || t('.unknown_device') }
    end

    def format_span(row)
      return '—' if row[:first_time].nil? || row[:time].nil?

      seconds = (row[:time] - row[:first_time]).to_i
      t(".duration.#{duration_unit(seconds)}", count: duration_count(seconds))
    end

    private

    def sensor_rows
      sensor_mappings.map { |var_name, mapping| build_row(var_name, mapping) }
    end

    def build_row(var_name, mapping)
      reading = readings[var_name]
      name = var_name.delete_prefix('INFLUX_SENSOR_')
      measurement, field = mapping.split(':', 2)

      {
        var_name:,
        name:,
        device_name: device_names[var_name],
        measurement:,
        field:,
        time: reading&.dig(:time),
        first_time: reading&.dig(:first_time),
        count: reading&.dig(:count) || 0,
      }
    end

    def duration_unit(seconds)
      DURATION_THRESHOLDS.each { |threshold, unit| return unit if seconds < threshold }
      :years
    end

    def duration_count(seconds)
      DURATION_THRESHOLDS.each { |threshold, _, divisor| return seconds / (divisor || 1) if seconds < threshold }
      seconds / (365 * 86_400)
    end
  end
end
