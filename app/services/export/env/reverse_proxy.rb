module Export
  class Env
    class ReverseProxy < Section
      def call
        env.add_section('Reverse Proxy (Traefik)')
        entry('APP_DOMAIN', configuration.reverse_proxy.app_domain,
              'Domain for HTTPS access via Traefik')
        entry('LETSENCRYPT_EMAIL', Services::Traefik.letsencrypt_email(configuration),
              "Email for Let's Encrypt certificate notifications")
        volume_path_entry(Services::Traefik, "Let's Encrypt certificates")
      end
    end
  end
end
