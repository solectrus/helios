require 'open3'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'json'

module Import
  class StackReader
    class Error < StandardError; end

    # Canonical HELIOS service name -> image prefix that identifies it.
    # Lets us resolve legacy installations where the user chose different
    # service names (e.g. SOLECTRUS's historic 'app' + 'db' instead of
    # 'dashboard' + 'postgresql').
    SERVICE_IMAGE_PREFIXES = {
      'dashboard' => %w[ghcr.io/solectrus/solectrus],
      'ingest' => %w[ghcr.io/solectrus/ingest],
      'senec-collector' => %w[ghcr.io/solectrus/senec-collector],
      'mqtt-collector' => %w[ghcr.io/solectrus/mqtt-collector],
      'forecast-collector' => %w[ghcr.io/solectrus/forecast-collector],
      'shelly-collector' => %w[ghcr.io/solectrus/shelly-collector],
      'power-splitter' => %w[ghcr.io/solectrus/power-splitter],
      'helios' => %w[ghcr.io/solectrus/helios],
      'postgresql-backup' => %w[ghcr.io/solectrus/postgres-s3-backup ghcr.io/solectrus/postgresql-backup],
      'influxdb-backup' => %w[ghcr.io/solectrus/influxdb2-s3-backup ghcr.io/solectrus/influxdb-backup],
      'postgresql' => %w[postgres],
      'redis' => %w[redis],
      'influxdb' => %w[influxdb],
      # containrrr/watchtower is the historical image; nickfedor/watchtower is
      # the community-maintained fork that many users (and fixtures) have moved to.
      'watchtower' => %w[containrrr/watchtower nickfedor/watchtower],
      'traefik' => %w[traefik],
    }.freeze

    ALL_IMAGE_PREFIXES = SERVICE_IMAGE_PREFIXES.values.flatten.freeze

    def initialize(compose_path:, env_path:)
      @compose_path = compose_path
      @env_path = env_path
    end

    # Full resolved config hash for a single service (image, ports, volumes, healthcheck, restart, etc.).
    # Falls back to image-based lookup so legacy service names (e.g. 'app') resolve
    # to their canonical counterparts.
    def service(name)
      services[name]
    end

    # All resolved services as { name => config_hash }, including canonical aliases
    # for services identified by image.
    def services
      @services ||= resolved_services.merge(aliased_services)
    end

    # Returns true if the given image (from a compose service) matches any of
    # HELIOS's known service images.
    def self.managed_image?(image)
      return false if image.nil?

      ALL_IMAGE_PREFIXES.any? { |prefix| image_matches_prefix?(image, prefix) }
    end

    # Matches an image against one prefix or an array of prefixes, respecting
    # the ':tag' / '@digest' boundary — so 'postgres' matches 'postgres:16-alpine'
    # but not 'ghcr.io/.../postgresql-backup'.
    def self.image_matches?(image, prefix_or_prefixes)
      Array(prefix_or_prefixes).any? { |prefix| image_matches_prefix?(image, prefix) }
    end

    def self.image_matches_prefix?(image, prefix)
      image = image.to_s
      image == prefix || image.start_with?("#{prefix}:", "#{prefix}@")
    end
    private_class_method :image_matches_prefix?

    # Raw (unresolved) compose config parsed from YAML, preserving ${VAR} references
    def raw_compose
      @raw_compose ||= YAML.safe_load_file(@compose_path, permitted_classes: [Symbol]) || {}
    end

    # Raw environment variables from .env file (unresolved, preserving original values)
    def raw_env
      @raw_env ||= Env::File.load(@env_path)
    end

    private

    def resolved_services
      resolved_config['services'] || {}
    end

    def aliased_services
      SERVICE_IMAGE_PREFIXES.each_with_object({}) do |(canonical_name, prefix), result|
        next if resolved_services.key?(canonical_name)

        matches = resolved_services.select { |_, cfg| self.class.image_matches?(cfg['image'], prefix) }
        # Only alias when exactly one candidate exists — ambiguous matches (e.g. multiple
        # shelly-collector services) are resolved by image-walking callers instead.
        result[canonical_name] = matches.values.first if matches.size == 1
      end
    end

    def resolved_config
      @resolved_config ||= run_compose_config
    end

    # Use JSON format to avoid YAML 1.1 type coercion issues.
    def run_compose_config
      Dir.mktmpdir do |tmpdir|
        FileUtils.cp(@compose_path, File.join(tmpdir, 'compose.yaml'))
        FileUtils.cp(@env_path, File.join(tmpdir, '.env'))

        stdout, stderr, status = Open3.capture3(
          'docker', 'compose', 'config', '--format', 'json',
          chdir: tmpdir
        )
        raise Error, "docker compose config failed: #{stderr.presence || stdout}" unless status.success?

        JSON.parse(stdout)
      end
    end
  end
end
