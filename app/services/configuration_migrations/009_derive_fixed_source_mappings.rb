module ConfigurationMigrations
  # Pins the measurement a fixed-source collector writes into, and drops the
  # copy of it that every sensor of that source carried.
  #
  # A fixed source (senec, forecast) has one collector, and that collector
  # writes every one of its sensors into one measurement. A copy of that name
  # on the sensor therefore says nothing new, and it does harm: the copy stays
  # behind when the measurement of the collector changes, and the sensor then
  # reads a measurement nothing writes to. The export reads the name off the
  # section of the source now, so the copy has no reader left.
  #
  # A value that differs from the derived one stays. It says the sensor reads
  # somewhere other than the collector writes, which is the choice of whoever
  # built the stack, and HELIOS is not the one to undo it.
  class DeriveFixedSourceMappings < Base
    version 9

    # What an earlier HELIOS told a fixed-source collector to write into where
    # the section of the source names nothing itself.
    #
    # `forecast` is such a name. The forecast collector writes into `Forecast`
    # on its own, and HELIOS assumed the lowercase name until this version. The
    # assumption is wrong, but it is what the running stack carries, and the
    # readings taken under it are bound to that name. An update must not move a
    # collector to another measurement, so the name is written out here and the
    # collector stays where it is. Whoever wants the other name says so in the
    # form, and takes the readings with them.
    #
    # `SENEC` is here for the senec collector alone, which has always agreed
    # with HELIOS. Nothing is written out for it.
    LEGACY_DEFAULT_MEASUREMENTS = { 'senec' => 'SENEC', 'forecast' => 'forecast' }.freeze

    def up(data)
      sensors = data['sensors']
      return data unless sensors.is_a?(Hash)

      SensorMappings::FIXED_SOURCES.each { |source| settle(source, data, sensors) }
      data
    end

    private

    def settle(source, data, sensors)
      pin_measurement(source, data)
      measurement = source_measurement(data, source)

      sensors.each { |name, config| prune(name, config, source, measurement) }
    end

    # Writes out the name the section held by way of the default alone, so the
    # collector keeps writing where it writes today. Nothing is written where
    # the section names a measurement itself, or where the name it held is the
    # one HELIOS derives from now on anyway.
    def pin_measurement(source, data)
      section = data[source]
      return unless section.is_a?(Hash) && section['measurement'].blank?

      legacy = LEGACY_DEFAULT_MEASUREMENTS[source]
      return if legacy == SensorMappings::DEFAULT_MEASUREMENTS[source]

      section['measurement'] = legacy
    end

    def prune(sensor_name, config, source, source_measurement)
      return unless config.is_a?(Hash) && config['source'].to_s == source

      derivable = SensorMappings.derivable_mapping?(
        sensor_name, source, config['measurement'], config['field'], source_measurement
      )
      return unless derivable

      config.delete('measurement')
      config.delete('field')
    end

    def source_measurement(data, source)
      section = data[source]
      section['measurement'] if section.is_a?(Hash)
    end
  end
end
