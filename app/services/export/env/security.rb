module Export
  class Env
    class Security < Section
      def call
        env.add_section('Security')
        entry('ADMIN_PASSWORD', configuration.system.admin_password,
              'Admin password — shared by Dashboard and HELIOS')
        entry('SECRET_KEY_BASE', configuration.system.secret_key_base,
              'Secret key for Rails sessions — shared by Dashboard and HELIOS')
      end
    end
  end
end
