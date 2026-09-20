module Export
  class Env
    # Only the names the generated Traefik service reads back. APP_DOMAIN is
    # gone entirely: the routers carry the domain in the host rule itself (see
    # Export::Services::Dashboard), and the import reads it back from there, so
    # nothing ever read the variable.
    class ReverseProxy < Section
      def call
        referenced = Services::Traefik.env_references(configuration)
        return if referenced.empty?

        env.add_section('Reverse Proxy (Traefik)')

        if referenced.include?('LETSENCRYPT_EMAIL')
          entry('LETSENCRYPT_EMAIL', Services::Traefik.letsencrypt_email(configuration),
                "Email for Let's Encrypt certificate notifications")
        end

        return unless referenced.include?(Services::Traefik.volume_env_key)

        volume_path_entry(Services::Traefik, "Let's Encrypt certificates")
      end
    end
  end
end
