module Export
  class Env
    class Section
      def initialize(env, configuration)
        @env = env
        @configuration = configuration
      end

      private

      attr_reader :env, :configuration

      def entry(key, value, comment)
        env.add_comment(comment)
        env[key] = value
        env.add_blank_line
      end

      def optional_entry(key, value, comment)
        entry(key, value, comment) if value.present?
      end

      def volume_path_entry(service_class, label)
        section = configuration.public_send(service_class.config_keys.first)
        host_path = service_class.default_host_volume_path(section)
        entry(service_class.volume_env_key, host_path, "Volume path for storing the #{label}")
      end
    end
  end
end
