module Export
  class Env
    class General < Section
      def call
        env.add_section('General settings')
        entry('TZ', configuration.system.timezone.presence || 'Europe/Berlin',
              'Timezone for all services (IANA format, e.g. Europe/Berlin)')
        optional_entry('INSTALLATION_DATE', configuration.system.installation_date,
                       'Date of first solar installation (YYYY-MM-DD) — used for statistics and charts')
      end
    end
  end
end
