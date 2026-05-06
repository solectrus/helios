module StatusBar
  class Component < ViewComponent::Base
    STATE_CONFIG = {
      ok: {
        icon: 'fa-solid fa-circle-check',
        css: 'bg-success text-success-content',
      },
      starting: {
        icon: 'fa-solid fa-spinner fa-spin',
        css: 'bg-info text-info-content status-bar-barber-pole',
      },
      stopping: {
        icon: 'fa-solid fa-spinner fa-spin',
        css: 'bg-base-content text-base-100 status-bar-barber-pole',
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
        css: 'bg-base-content text-base-100',
      },
      restart_required: {
        icon: 'fa-solid fa-arrows-rotate',
        css: 'bg-warning text-warning-content',
      },
    }.freeze

    DEFAULT_CONFIG = STATE_CONFIG[:stopped]

    def initialize(status: nil)
      super()
      @status = status || Orchestration::StackStatus.overall
      @config = STATE_CONFIG.fetch(@status, DEFAULT_CONFIG)
    end

    def icon_class
      @config[:icon]
    end

    def bar_class
      @config[:css]
    end

    def labels
      counts = service_counts
      pending_restart = pending_restart_services
      pending_start = pending_start_services
      I18n.available_locales.index_with do |locale|
        restart_label(locale, pending_restart, pending_start, counts) ||
          t(".#{@status}", locale:, **counts)
      end
    end

    def show_start?
      @status.in?(%i[stopped partial error]) &&
        Configuration.current.setup_completed? &&
        !Configuration.current.incomplete? &&
        !Configuration.current.incomplete_influxdb?
    end

    def show_stop?
      @status.in?(%i[ok starting partial error])
    end

    def show_restart?
      @status == :restart_required
    end

    def batch_path
      '/services/batch'
    end

    private

    def service_counts
      Orchestration::StackStatus.service_counts
    end

    def pending_restart_services
      Orchestration::StackStatus.pending_restart_services
    end

    def pending_start_services
      Orchestration::StackStatus.pending_start_services
    end

    def restart_label(locale, restart, start, counts)
      return nil unless @status == :restart_required && restart.any?

      parts = []
      parts << pending_label(:start_pending_services, start, locale, counts) if start.any?
      parts << pending_label(:restart_required_services, restart, locale, counts)
      parts.join(' · ')
    end

    def pending_label(key, services, locale, counts)
      display_names = services.map { |s| Compose::Service.display_name_for(s) }
      t(".#{key}", locale:, services: display_names.join(', '), **counts)
    end
  end
end
