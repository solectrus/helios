module Orchestration
  class CommandResult
    attr_reader :output, :exit_status

    def initialize(output:, exit_status:)
      @output = output
      @exit_status = exit_status
    end

    def success?
      exit_status.zero?
    end

    def to_s
      output
    end

    def inspect
      status = success? ? 'success' : "failed(#{exit_status})"
      "#<Orchestration::CommandResult #{status}>\n#{output}"
    end
  end
end
