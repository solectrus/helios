# Words the reason Configuration#influx_write_conflict gives, for the form
# that refuses a save and for the sensor list that flags a stored collision.
module InfluxWriteConflict
  def self.message(configuration, owner, config)
    reason, measurement, detail = configuration.influx_write_conflict(owner, config)

    case reason
    when :reserved, :taken
      I18n.t("sensors.errors.measurement_#{reason}", measurement:,
                                                     name: I18n.t("configurations.settings.#{detail}.title"))
    when :shelly then I18n.t('sensors.errors.shelly_measurement_taken', measurement:)
    when :field then I18n.t('sensors.errors.influx_target_taken', target: "#{measurement}:#{detail}")
    end
  end
end
