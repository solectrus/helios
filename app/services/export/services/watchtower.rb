module Export
  module Services
    class Watchtower < Base
      def self.service_name
        'watchtower'
      end

      def self.comment
        'Watchtower — Automatic Docker image updates'
      end

      def to_h
        {
          image: configuration.watchtower.image,
          environment: ['TZ'],
          volumes: ['/var/run/docker.sock:/var/run/docker.sock'],
          command: '--scope solectrus --cleanup',
          restart: 'unless-stopped',
          healthcheck: healthcheck('CMD', '/watchtower', '--health-check', start_period: '10s'),
        }
      end
    end
  end
end
