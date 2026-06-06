module Export
  class Env
    class Tibber < Section
      def call
        return unless Services::TibberCollector.enabled?(configuration)

        tibber = configuration.tibber
        env.add_section('Tibber collector')
        entry('TIBBER_TOKEN', tibber.token, 'Tibber API access token')
        entry('INFLUX_MEASUREMENT_PRICES', tibber.measurement.presence || 'Prices',
              'InfluxDB measurement name for electricity prices')
      end
    end
  end
end
