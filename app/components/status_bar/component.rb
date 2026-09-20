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
      restore_in_progress: {
        icon: 'fa-solid fa-arrow-rotate-left fa-spin',
        css: 'bg-warning text-warning-content status-bar-barber-pole',
      },
    }.freeze

    DEFAULT_CONFIG = STATE_CONFIG[:stopped]

    # Action buttons shown on the right of the bar. The first available one
    # becomes the prominent primary button, the rest collapse into a dropdown,
    # so the bar never grows a row of competing buttons.
    # `long_label` is the spelled-out variant ("Stop all services"), used in the
    # dropdown and for a lone button; `label` is the compact one used only when
    # the action sits next to a dropdown caret in a split button.
    ACTIONS = {
      open: { icon: 'fa-up-right-from-square', label: 'open_dashboard' },
      start: { icon: 'fa-play', label: 'start', long_label: 'start_all', partial_label: 'start_missing' },
      restart: { icon: 'fa-arrows-rotate', label: 'restart', long_label: 'restart_all' },
      stop: { icon: 'fa-stop', label: 'stop', long_label: 'stop_all' },
    }.freeze

    # `mark_active_locale` emits the native `hidden` attribute on the
    # non-active locale for a flash-free first paint (see #locale_label_tags).
    # It is only correct when the render locale matches the recipient's locale,
    # i.e. for request-scoped renders. Locale-agnostic broadcasts (rendered
    # with the default locale but delivered to clients of either language) must
    # disable it and rely purely on the per-client CSS instead.
    def initialize(status: nil, mark_active_locale: true)
      super()
      @restore_in_progress = RestoreRunner.in_progress.present?
      @backup_in_progress = !@restore_in_progress && BackupRunner.in_progress.present?
      @status = derive_status(status)
      @config = STATE_CONFIG.fetch(@status, DEFAULT_CONFIG)
      @mark_active_locale = mark_active_locale
    end

    def icon_class
      @config[:icon]
    end

    def bar_class
      @config[:css]
    end

    def labels
      return restore_labels if @status == :restore_in_progress

      counts = service_counts
      pending_restart = pending_restart_services
      I18n.available_locales.index_with do |locale|
        restart_label(locale, pending_restart, counts) ||
          t(".#{@status}", locale:, **counts)
      end
    end

    def backup_hint_labels
      return nil unless @backup_in_progress

      I18n.available_locales.index_with { |locale| t('.backup_in_progress', locale:) }
    end

    # The action stays on the bar while a setting is still open. An empty
    # place says nothing about why, so it is shown and refuses instead.
    # Before the first sensor there is nothing to start at all, and the
    # screens say so themselves, so the action stays away until then.
    def show_start?
      return false if operation_in_progress?

      Configuration.current.setup_completed? && @status.in?(%i[stopped partial error])
    end

    # Refused again by ApplicationController#require_configuration_complete.
    def start_blocked? = !Configuration.current.configuration_complete?

    def show_stop?
      return false if operation_in_progress?

      @status.in?(%i[ok starting partial error])
    end

    def show_restart?
      return false if operation_in_progress?

      @status == :restart_required
    end

    # Prominent shortcut to the SOLECTRUS dashboard, shown whenever the
    # dashboard container is up and healthy and has a browsable endpoint —
    # the small per-row "Open" button is easy to miss for new users.
    def dashboard_endpoint
      return @dashboard_endpoint if defined?(@dashboard_endpoint)

      @dashboard_endpoint =
        if dashboard_reachable?
          Export::OpenEndpoint.resolve(
            service_name: 'dashboard',
            public_port: dashboard_public_port,
          )
        end
    end

    def show_dashboard?
      dashboard_endpoint.present?
    end

    # Available actions in priority order. The dashboard shortcut leads (the
    # main thing a regular user wants), stack lifecycle controls follow.
    def actions
      acts = []
      acts << :open if show_dashboard?
      acts << :start if show_start?
      acts << :restart if show_restart?
      acts << :stop if show_stop?
      acts
    end

    def primary_action
      actions.first
    end

    def dropdown_actions
      actions.drop(1)
    end

    # Renders one action as either the prominent JS "open" button or a stack
    # lifecycle form button, with the given CSS classes — used for both the
    # primary button and the dropdown menu items.
    def action_button(key, css, long: false, icon_only_mobile: false)
      return open_button(css, icon_only_mobile:) if key == :open
      return blocked_start_button(css, long:, icon_only_mobile:) if key == :start && start_blocked?

      button_to(batch_path, method: action_method(key), class: css, form_class: 'contents') do
        action_inner(key, long:, icon_only_mobile:)
      end
    end

    def batch_path
      '/services/batch'
    end

    # Renders the same text in every locale as sibling spans; the component
    # stylesheet shows only the one matching the client's <html lang>.
    #
    # For request-scoped renders the non-active locales also carry the native
    # `hidden` attribute so the right language already shows at first paint,
    # before the (Vite-injected) component CSS loads — otherwise both languages
    # flash and shift the layout on a hard reload.
    #
    # Broadcasts render with the default locale but are delivered to clients of
    # either language, so they must NOT bake in `hidden` (that would hide the
    # text for every client whose locale differs from the default until the CSS
    # corrects it). They set `mark_active_locale: false` and rely on the CSS,
    # which the page already has loaded by the time a broadcast arrives.
    def locale_label_tags(labels, extra_class = nil)
      safe_join(
        labels.map do |locale, text|
          tag.span(
            text,
            data: { locale: },
            hidden: @mark_active_locale && locale != I18n.locale,
            class: ['status-bar-label', extra_class].compact.join(' '),
          )
        end,
      )
    end

    private

    # Disabled, and carrying what blocks it in the words and the colour of the
    # warning sign in the navigation. The text sits in a `tooltip-content`
    # element rather than in `data-tip`: an attribute holds one language, and
    # a broadcast bar is rendered once for clients of both.
    def blocked_start_button(css, long:, icon_only_mobile:)
      button = button_to(batch_path, method: :post, class: css, form_class: 'contents', disabled: true) do
        action_inner(:start, long:, icon_only_mobile:)
      end
      hint = tag.div(locale_label_tags(incomplete_labels), class: 'tooltip-content')

      # To the left, not above: the bar is the last strip of the screen, and a
      # tooltip over it would sit half on the page behind it.
      #
      # tabindex: a disabled button takes no focus, so a tap lands on this
      # wrapper and opens the tooltip on a touch device, where there is no
      # hover to open it with.
      #
      # block and p-0: in the dropdown the wrapper sits where the button sat,
      # and the menu styles that place hold a grid plus the padding of a row.
      # The button would keep a quarter of the row. The two classes hand both
      # back to it, and leave the split button beside the bar untouched.
      tag.div(safe_join([hint, button]), class: 'tooltip tooltip-left tooltip-warning block p-0', tabindex: -1)
    end

    def incomplete_labels
      I18n.available_locales.index_with { |locale| t('configurations.show.incomplete', locale:) }
    end

    def open_button(css, icon_only_mobile: false)
      tag.button(
        action_inner(:open, icon_only_mobile:),
        type: 'button',
        class: css,
        data: {
          controller: 'open-external',
          action: 'click->open-external#open',
          url: dashboard_endpoint[:url],
          port: dashboard_endpoint[:port],
        },
      )
    end

    # Icon plus the per-locale labels (see #locale_label_tags).
    #
    # `icon_only_mobile` wraps the labels so they collapse to sr-only below the
    # `sm` breakpoint — the primary button shrinks to its icon where space is
    # tight, while keeping an accessible name. The wrapper is needed because the
    # per-locale CSS rule outranks a plain `max-sm:hidden` on the spans.
    def action_inner(key, long: false, icon_only_mobile: false)
      labels = locale_label_tags(action_labels(key, long:), 'whitespace-nowrap')
      labels = tag.span(labels, class: 'max-sm:sr-only') if icon_only_mobile

      safe_join([tag.i(class: "fa-solid #{ACTIONS.fetch(key)[:icon]}"), labels])
    end

    def action_labels(key, long: false)
      spec = ACTIONS.fetch(key)
      label = start_label(spec) || (long && spec[:long_label]) || spec[:label]
      I18n.available_locales.index_with { |locale| t(".#{label}", locale:) }
    end

    # In the :partial state some services already run, so the start action only
    # fills the gaps — spell that out ("Start missing services") instead of the
    # generic "Start" / "Start all services".
    def start_label(spec)
      spec[:partial_label] if @status == :partial
    end

    def action_method(key)
      key == :stop ? :delete : :post
    end

    def derive_status(provided)
      return :restore_in_progress if @restore_in_progress

      provided || Orchestration::StackStatus.overall
    end

    def operation_in_progress?
      @restore_in_progress || @backup_in_progress
    end

    # Reachable means running and past its healthcheck (effective_status :ok) —
    # opening a still-booting dashboard would likely hit a half-rendered UI.
    # Reads the cached StackStatus (same source as the service counts) instead
    # of a fresh Docker lookup, so this stays cheap in the broadcast-heavy
    # status bar render path.
    def dashboard_reachable?
      Orchestration::StackStatus.status_for('dashboard') == :ok
    end

    # Direct host port the dashboard publishes (nil when routed through a
    # reverse proxy). Taken from the compose config rather than the running
    # container — reachability is already confirmed via StackStatus.
    def dashboard_public_port
      ::Compose.load.services.find('dashboard')&.public_port
    end

    def restore_labels
      I18n.available_locales.index_with { |locale| t('.restore_in_progress', locale:) }
    end

    def service_counts
      Orchestration::StackStatus.service_counts
    end

    def pending_restart_services
      Orchestration::StackStatus.pending_restart_services
    end

    def restart_label(locale, restart, counts)
      return nil unless @status == :restart_required && restart.any?

      pending_label(:restart_required_services, restart, locale, counts)
    end

    def pending_label(key, services, locale, counts)
      display_names = services.map { |s| Compose::Service.display_name_for(s) }
      t(".#{key}", locale:, services: display_names.join(', '), **counts)
    end
  end
end
