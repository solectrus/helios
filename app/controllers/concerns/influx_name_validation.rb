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
    return false unless name

    flash[:alert] = t('sensors.errors.invalid_influx_name', name:)
    redirect_to path
    true
  end

  def invalid_name(data)
    measurement = data['measurement']
    return measurement if measurement.present? && !SensorMappings.valid_measurement?(measurement)

    field = data['field']
    field if field.present? && !SensorMappings.valid_field?(field)
  end
end
