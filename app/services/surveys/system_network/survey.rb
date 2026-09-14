module Surveys
  module SystemNetwork
    class Survey < Base
      private

      # The address has to name the machine to others, so the field refuses an
      # address that names it to itself. The rule lives in Loopback, the field
      # validates it while it is typed, and the controller refuses it again
      # for a request that bypasses the UI.
      def customize!(data)
        element = find_element(data, 'app_host')
        return unless element

        element['validators'] = [loopback_validator]
      end

      def loopback_validator
        {
          'type' => 'regex',
          'regex' => Loopback::SURVEY_PATTERN,
          'caseInsensitive' => true,
          'text' => self.class.localized(
            en: 'This address names the machine to itself alone. Others do not reach SOLECTRUS at it.',
            de: 'Diese Adresse benennt den Rechner nur sich selbst gegenüber. ' \
                'Andere erreichen SOLECTRUS darüber nicht.',
          ),
        }
      end
    end
  end
end
