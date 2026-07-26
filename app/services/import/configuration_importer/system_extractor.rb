module Import
  class ConfigurationImporter
    class SystemExtractor
      include Helpers

      def initialize(reader, watchtower_interval:, watchtower_schedule:)
        @reader = reader
        @watchtower_interval = watchtower_interval
        @watchtower_schedule = watchtower_schedule
      end

      def section_data
        core_data.merge('app_host' => normalized_app_host).compact
      end

      private

      # APP_HOST is the bare hostname or IP; the dashboard adds the scheme at
      # runtime. Some users paste a full URL (`http://solar.example.com`)
      # into .env — strip the scheme so config.yaml stays clean and the
      # dashboard's URL construction doesn't end up with a double prefix.
      def normalized_app_host
        value = service_env('dashboard')['APP_HOST']
        return value if value.blank?

        value.sub(%r{\Ahttps?://}, '')
      end

      def core_data
        dashboard_env = service_env('dashboard')

        {
          'timezone' => env_or_raw(dashboard_env, 'TZ'),
          'currency' => env_or_raw(dashboard_env, 'CURRENCY')&.strip&.upcase,
          'installation_date' => dashboard_env['INSTALLATION_DATE'],
          # Direct raw_env (no .presence) preserves an explicit empty .env value,
          # otherwise ensure_defaults! would regenerate a random secret on every
          # round-trip and break determinism. Inline-only stacks (no .env) still
          # round-trip via service_env.
          'admin_password' => dashboard_env['ADMIN_PASSWORD'].presence || @reader.raw_env['ADMIN_PASSWORD'],
          'secret_key_base' => dashboard_env['SECRET_KEY_BASE'].presence || @reader.raw_env['SECRET_KEY_BASE'],
          'network_name' => imported_network_name,
          'update_mode' => update_mode,
          'update_interval' => @watchtower_interval,
          'update_time' => update_time,
        }
      end

      # A stack checking at a fixed time keeps doing so — but only if its cron
      # says "daily at HH:MM", the single shape HELIOS renders. Anything more
      # elaborate is dropped and the stack falls back to interval polling,
      # rather than HELIOS pretending to manage an expression it can't rebuild.
      def update_time
        return @update_time if defined?(@update_time)

        @update_time = WatchtowerSchedule.time_of_day(@watchtower_schedule)
      end

      def update_mode
        ConfigSchema::UPDATE_MODE_TIME if update_time
      end

      # Prefer the value referenced by the dashboard service, but fall back to
      # the raw .env — legacy compose files often define TZ/CURRENCY in .env
      # without referencing them from the dashboard service.
      def env_or_raw(dashboard_env, key)
        dashboard_env[key].presence || @reader.raw_env[key].presence
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
