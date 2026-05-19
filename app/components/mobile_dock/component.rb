module MobileDock
  class Component < ViewComponent::Base
    SHEET_ID = 'mobile-dock-config-sheet'.freeze

    ITEM_DEFINITIONS = [
      { id: :configuration, icon: 'fa-solid fa-wrench', type: :sheet },
      { id: :services, path_helper: :services_path, icon: 'fa-solid fa-server', type: :link },
      {
        id: :backup,
        path_helper: :backups_path,
        icon: 'fa-solid fa-box-archive',
        type: :link,
        # Collectors-only stacks have no local databases, so backup never applies.
        visible_if: -> { !Configuration.current.collectors_only? },
      },
    ].freeze

    def initialize(active_tab:)
      super()
      @active_tab = active_tab
    end

    private

    attr_reader :active_tab

    def items
      @items ||=
        ITEM_DEFINITIONS
        .select { |item| item[:visible_if].nil? || item[:visible_if].call }
        .map { |item| item.merge(label: t(".#{item[:id]}")) }
    end

    def active?(item)
      item[:id] == active_tab
    end
  end
end
