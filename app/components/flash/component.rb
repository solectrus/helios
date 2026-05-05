module Flash
  class Component < ViewComponent::Base
    ALERT_CLASSES = { alert: 'alert-error', notice: 'alert-success' }.freeze
    AUTO_DISMISS_MS = 3000

    def initialize(flash:)
      super()
      @flash = flash
    end

    def render?
      messages.any?
    end

    private

    def messages
      @messages ||=
        ALERT_CLASSES.filter_map do |key, alert_class|
          message = @flash[key]
          [message, alert_class] if message.present?
        end
    end
  end
end
