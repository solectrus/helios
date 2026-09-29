# Rejects a measurement or field name that cannot work in InfluxDB or would
# reach the collectors split in the wrong place. The surveys already refuse
# both client-side, so this only catches a request that bypasses the UI. It is
# worth catching: the sensor would silently point somewhere else than the UI
# shows, or never receive data at all.
module InfluxNameValidation
  extend ActiveSupport::Concern

  private

  # Returns true when the save was refused and a response has been sent, so the
  # caller stops without writing anything.
  def invalid_influx_name?(data, path)
    name = invalid_name(data)
    refused?(name && t('sensors.errors.invalid_influx_name', name:), path)
  end

  def invalid_name(data)
    measurement = data['measurement']
    return measurement if measurement.present? && !SensorMappings.valid_measurement?(measurement)

    field = data['field']
    field if field.present? && !SensorMappings.valid_field?(field)
  end

  # Refuses a write into a measurement:field that another sensor, Shelly
  # device or MQTT mapping already writes. The two would overwrite each other.
  # The survey asks before it closes (see WriteChecksController), so this only
  # catches a request that bypasses the UI.
  def influx_target_taken?(owner, data, path)
    refused?(influx_target_message(owner, data), path)
  end

  def refused?(message, path)
    return false unless message

    flash[:alert] = message
    redirect_to path
    true
  end

  def influx_target_message(owner, data)
    reason, measurement, detail = Configuration.current.influx_write_conflict(owner, data)

    case reason
    when :reserved, :taken
      t("sensors.errors.measurement_#{reason}", measurement:, name: t("configurations.settings.#{detail}.title"))
    when :shelly then t('sensors.errors.shelly_measurement_taken', measurement:)
    when :field then t('sensors.errors.influx_target_taken', target: "#{measurement}:#{detail}")
    end
  end
end
