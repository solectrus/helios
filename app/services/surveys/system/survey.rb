module Surveys
  module System
    # The system survey hides parts of itself depending on the current
    # deployment mode. Mode lives in its own section, so the JSON cannot
    # express the gating with SurveyJS' `visibleIf` (which only sees fields
    # within the same survey). Pages and elements use a `visibleIfMode`
    # marker instead, which we resolve here against `Configuration#mode`.
    class Survey < Base
      MODE_PREDICATES = {
        'not_collectors_only' => ->(mode) { mode != ConfigSchema::MODE_COLLECTORS_ONLY },
      }.freeze

      private

      def customize!(data)
        mode = Configuration.current.mode
        data['pages']&.reject! { |page| hidden_for_mode?(page, mode) }
        data['pages']&.each do |page|
          page['elements']&.reject! { |element| hidden_for_mode?(element, mode) }
        end
      end

      def hidden_for_mode?(node, mode)
        marker = node.delete('visibleIfMode')
        return false unless marker

        predicate = MODE_PREDICATES[marker]
        return false unless predicate

        !predicate.call(mode)
      end
    end
  end
end
