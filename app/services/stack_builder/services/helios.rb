class StackBuilder
  module Services
    class Helios < Base
      def self.service_name
        'helios'
      end

      def self.comment
        'Configuration management UI'
      end

      def to_h
        {
          image: configuration.system.helios_image,
          user: 'root',
          environment: {
            'SECRET_KEY_BASE' => '${SECRET_KEY_BASE}',
            'HELIOS_STACK_PATH' => '/opt/solectrus',
            'HELIOS_HOST_STACK_PATH' => '${HELIOS_HOST_STACK_PATH}',
          },
          volumes: [
            '${HELIOS_HOST_STACK_PATH}:/opt/solectrus',
            '/var/run/docker.sock:/var/run/docker.sock',
          ],
          ports: ['3999:3000'],
          restart: 'unless-stopped',
        }
      end
    end
  end
end
