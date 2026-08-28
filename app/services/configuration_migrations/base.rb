module ConfigurationMigrations
  # Base class for config.yaml migrations. Provides a small DSL so concrete
  # migrations stay declarative — `version` and per-operation helpers like
  # `move` collect operations on the class, and `up` applies them in order.
  #
  # Example:
  #
  #   class CreateDashboardSection < Base
  #     version 1
  #     move %w[ui_theme lockup_codeword], from: 'system', to: 'dashboard'
  #   end
  class Base
    # Class-level state is set once at load time during DSL evaluation and
    # only read afterwards — no concurrent writes.
    # rubocop:disable-next ThreadSafety/ClassInstanceVariable
    class << self
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@operations, [])
      end

      def version(value = nil)
        @version = value if value
        @version
      end

      def operations
        @operations ||= []
      end

      # Move one or more fields from `from` to `to`. Skips silently if the
      # source section or the field is missing. Never clobbers a non-nil
      # value already present at the destination.
      def move(fields, from:, to:)
        Array(fields).each { |field| operations << [:move, field, from, to] }
      end
    end

    def up(data)
      self.class.operations.each do |type, *args|
        send(:"perform_#{type}", data, *args)
      end
      data
    end

    private

    def perform_move(data, field, from, to)
      source = data[from]
      return unless source.is_a?(Hash) && source.key?(field)

      value = source.delete(field)
      target = (data[to] ||= {})
      target[field] = value unless target.key?(field) && !target[field].nil?
    end
  end
end
