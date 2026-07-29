module Orchestration
  module PowerSplitter
    # Asks a running power-splitter to throw away its calculated values and
    # derive them again from the raw measurements.
    #
    # power-splitter traps USR1 (power-splitter/lib/loop.rb#start): it stops
    # the processing thread, deletes its whole InfluxDB measurement and then
    # reprocesses every day since the installation date. There is no other
    # entry point — the signal is the documented interface
    # (https://github.com/solectrus/power-splitter).
    class Recalculation
      include Loggable

      SIGNAL = 'USR1'.freeze

      def self.call(container)
        new(container).call
      end

      def initialize(container)
        @container = container
      end

      def call
        return false unless container&.running?

        logger.info("docker kill --signal #{SIGNAL} #{container.name}")
        container.kill(signal: SIGNAL)
        State.trigger!
        true
      rescue Docker::Error::DockerError, Excon::Error => e
        logger.warn("failed: #{e.class}: #{e.message}")
        false
      end

      private

      attr_reader :container
    end
  end
end
