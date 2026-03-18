class StackBuilder
  module Services
    class Watchtower < Base
      def self.service_name
        'watchtower'
      end

      def self.comment
        'Automatic Docker image updates'
      end

      def to_h
        {
          image: system_data.watchtower_image || 'nickfedor/watchtower',
          environment: ['TZ'],
          volumes: ['/var/run/docker.sock:/var/run/docker.sock'],
          command: '--scope solectrus --cleanup',
          restart: 'unless-stopped',
          logging: { options: { 'max-size' => '10m', 'max-file' => '3' } },
          labels: ['com.centurylinklabs.watchtower.scope=solectrus'],
        }
      end
    end
  end
end
