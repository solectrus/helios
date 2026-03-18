module MainNav
  class Component < ViewComponent::Base
    TAB_DEFINITIONS = [
      { id: :services, path_helper: :root_path, icon: 'fa-solid fa-cubes' },
      { id: :configuration, path_helper: :configuration_path, icon: 'fa-solid fa-gear' },
      { id: :sensors, path_helper: :sensors_path, icon: 'fa-solid fa-gauge' },
      { id: :generated_files, path_helper: :generated_files_path, icon: 'fa-solid fa-file-code', expert_only: true },
    ].freeze

    delegate :expert_mode?, to: :helpers

    def initialize(active_tab:)
      super()
      @active_tab = active_tab
    end

    private

    attr_reader :active_tab

    def tabs
      TAB_DEFINITIONS
        .reject { |tab| tab[:expert_only] && !expert_mode? }
        .map { |tab| tab.merge(path: send(tab[:path_helper]), label: t(".#{tab[:id]}")) }
    end

    def tab_classes(tab)
      base = 'tab'
      tab[:id] == active_tab ? "#{base} tab-active" : base
    end
  end
end
