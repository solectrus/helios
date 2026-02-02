module Compose
  class Service
    DISPLAY_NAMES = {
      'postgres' => 'PostgreSQL',
      'redis' => 'Redis',
      'influxdb' => 'InfluxDB',
      'ghcr.io/solectrus/solectrus' => 'SOLECTRUS',
      'nickfedor/watchtower' => 'Watchtower',
      'amir20/dozzle' => 'Dozzle',
    }.freeze

    attr_reader :name, :config

    def initialize(name, config)
      @name = name
      @config = config || {}
    end

    def image
      config['image']
    end

    def image_name
      image&.split(':')&.first
    end

    def image_tag
      return nil unless image

      tag = image.split(':').last
      tag == image ? 'latest' : tag
    end

    def display_name
      DISPLAY_NAMES[image_name] || name
    end

    def helios?
      image_name&.end_with?('/helios') || image_name == 'helios'
    end

    def ports
      config['ports'] || []
    end

    def public_port
      return nil unless ports.any?

      first_port = ports.first
      case first_port
      when String
        first_port.split(':').first.to_i
      when Hash
        first_port['published']&.to_i
      end
    end

    def environment
      config['environment'] || {}
    end

    def volumes
      config['volumes'] || []
    end

    def depends_on
      config['depends_on'] || {}
    end

    def restart
      config['restart']
    end

    def healthcheck
      config['healthcheck']
    end

    def to_h
      config.dup
    end
  end
end
