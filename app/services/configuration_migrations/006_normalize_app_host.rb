module ConfigurationMigrations
  # Brings app_host to the form the configuration holds now: the host alone.
  #
  # The field takes the address other devices reach SOLECTRUS at, and a user
  # pastes what the browser showed them. Nothing trimmed that value before, so
  # it could carry a scheme, a port or a path, and every reader that builds an
  # address from it produced one that reaches nothing: the link to the
  # dashboard, the endpoint external sources write to, the host rule of an
  # external Traefik. HostAddress.normalize runs on every write now, and this
  # catches what an earlier HELIOS stored.
  #
  # An address that reaches only whoever asks is dropped instead of trimmed.
  # Such a value arrived on its own: the field used to be prefilled from the
  # browser's address bar without a check, so an installation set up while
  # HELIOS itself was reached at `localhost` (or at a `*.localhost` name, or
  # through an SSH tunnel) stored that name. The field refuses one now. Left in
  # place, a value the user never typed would turn into an error the moment the
  # form opens, and the section would stay unsaveable until they clear it by
  # hand. Configuration#adopt_request_host! fills the field again from the next
  # request that carries a routable host, and until then every caller names the
  # published port alone.
  class NormalizeAppHost < Base
    version 6

    def up(data)
      system = data['system']
      return data unless system.is_a?(Hash) && system.key?('app_host')

      host = HostAddress.normalize(system['app_host'])

      if host && !HostAddress.loopback?(host)
        system['app_host'] = host
      else
        system.delete('app_host')
      end

      data
    end
  end
end
