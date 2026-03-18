module SensorsHelper
  STALE_THRESHOLD = 1.hour

  DURATION_THRESHOLDS = [
    [60, :seconds],
    [3_600, :minutes, 60],
    [86_400, :hours, 3_600],
    [30 * 86_400, :days, 86_400],
    [365 * 86_400, :months, 30 * 86_400],
  ].freeze

  def sensor_value_cell(var_name, reading)
    name = var_name.delete_prefix('INFLUX_SENSOR_')
    value = reading&.dig(:value)
    time = reading&.dig(:time)
    unit = SensorRegistry.unit_for(name)
    css = sensor_freshness_class(value, time)
    dom_id = "sensor-value-#{name.parameterize}"

    content_tag(:td, id: dom_id, class: "text-right font-mono text-sm #{css}") do
      safe_join([
        sensor_formatted_value(value),
        value && unit.present? ? ' '.html_safe + content_tag(:span, unit, class: 'text-base-content/50') : nil,
      ].compact)
    end
  end

  def sensor_time_cell(var_name, reading)
    name = var_name.delete_prefix('INFLUX_SENSOR_')
    time = reading&.dig(:time)
    dom_id = "sensor-time-#{name.parameterize}"

    content_tag(:td, sensor_formatted_time(time), id: dom_id, class: 'text-base-content/50 text-sm')
  end

  def sensor_formatted_value(value)
    return '—' if value.nil?

    if value.is_a?(Numeric)
      value == value.to_i ? value.to_i.to_s : format('%.2f', value)
    else
      value.to_s
    end
  end

  def sensor_formatted_time(time)
    return '—' if time.nil?

    seconds = (Time.current - time).to_i
    t("sensor_table.component.time_ago.#{duration_unit(seconds)}", count: duration_count(seconds))
  end

  def sensor_freshness_class(value, time)
    return 'text-base-content/30' if value.nil?
    return 'text-warning' if time && time < STALE_THRESHOLD.ago

    'text-success'
  end

  private

  def duration_unit(seconds)
    DURATION_THRESHOLDS.each { |threshold, unit| return unit if seconds < threshold }
    :years
  end

  def duration_count(seconds)
    DURATION_THRESHOLDS.each { |threshold, _, divisor| return seconds / (divisor || 1) if seconds < threshold }
    seconds / (365 * 86_400)
  end
end
