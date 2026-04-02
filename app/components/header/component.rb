module Header
  class Component < ViewComponent::Base
    TAB_DEFINITIONS = [
      { id: :configuration, path_helper: :configuration_path, icon: 'fa-solid fa-wrench' },
      { id: :services, path_helper: :services_path, icon: 'fa-solid fa-server' },
    ].freeze

    delegate :preferences, to: :helpers

    def initialize(active_tab:)
      super()
      @active_tab = active_tab
    end

    private

    attr_reader :active_tab

    def tabs
      TAB_DEFINITIONS
        .reject { |tab| tab[:expert_only] && !preferences.expert_mode? }
        .map { |tab| tab.merge(path: send(tab[:path_helper]), label: t(".#{tab[:id]}")) }
    end

    def tab_classes(tab)
      class_names(
        'inline-flex items-center gap-1 p-2 text-sm',
        'border-b-2 border-current': tab[:id] == active_tab,
      )
    end
  end
end
