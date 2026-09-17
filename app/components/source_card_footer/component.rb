module SourceCardFooter
  # The foot of every source card on the data sources screen: what the source
  # is set to on the left, how many sensors read through it on the right. Both
  # cards render it, so the two keep one look where they stand side by side.
  #
  # The left cell is the block content, because it is the one part that
  # differs: a status line where the source has settings, and nothing where it
  # has none.
  class Component < ViewComponent::Base
    def initialize(sensor_count:, dimmed: false, stimulus_scope: nil)
      super()
      @sensor_count = sensor_count
      @dimmed = dimmed
      @stimulus_scope = stimulus_scope
    end

    attr_reader :sensor_count

    # A card whose switch dims the footer alone passes `dimmed`. One that dims
    # as a whole leaves it off, or the two opacities would multiply.
    def dimmed?
      @dimmed
    end

    # A card with a Stimulus controller keeps its footer in step with the
    # switch before the server answers, so the wrapper and the link need its
    # targets. The external input has no switch and therefore no controller.
    def wrapper_data
      target_data('dim')
    end

    def link_data
      { turbo_frame: '_top' }.merge(target_data('link'))
    end

    private

    def target_data(name)
      return {} if @stimulus_scope.blank?

      { "#{@stimulus_scope}-target" => name }
    end
  end
end
