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

    # Mirrors the warning sign of the top navigation, and its rule: the sign
    # stays on the level the reader has opened, but the color moves on with
    # them (see Header::Component#warning_classes).
    def show_warning?(item)
      item[:id] == :configuration && Configuration.current.incomplete_settings.any?
    end

    def dot_classes(item)
      active?(item) ? 'bg-base-content/30' : 'bg-warning'
    end

    # The dock has room for a dot, not for a sign next to the label.
    def icon_tag(item)
      icon = tag.i(class: "text-lg #{item[:icon]}", aria: { hidden: true })
      return icon unless show_warning?(item)

      tag.span(
        safe_join(
          [
            icon,
            tag.span(class: "absolute -top-1 -right-2 size-2 rounded-full #{dot_classes(item)}"),
            tag.span(t('configurations.show.incomplete'), class: 'sr-only'),
          ],
        ),
        class: 'relative',
      )
    end
  end
end
