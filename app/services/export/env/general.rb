module Export
  class Env
    class General < Section
      def call
        env.add_section('General settings')
        entry('TZ', configuration.system.timezone.presence || 'Europe/Berlin',
              'Timezone for all services (IANA format, e.g. Europe/Berlin)')
        optional_entry('INSTALLATION_DATE', configuration.system.installation_date,
                       'Date of first solar installation (YYYY-MM-DD) — used for statistics and charts')
        entry('CURRENCY', currency_code,
              'Currency for monetary values in the dashboard (ISO 4217 code, e.g. EUR, CHF, USD)')
      end

      private

      # The dropdown stores the ISO-4217 code directly (common choices and the
      # free-text "other" value alike). Upcased so config.yaml casing never
      # leaks into .env, and always emitted with the EUR default so .env states
      # the currency explicitly, matching TZ.
      def currency_code
        configuration.system.currency.presence&.strip&.upcase || 'EUR'
      end
    end
  end
end
