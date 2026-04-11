module ConfigNav
  class Component < ViewComponent::Base
    TAB_DEFINITIONS = [
      { id: :sensors, path_helper: :sensors_path, icon: 'fa-solid fa-gauge-high' },
      { id: :datasources, path_helper: :datasources_path, icon: 'fa-solid fa-satellite-dish' },
      { id: :advanced, path_helper: :advanced_path, icon: 'fa-solid fa-sliders' },
    ].freeze

    def initialize(active_tab:)
      super()
      @active_tab = active_tab
    end

    private

    attr_reader :active_tab

    def tabs
      TAB_DEFINITIONS.map { |tab| tab.merge(path: send(tab[:path_helper]), label: t(".#{tab[:id]}")) }
    end

    def active?(tab)
      tab[:id] == active_tab
    end

    def item_classes(tab)
      class_names(
        'group flex items-center gap-4 rounded-xl px-4 py-3 transition-colors',
        'bg-primary/15 text-primary': active?(tab),
        'text-base-content/80 hover:bg-base-content/5 hover:text-base-content': !active?(tab),
      )
    end

    def icon_box_classes(tab)
      class_names(
        'flex h-12 w-12 shrink-0 items-center justify-center rounded-lg text-2xl',
        'bg-primary/20 text-primary': active?(tab),
        'bg-base-300/70 text-base-content/60 group-hover:text-base-content': !active?(tab),
      )
    end
  end
end
