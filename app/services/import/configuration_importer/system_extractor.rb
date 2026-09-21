module Import
  class ConfigurationImporter
    class SystemExtractor
      include Helpers

      def initialize(reader, watchtower_interval:, watchtower_schedule:, proxy_domain: nil)
        @reader = reader
        @watchtower_interval = watchtower_interval
        @watchtower_schedule = watchtower_schedule
        @proxy_domain = proxy_domain
      end

      def section_data
        core_data.merge('app_host' => normalized_app_host).compact
      end

      private

      # APP_HOST holds the host alone in config.yaml, the same as after a save
      # through the form. A hand-written .env carries whatever its author put
      # there, a full URL (`http://solar.example.com`) among it, so the value
      # goes through the one normalizer every write path uses.
      #
      # The domain a Traefik of the stack routes the dashboard at wins over
      # APP_HOST. That is the address the stack answers on, while APP_HOST may
      # hold anything its author left there, the address of the machine on the
      # local network among it. One field carries the address in every mode
      # (see ConfigurationMigrations::MergeAppDomain), so the two cannot both
      # be kept.
      #
      # A loopback address is dropped, the same way
      # ConfigurationMigrations::NormalizeAppHost drops one an earlier HELIOS
      # stored: it names the machine to itself alone, the field refuses it, and
      # an imported stack would carry a value its own form rejects. Each address
      # is judged on its own, so a router rule that names the machine to itself
      # drops out and leaves APP_HOST its turn. `section_data` compacts the nil
      # away where neither survives, and every caller then names the published
      # port instead.
      def normalized_app_host
        HostAddress.public_host(@proxy_domain) ||
          HostAddress.public_host(service_env('dashboard')['APP_HOST'])
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
