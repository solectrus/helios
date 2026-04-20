module Compose
  class Service
    DISPLAY_NAMES = {
      'dashboard' => 'SOLECTRUS',
      'forecast-collector' => 'Forecast-Collector',
      'helios' => 'HELIOS',
      'influxdb' => 'InfluxDB',
      'influxdb-backup' => 'InfluxDB-Backup',
      'ingest' => 'Ingest',
      'mqtt-collector' => 'MQTT-Collector',
      'postgresql' => 'PostgreSQL',
      'postgresql-backup' => 'PostgreSQL-Backup',
      'power-splitter' => 'Power-Splitter',
      'redis' => 'Redis',
      'senec-collector' => 'SENEC-Collector',
      'shelly-collector' => 'Shelly-Collector',
      'traefik' => 'Traefik',
      'watchtower' => 'Watchtower',
    }.freeze

    def self.display_name_for(service_name)
      DISPLAY_NAMES[service_name] || service_name
    end

    attr_reader :name, :config

    def initialize(name, config)
      @name = name
      @config = config || {}
    end

    def image
      Compose.normalize_image(config['image'])
    end

    def image_name
      image&.split(':')&.first
    end

    def image_tag
      image&.split(':')&.last
    end

    def display_name
      self.class.display_name_for(name)
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
