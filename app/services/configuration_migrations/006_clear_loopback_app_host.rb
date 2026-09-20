module ConfigurationMigrations
  # Drops an app_host that names the machine to itself alone.
  #
  # The field holds the address at which other devices reach SOLECTRUS, but it
  # used to be prefilled from the browser's address bar without a check. An
  # installation set up while HELIOS itself was reached at `localhost` (or at a
  # `*.localhost` name, or through an SSH tunnel) stored that name, and every
  # address derived from it pointed back at whoever asked: the link to the
  # dashboard, the endpoint external sources write to, the host rule of an
  # external Traefik.
  #
  # The field refuses such a name now. Left in place, a value the user never
  # typed would turn into an error the moment the form opens, and the whole
  # section would stay unsaveable until they clear it by hand. So it goes here
  # instead. Configuration#adopt_request_host! fills the field again from the
  # next request that carries a routable host, and until then every caller
  # names the published port alone.
  class ClearLoopbackAppHost < Base
    version 6

    def up(data)
      system = data['system']
      return data unless system.is_a?(Hash) && Loopback.host?(system['app_host'])

      system.delete('app_host')
      data
    end
  end
end
