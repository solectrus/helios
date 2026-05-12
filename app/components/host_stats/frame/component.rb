module HostStats
  module Frame
    # Stream-replace target. Kept separate from the outer wrapper so the
    # polling Stimulus controller doesn't disconnect/reconnect — and briefly
    # double-poll — on each refresh.
    class Component < ViewComponent::Base
      def initialize(snapshot:)
        super()
        @snapshot = snapshot
      end

      private

      attr_reader :snapshot

      def metrics
        [
          [snapshot.cpu_percent, 'fa-solid fa-microchip', cpu_tooltip],
          [snapshot.ram_percent, 'fa-solid fa-memory', t('.ram')],
        ]
      end

      def value_text(value)
        value.nil? ? '—' : "#{value} %"
      end

      def value_class(value)
        value.to_i >= 80 ? 'text-warning' : 'text-base-content/65'
      end

      def cpu_tooltip
        cores = snapshot.cpu_cores
        return t('.cpu') if cores.nil?

        t('.cpu_detail', count: cores)
      end
    end
  end
end
