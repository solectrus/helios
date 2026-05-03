# Latest measured value for a single InfluxDB measurement+field, plus the
# timestamp of that data point. Wraps the raw `{value:, time:}` returned by
# `InfluxDb::Client` so all consumers (sensor rows, MQTT topic cards, future
# widgets) share one formatting/freshness vocabulary.
class Reading
  STALE_AFTER = 1.hour
  EMPTY_DISPLAY = '—'.freeze

  attr_reader :value, :time

  def initialize(value:, time: nil)
    @value = value
    @time = time
  end

  def value?
    !value.nil?
  end

  def numeric?
    value.is_a?(Numeric)
  end

  def boolean?
    value.is_a?(String) && value.match?(/\A(?:true|false)\z/i)
  end

  def stale?
    !!(time && time < STALE_AFTER.ago)
  end

  def formatted(precision: 1)
    case value
    when nil then EMPTY_DISPLAY
    when Numeric
      value == value.to_i ? value.to_i.to_s : format("%.#{precision}f", value)
    else
      value.to_s
    end
  end

  def freshness_class
    return 'text-base-content/30' unless value?
    return 'text-warning' if stale?

    'text-success'
  end

  def timestamp_iso
    time&.iso8601
  end

  def boolean_label
    return unless boolean?

    value.casecmp('true').zero? ? I18n.t('common.boolean_yes') : I18n.t('common.boolean_no')
  end
end
