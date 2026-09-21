module Compose
  class Service
    DISPLAY_NAMES = {
      'dashboard' => 'Dashboard',
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
      published_host_ports.first
    end

    # Every host port the service publishes, in the order compose lists them.
    #
    # A published port carries an optional bind address in front of it
    # (`10.0.0.5:3999:3000`, `[::1]:3999:3000`), an optional protocol behind it
    # (`3999:3000/udp`), and it can name the container port alone (`3000`),
    # which publishes nothing on the host. So the host port is the second field
    # from the end, and it is there only where a field follows it.
    def published_host_ports
      ports.filter_map { |entry| host_port_of(entry) }
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

    private

    def host_port_of(entry)
      case entry
      when Hash then entry['published']&.to_i
      else host_port_of_string(entry.to_s)
      end
    end

    def host_port_of_string(entry)
      fields = entry.split('/', 2).first.to_s.sub(/\A\[[^\]]*\]:/, '').split(':')
      return if fields.size < 2

      fields[-2].to_i
    end
  end
end
