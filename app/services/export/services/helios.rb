module Export
  module Services
    class Helios < Base
      IMAGE = 'ghcr.io/solectrus/helios:develop'.freeze
      ENVIRONMENT = %w[
        ADMIN_PASSWORD
        SECRET_KEY_BASE
      ].freeze

      def self.service_name
        'helios'
      end

      def self.comment
        'Helios — Configuration management UI'
      end

      def self.enabled?(_configuration)
        !Rails.env.development?
      end

      def to_h
        {
          image: IMAGE,
          environment: ENVIRONMENT,
          volumes: [
            '/opt/solectrus:/data',
            '/var/run/docker.sock:/var/run/docker.sock',
          ],
          ports: ['3999:3000'],
          restart: 'unless-stopped',
        }
      end
    end
  end
end
