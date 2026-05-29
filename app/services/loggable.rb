# Gives a class or module its own logger that prefixes every line with the
# class/module name centrally — no per-message "[ClassName]" literals to write
# or forget.
#
#   class Foo
#     include Loggable   # for instance-method logging
#     extend  Loggable   # for class-method logging
#   end
#
#   Foo.new.logger.info('hi')  # => "[Foo] hi"
#   Foo.logger.info('hi')      # => "[Foo] hi"
#
# Why a literal prefix and not Rails.logger.tagged(name)? Under `bin/dev`,
# `rails server` broadcasts the development log to a *plain* STDOUT logger
# (ActiveSupport::Logger.new($stdout)). ActiveSupport::BroadcastLogger#tagged
# dispatches only to sinks that respond to `tagged`, so a tagged logger reaches
# development.log but never the terminal. Sending a literal prefix straight
# through Rails.logger hits every broadcast sink, so the line shows up both in
# the file and in the `bin/dev` terminal.
#
# Do NOT use in ActiveJob or ActionController subclasses — they already define
# `logger`; use their framework logger instead.
module Loggable
  # The standard severities. Only debug/info/warn/error are used today; fatal
  # and unknown are wired up for completeness.
  LEVELS = %i[debug info warn error fatal unknown].freeze

  def logger
    # self is a Class/Module when extended (class-method context), an instance
    # when included (instance-method context).
    PrefixedLogger.new(is_a?(Module) ? name : self.class.name)
  end

  # Forwards each severity to Rails.logger, prefixing the message with the tag.
  # Logging through Rails.logger (rather than a tagged sub-logger) is what keeps
  # the line visible on every broadcast sink — see the note above.
  class PrefixedLogger
    def initialize(tag)
      @tag = tag
    end

    LEVELS.each do |level|
      define_method(level) do |message = nil, &block|
        Rails.logger.public_send(level) { "[#{@tag}] #{block ? block.call : message}" }
      end
    end
  end
end
