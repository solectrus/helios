module Surveys
  module Tibber
    # One survey for two services: the Tibber collector that fetches the hourly
    # prices, and optionally the SENEC charger that spends them (its tuning is
    # borrowed into the `senec_charger` section, see
    # Configuration::BORROWED_FIELDS).
    #
    # Collecting prices works for everyone, so the survey itself is never gated.
    # Charging is: it steers a locally-queried SENEC battery and reads the PV
    # forecast, and both dependencies live in sections SurveyJS can't see. Hence
    # the server-side split below.
    class Survey < Base
      CHARGING_PAGES = %w[p_charging p_price p_forecast p_options].freeze
      UNAVAILABLE_PAGE = 'p_charging_unavailable'.freeze

      def customize!(data)
        config = Configuration.current
        return drop_pages!(data, [UNAVAILABLE_PAGE]) if config.senec_charger_configurable?

        # A local battery but no forecast collector: name the missing dependency
        # instead of silently hiding the charging half of the survey.
        drop_pages!(data, CHARGING_PAGES)
        drop_pages!(data, [UNAVAILABLE_PAGE]) unless config.senec_charger_offered?
      end

      private

      def drop_pages!(data, names)
        data['pages'].reject! { |page| names.include?(page['name']) }
      end
    end
  end
end
