module InfoTooltip
  # Small info icon next to a heading that reveals an explanatory text in a
  # daisyUI tooltip on hover/focus. Keeps secondary hints out of the layout.
  class Component < ViewComponent::Base
    def initialize(text:)
      super()
      @text = text
    end
  end
end
