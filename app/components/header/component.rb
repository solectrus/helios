module Header
  class Component < ViewComponent::Base
    TAB_DEFINITIONS = [
      { id: :configuration, path_helper: :sensors_path, icon: 'fa-solid fa-wrench' },
      {
        id: :services,
        path_helper: :services_path,
        icon: 'fa-solid fa-server',
        visible_if: -> { Configuration.current.setup_completed? },
      },
      {
        id: :backup,
        path_helper: :backups_path,
        icon: 'fa-solid fa-box-archive',
        visible_if: -> { Configuration.current.setup_completed? && !Configuration.current.collectors_only? },
      },
    ].freeze

    TAB_BASE_CLASSES = 'flex items-center gap-2 rounded-full px-4 py-1.5 text-sm font-semibold ' \
                       'tracking-[0.1em] uppercase transition-colors'.freeze

    DRAWER_BASE_CLASSES = 'flex items-center gap-3 rounded-lg px-3 py-2 text-base'.freeze

    def initialize(active_tab:)
      super()
      @active_tab = active_tab
    end

    private

    attr_reader :active_tab

    def tabs
      @tabs ||=
        TAB_DEFINITIONS
        .select { |tab| tab[:visible_if].nil? || tab[:visible_if].call }
        .map { |tab| tab.merge(path: tab_path(tab), label: t(".#{tab[:id]}")) }
    end

    # In collectors_only mode the Sensors page is unreachable; route the
    # Configuration top-level tab straight to Datasources.
    def tab_path(tab)
      if tab[:id] == :configuration && Configuration.current.collectors_only?
        datasources_path
      else
        send(tab[:path_helper])
      end
    end

    def tab_classes(tab)
      class_names(
        TAB_BASE_CLASSES,
        'text-primary bg-primary/10 font-semibold': tab[:id] == active_tab,
        'text-base-content/65 hover:bg-base-content/5 hover:text-base-content': tab[:id] != active_tab,
      )
    end

    def drawer_item_classes(tab)
      class_names(
        DRAWER_BASE_CLASSES,
        'bg-primary/15 text-primary font-semibold': tab[:id] == active_tab,
        'text-base-content/80 hover:bg-base-content/5': tab[:id] != active_tab,
      )
    end
  end
end
