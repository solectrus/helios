module ConfigurationMigrations
  # Collapses the two fields that named the same machine onto one.
  #
  # `app_host` held the address SOLECTRUS is reached at, `app_domain` the
  # domain a HELIOS-managed Traefik answers on. `app_host` is the one that
  # stays, and the domain wins where both are set: the domain is the address
  # the stack answers on, while app_host was filled from the browser at the
  # first start and holds the address of the machine on the local network.
  #
  # Wherever the stack predates the stored `mode` field, the mode was derived
  # from what the section held: an app_domain meant the managed Traefik, a
  # bind_ip alone meant an external one. Both halves are written out here, so
  # that `mode` answers on its own from now on.
  class MergeAppDomain < Base
    version 7

    def up(data)
      reverse_proxy = data['reverse_proxy']
      reverse_proxy = {} unless reverse_proxy.is_a?(Hash)

      domain = reverse_proxy.delete('app_domain')

      if domain.present?
        adopt_domain(data, reverse_proxy, domain)
      else
        derive_external_mode(data, reverse_proxy)
      end

      data['reverse_proxy'] = reverse_proxy if reverse_proxy.present?
      data
    end

    private

    # A managed Traefik: the domain it answers on becomes the one address, and
    # the mode the field used to imply is written out.
    #
    # The mode follows the address rather than the section, because Traefik
    # routes by host rule and a rule with nothing in it matches nothing. Where
    # the domain drops out and nothing else names the machine, the stack
    # therefore keeps no proxy it cannot run (see
    # Configuration#reverse_proxy_managed?).
    def adopt_domain(data, reverse_proxy, domain)
      host = HostAddress.public_host(domain)
      (data['system'] ||= {})['app_host'] = host if host

      reverse_proxy['mode'] ||= 'internal' if stored_app_host(data).present?
    end

    def stored_app_host(data)
      system = data['system']

      system['app_host'] if system.is_a?(Hash)
    end

    # An external proxy. Two marks name one before the mode was stored: ports
    # bound to a single host IP, and the HTTPS flag the dashboard carries for a
    # proxy that terminates TLS in front of the stack. The flag is the only
    # mark an nginx or an Apache leaves behind, and the form shows it in the
    # external mode alone, so a stack that keeps no mode here loses the flag on
    # the first save and the login behind the proxy fails.
    def derive_external_mode(data, reverse_proxy)
      return if reverse_proxy['mode'].present?
      return if reverse_proxy['bind_ip'].blank? && !force_ssl?(data)

      reverse_proxy['mode'] = 'external'
    end

    def force_ssl?(data)
      dashboard = data['dashboard']
      return false unless dashboard.is_a?(Hash)

      ActiveModel::Type::Boolean.new.cast(dashboard['force_ssl'])
    end
  end
end
