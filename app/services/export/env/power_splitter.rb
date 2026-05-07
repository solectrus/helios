module Export
  class Env
    class PowerSplitter < Section
      def call
        env.add_section('Power Splitter')

        interval = configuration.power_splitter.interval.presence || 3600
        entry('POWER_SPLITTER_INTERVAL', interval,
              'Recalculation interval in seconds (min 300)')
      end
    end
  end
end
