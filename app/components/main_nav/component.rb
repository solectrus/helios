module MainNav
  class Component < ViewComponent::Base
    def initialize(active_tab:)
      super()
      @active_tab = active_tab
    end

    private

    attr_reader :active_tab

    def tabs
      [
        {
          id: :services,
          path: root_path,
          icon: 'fa-solid fa-cubes',
          label: t('.services'),
        },
        {
          id: :configuration,
          path: configuration_path,
          icon: 'fa-solid fa-gear',
          label: t('.configuration'),
        },
      ]
    end

    def tab_classes(tab)
      base = 'tab'
      tab[:id] == active_tab ? "#{base} tab-active" : base
    end
  end
end
