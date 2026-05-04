module Import
  class ConfigurationImporter
    class SystemExtractor
      include Helpers

      def initialize(reader, collectors_only:, watchtower_interval:)
        @reader = reader
        @collectors_only = collectors_only
        @watchtower_interval = watchtower_interval
      end

      def section_data
        data = core_data.merge('app_host' => service_env('dashboard')['APP_HOST'])
        data['mode'] = ConfigSchema::MODE_COLLECTORS_ONLY if @collectors_only
        data.compact
      end

      private

      def core_data
        dashboard_env = service_env('dashboard')

        # Legacy compose files often define TZ in .env but don't reference it
        # from the dashboard service — fall back to raw_env so the user's
        # timezone survives the round-trip.
        {
          'timezone' => dashboard_env['TZ'].presence || @reader.raw_env['TZ'].presence,
          'installation_date' => dashboard_env['INSTALLATION_DATE'],
          'admin_password' => @reader.raw_env['ADMIN_PASSWORD'],
          'secret_key_base' => @reader.raw_env['SECRET_KEY_BASE'],
          'network_name' => imported_network_name,
          'update_interval' => @watchtower_interval,
        }
      end

      # Picks up an explicit `networks: default: name:` override from the
      # imported compose. Without an override, leave it nil so HELIOS falls
      # back to its default (`solectrus_default`). If the imported stack ran
      # under a differently-named auto-network (e.g. `senec_default` from a
      # directory named `senec`), `compose up` will create the new network
      # and leave the old one orphaned — harmless, since unmanaged services
      # only reference the compose-internal `default` alias, not the Docker
      # network name. The orphan is cleaned up by `docker network prune`.
      def imported_network_name
        @reader.raw_compose.dig('networks', 'default', 'name').presence
      end
    end
  end
end
