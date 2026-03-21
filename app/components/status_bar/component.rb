module StatusBar
  class Component < ViewComponent::Base
    STATE_CONFIG = {
      ok: {
        icon: 'fa-solid fa-circle-check',
        css: 'bg-success text-success-content',
      },
      starting: {
        icon: 'fa-solid fa-spinner fa-spin',
        css: 'bg-info text-info-content',
      },
      partial: {
        icon: 'fa-solid fa-circle-half-stroke',
        css: 'bg-warning text-warning-content',
      },
      error: {
        icon: 'fa-solid fa-circle-exclamation',
        css: 'bg-error text-error-content',
      },
      stopped: {
        icon: 'fa-solid fa-circle-stop',
        css: 'bg-base-content/30 text-base-content/70',
      },
      restart_required: {
        icon: 'fa-solid fa-arrows-rotate',
        css: 'bg-warning text-warning-content',
      },
    }.freeze

    DEFAULT_CONFIG = STATE_CONFIG[:stopped]

    def initialize(status: nil)
      super()
      @status = status || DockerHost::StackStatus.overall
      @config = STATE_CONFIG.fetch(@status, DEFAULT_CONFIG)
    end

    def icon_class
      @config[:icon]
    end

    def bar_class
      @config[:css]
    end

    def labels
      I18n.available_locales.index_with do |locale|
        t(".#{@status}", locale:)
      end
    end
  end
end
