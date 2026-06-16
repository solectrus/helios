module ConfigNav
  class Component < ViewComponent::Base
    TAB_DEFINITIONS = [
      { id: :sensors, path_helper: :sensors_path, icon: 'fa-solid fa-gauge-high' },
      { id: :datasources, path_helper: :datasources_path, icon: 'fa-solid fa-satellite-dish' },
      { id: :advanced, path_helper: :advanced_path, icon: 'fa-solid fa-sliders' },
    ].freeze

    def initialize(active_tab: nil, compact: false, only: nil)
      super()
      @active_tab = active_tab
      @compact = compact
      @only = only
    end

    private

    attr_reader :only

    def compact?
      @compact
    end

    def show_tabs?
      only != :files
    end

    # The compose.yaml / .env preview links only make sense once setup is
    # completed — before that there is no stack and previewing them must not
    # create the files prematurely.
    def show_files?
      only != :tabs && Configuration.current.setup_completed?
    end

    def docker_file_links
      [
        { key: 'compose', icon: 'fa-file-code', label: ::Compose.filename },
        { key: 'env', icon: 'fa-file-lines', label: '.env' },
      ]
    end

    # External-Traefik mode: offer the file-provider snippet to copy into the
    # external Traefik (HELIOS only publishes host ports, see TraefikConfig).
    # Shown under its own "Generated for Traefik" heading.
    def show_traefik_file?
      Configuration.current.reverse_proxy_external?
    end

    def active_tab
      @active_tab ||= begin
        controller_id = helpers.controller_name.to_sym
        controller_id if TAB_DEFINITIONS.any? { |t| t[:id] == controller_id }
      end
    end

    def tabs
      @tabs ||= visible_tab_definitions.map { |tab| tab.merge(path: send(tab[:path_helper]), label: t(".#{tab[:id]}")) }
    end

    # Sensors are managed on the remote dashboard host in collectors_only mode,
    # so the local /sensors UI has no meaning here.
    def visible_tab_definitions
      return TAB_DEFINITIONS unless Configuration.current.collectors_only?

      TAB_DEFINITIONS.reject { |tab| tab[:id] == :sensors }
    end

    def active?(tab)
      tab[:id] == active_tab
    end

    def item_classes(tab)
      active = active?(tab)

      if compact?
        class_names(
          item_base_classes,
          'bg-primary/15 text-primary font-semibold': active,
          'text-base-content/70 hover:bg-base-content/5 hover:text-base-content': !active,
        )
      else
        class_names(
          item_base_classes,
          'bg-primary/10 text-primary font-semibold before:bg-primary': active,
          'text-base-content/75 hover:bg-base-content/5 hover:text-base-content before:bg-transparent': !active,
        )
      end
    end

    def item_base_classes
      if compact?
        'flex items-center gap-3 rounded-lg px-3 py-2 text-base transition-colors'
      else
        'group relative flex items-center gap-3 rounded-lg px-3 py-2.5 text-base transition-colors ' \
          'before:absolute before:top-2 before:bottom-2 before:left-0 before:w-0.5 before:rounded-full ' \
          'before:transition-colors'
      end
    end

    def icon_box_classes(tab)
      return 'w-5 text-center text-base' if compact?

      class_names(
        'w-5 shrink-0 text-center text-base',
        'text-primary': active?(tab),
        'text-base-content/55 group-hover:text-base-content': !active?(tab),
      )
    end

    def file_link_classes
      if compact?
        'flex items-center gap-3 rounded-lg px-3 py-2 hover:bg-base-content/5 ' \
          'text-base-content/70 transition-colors'
      else
        'flex items-center gap-3 rounded-lg px-3 py-2 font-mono text-sm ' \
          'text-base-content/70 hover:bg-base-content/5 hover:text-base-content transition-colors'
      end
    end

    def show_warning?(tab)
      case tab[:id]
      when :datasources then Configuration.current.incomplete?
      when :advanced
        Configuration.current.incomplete_influxdb? ||
          Configuration.current.incomplete_system_general?
      end
    end

    def show_reset?
      only != :tabs && StackBackup.exist?
    end

    def reset_actions
      ResetDialogs::Component::DIALOGS
    end

    def reset_link_classes
      'group/reset flex items-center gap-3 rounded-md px-3 py-2 text-sm transition-colors ' \
        'text-base-content/75 hover:bg-error/15 hover:text-base-content'
    end
  end
end
