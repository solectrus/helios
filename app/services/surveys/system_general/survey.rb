module Surveys
  module SystemGeneral
    class Survey < Base
      private

      # The currency page only exists while the dashboard runs on the
      # development channel (see its `visibleIfDevelop` marker), so the header
      # must not announce a currency question that is not there.
      def customize!(data)
        return if find_page(data, 'p_currency')

        data['description'] = self.class.localized(
          de: 'Inbetriebnahme und Zeitzone',
          en: 'Commissioning date and timezone',
        )
      end
    end
  end
end
