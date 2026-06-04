module Export
  class Env
    class PowerSplitter < Section
      def call
        env.add_section('Power Splitter')

        # Fixed 5-minute recalculation cadence, not user-configurable.
        entry('POWER_SPLITTER_INTERVAL', 300,
              'Recalculation interval in seconds')
      end
    end
  end
end
