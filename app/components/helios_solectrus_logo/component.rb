module HeliosSolectrusLogo
  class Component < ViewComponent::Base
    def initialize(css_class:)
      super()
      @css_class = css_class
    end

    private

    attr_reader :css_class
  end
end
