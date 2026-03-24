module Export
  module Services
    class Helios < Base
      IMAGE = 'ghcr.io/solectrus/helios:develop'.freeze
      ENVIRONMENT = [
        'ADMIN_PASSWORD',
        'SECRET_KEY_BASE',
        'HELIOS_STACK_PATH=/opt/solectrus',
        'HELIOS_HOST_STACK_PATH',
      ].freeze

      def self.service_name
        'helios'
      end

      def self.comment
        'Helios — Configuration management UI'
      end

      def to_h
        {
          image: IMAGE,
          user: 'root',
          environment: ENVIRONMENT,
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
