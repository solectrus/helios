module Export
  class Env
    class PowerSplitter < Section
      def call
        env.add_section('Power Splitter')

        entry('POWER_SPLITTER_INTERVAL', 300,
              'Recalculation interval in seconds (min 300)')
      end
    end
  end
end
