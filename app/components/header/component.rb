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
    ].freeze

    TAB_BASE_CLASSES = 'flex items-center gap-2 rounded-full px-4 py-2 text-sm ' \
                       'font-semibold tracking-wider uppercase transition-colors'.freeze

    def initialize(active_tab:)
      super()
      @active_tab = active_tab
    end

    private

    attr_reader :active_tab

    def tabs
      TAB_DEFINITIONS
        .select { |tab| tab[:visible_if].nil? || tab[:visible_if].call }
        .map { |tab| tab.merge(path: send(tab[:path_helper]), label: t(".#{tab[:id]}")) }
    end

    def tab_classes(tab)
      class_names(
        TAB_BASE_CLASSES,
        'bg-primary/15 text-primary': tab[:id] == active_tab,
        'text-base-content/60 hover:bg-base-content/5 hover:text-base-content': tab[:id] != active_tab,
      )
    end
  end
end
