module Export
  class Env
    class General < Section
      def call
        env.add_section('General settings')
        entry('TZ', configuration.timezone,
              'Timezone for all services (IANA format, e.g. Europe/Berlin)')
        optional_entry('INSTALLATION_DATE', configuration.system.installation_date,
                       'Date of first solar installation (YYYY-MM-DD) — used for statistics and charts')
        entry('CURRENCY', configuration.currency,
              'Currency for monetary values in the dashboard (ISO 4217 code, e.g. EUR, CHF, USD)')
        optional_entry('COUNTRY', country,
                       'Country of the installation (ISO 3166 code, e.g. DE)')
      end

      private

      # Only the public-data-collector reads the country so far.
      def country
        configuration.country if Services::PublicDataCollector.enabled?(configuration)
      end
    end
  end
end
