module ConfigurationMigrations
  # Enables the sensors of the PV forecast band that are not yet configured,
  # where the forecast collector delivers the band.
  class EnableForecastBandSensors < Base
    version 10

    def up(data)
      sensors = data['sensors']
      return data unless sensors.is_a?(Hash) && Configuration.from_data(data).forecast_band_delivered?

      SensorRegistry::PVNODE_V2_SENSORS.each do |name|
        sensors[name] = { 'source' => 'forecast' } unless sensors.key?(name)
      end
      data
    end
  end
end
