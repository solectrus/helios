module Compose
  class ServiceCollection
    include Enumerable

    # Keep in sync with Export::Compose::SERVICE_ORDER (compose.yaml order).
    # HELIOS is handled separately by #sort_key and always appears last in the UI.
    PRIORITY_ORDER = %w[
      dashboard
      influxdb
      ingest
      postgresql
      redis
      senec-collector
      shelly-collector
      mqtt-collector
      forecast-collector
      power-splitter
      traefik
      influxdb-backup
      postgresql-backup
      watchtower
    ].freeze

    def initialize(services_hash)
      @services_hash = services_hash || {}
    end

    def each(&)
      all.each(&)
    end

    def all
      @all ||= @services_hash.map { |name, config| Service.new(name, config) }
    end

    def sorted
      all.sort_by { |service| sort_key(service.name) }
    end

    def find(name)
      config = @services_hash[name.to_s]
      Service.new(name.to_s, config) if config
    end

    def [](name)
      find(name)
    end

    def exists?(name)
      @services_hash.key?(name.to_s)
    end

    def names
      @services_hash.keys
    end

    def count
      @services_hash.size
    end

    delegate :empty?, to: :@services_hash

    private

    def sort_key(name)
      return 2, 0 if name == 'helios'

      priority_index = PRIORITY_ORDER.index(name)
      priority_index ? [0, priority_index] : [1, name]
    end
  end
end
