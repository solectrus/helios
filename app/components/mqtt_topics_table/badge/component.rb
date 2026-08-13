module MqttTopicsTable
  module Badge
    class Component < ViewComponent::Base
      # The row lightens on hover, so the fill follows the text color instead of
      # the background. A soft badge would dissolve into the hovered row. The
      # text is a value of the mapping, so it is set monospaced, like the topic
      # above it; the tooltip stays proportional via `tooltip_class`.
      DEFAULT_STYLE = 'bg-base-content/10 text-base-content/80 border-transparent font-mono'.freeze

      attr_reader :text, :tip, :tip_position, :icon, :style

      def initialize(text: nil, tip: nil, tip_position: 'tooltip-top', icon: nil, style: DEFAULT_STYLE)
        super()
        @text = text
        @tip = tip
        @tip_position = tip_position
        @icon = icon
        @style = style
      end

      # An option that its icon already tells goes without a word. The tooltip
      # then carries the whole meaning, so it also names the badge.
      def icon_only?
        text.blank?
      end

      def css_class
        ["badge badge-sm #{style} max-w-full gap-1.5 font-normal", (tooltip_class if tip)].compact.join(' ')
      end

      def icon_class
        icon_only? ? 'text-base-content/70' : 'text-base-content/50 text-[0.7em]'
      end

      private

      # The list clips what leaves it, so a wide tooltip on a badge near the
      # edge would lose its first words. A narrow one stays inside.
      def tooltip_class
        "tooltip #{tip_position} cursor-default before:max-w-56 before:font-sans before:text-xs before:normal-case"
      end
    end
  end
end
