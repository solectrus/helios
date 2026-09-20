module Export
  class Env
    class Dashboard < Section
      def call
        env.add_section('Dashboard')
        # Omitted rather than filled in when the address is unknown. The
        # dashboard reads the value with `.presence` and uses it for one thing,
        # the CORS origin it accepts a request from.
        #
        # That rule is narrower than it looks. Rack::Cors compiles a bare
        # hostname into `^[a-z][a-z0-9.+-]*://<host>$`, which carries no port,
        # so the origin matches only a dashboard served on 80 or 443, meaning
        # one behind a reverse proxy. A loopback name therefore never matches:
        # the dashboard carries a host port of its own there, and even on 80
        # the rule would allow the page the origin it is already served from,
        # which no same-origin request consults.
        #
        # So a guessed name is worse than none. It allows an origin nobody
        # calls the dashboard at, while a missing one drops a rule that had
        # nothing to do anyway. The form that asks for the address refuses a
        # loopback name for the same reason.
        #
        # Configuration#public_host, not app_host: behind the managed Traefik
        # the dashboard answers on the domain, while app_host holds the address
        # of the machine on the local network.
        optional_entry('APP_HOST', configuration.public_host,
                       'Hostname for the SOLECTRUS web interface')
        entry('FORCE_SSL', force_ssl?,
              'Must be TRUE only when a reverse proxy terminates TLS in front of the dashboard')
        entry('WEB_CONCURRENCY', 0,
              'Number of Puma worker processes (0 = single-process mode, sufficient for most setups)')
        optional_entries(configuration.dashboard)
      end

      private

      # TLS in front of the dashboard: implied by the HELIOS-managed Traefik,
      # otherwise taken from the `force_ssl` flag the reverse-proxy survey sets
      # for a proxy the user runs themselves (Traefik, nginx, Apache).
      def force_ssl?
        Services::Traefik.enabled?(configuration) || configuration.dashboard.force_ssl.present?
      end

      def optional_entries(dashboard)
        optional_entry('CO2_EMISSION_FACTOR', dashboard.co2_emission_factor, 'CO2 emission factor (g/kWh)')
        optional_entry('FRAME_ANCESTORS', dashboard.frame_ancestors, 'Allowed frame ancestors for embedding')
        # An empty UI_THEME is dropped: an unset value already means "user
        # picks the theme", so writing UI_THEME= adds nothing.
        optional_entry('UI_THEME', dashboard.ui_theme, 'UI theme (light, dark, or empty for user choice)')
        optional_entry('LOCKUP_CODEWORD', dashboard.lockup_codeword, 'Codeword for lockup page protection')
        optional_entry('TRUSTED_PROXY_RANGES', dashboard.trusted_proxy_ranges, 'Trusted proxy IP ranges')
        excluded = configuration.excluded_from_house_power.join(',').presence
        optional_entry('INFLUX_EXCLUDE_FROM_HOUSE_POWER', excluded,
                       'Sensors excluded from house power calculation')
      end
    end
  end
end
