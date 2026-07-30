require 'open3'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'json'

module Import
  class StackReader
    # Raised when `docker compose config` rejects the stack (malformed YAML,
    # an invalid compose project, etc.).
    class Error < StandardError
      # The `docker compose config` output that caused the failure, stripped
      # of progress/warning noise — safe to show the user verbatim.
      attr_reader :detail

      def initialize(detail)
        @detail = detail
        super("docker compose config failed: #{detail}")
      end
    end

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
      'tibber-collector' => %w[ghcr.io/solectrus/tibber-collector],
      'senec-charger' => %w[ghcr.io/solectrus/senec-charger],
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

    COLLECTOR_SERVICES = %w[senec-collector mqtt-collector shelly-collector forecast-collector].freeze

    # Collectors that need local hardware/network access (vs. the API-based
    # forecast-collector). Their absence — alongside an exposed InfluxDB — is the
    # signal that the device collectors run remotely (dashboard_only mode).
    DEVICE_COLLECTOR_SERVICES = %w[senec-collector mqtt-collector shelly-collector].freeze

    def initialize(compose_path:, env_path:)
      @compose_path = compose_path
      @env_path = env_path
    end

    # Directory the imported stack lives in. Used to decide whether an
    # absolute volume path from .env is equivalent to the default relative
    # bind mount (./service) and can therefore be dropped.
    def stack_dir
      File.dirname(@compose_path)
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

    # Raw (unresolved) compose config parsed from YAML, preserving ${VAR} references.
    # Aliases are allowed (real-world compose files lean on `<<: *anchor` heavily) and
    # the parsed tree is deep-duped so identical sub-hashes from resolved aliases
    # don't share object identity — otherwise YAML.dump would re-emit anchors when
    # downstream consumers persist this data into config.yaml.
    def raw_compose
      @raw_compose ||= (YAML.safe_load_file(@compose_path, permitted_classes: [Symbol], aliases: true) || {}).deep_dup
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
        # ShellyExtractor reads every service with the shelly-collector image
        # directly and merges them into `shelly.devices`. A canonical alias
        # would only duplicate the first instance under two keys.
        next if canonical_name == 'shelly-collector'

        # When multiple services share the same image (e.g. parallel
        # forecast-collector instances per provider, or a second mqtt-collector
        # for ingest), the first one wins the canonical alias — HELIOS re-emits
        # it under the canonical name, while the rest stay in
        # _unmanaged.services with their original names. Order is taken from
        # raw_compose (original YAML insertion order, what the user authored)
        # rather than resolved_services (alphabetized by `docker compose
        # config`), so the user's first-listed service wins.
        first_match = ordered_service_names.find do |name|
          self.class.image_matches?(resolved_services.dig(name, 'image'), prefix)
        end
        result[canonical_name] = resolved_services[first_match] if first_match
      end
    end

    def ordered_service_names
      (raw_compose['services'] || {}).keys
    end

    def resolved_config
      @resolved_config ||= run_compose_config
    end

    # Use JSON format to avoid YAML 1.1 type coercion issues.
    def run_compose_config
      Dir.mktmpdir do |tmpdir|
        FileUtils.cp(@compose_path, File.join(tmpdir, 'compose.yaml'))
        # Normalized copy rather than FileUtils.cp: docker replaces invalid
        # bytes with U+FFFD, so a Latin-1 umlaut in a *value* (a password!)
        # would be imported corrupted here, while raw_env reads it correctly.
        # Extractors mix both sources, so the two have to agree.
        File.write(File.join(tmpdir, '.env'), TextEncoding.utf8(File.read(@env_path))) if File.exist?(@env_path)

        # Without the overrides, HELIOS' own TZ/ADMIN_PASSWORD/SECRET_KEY_BASE
        # would outrank the adopted stack's .env and get imported as if they
        # were the user's values (see Env.spawn_overrides).
        stdout, stderr, status = Open3.capture3(
          ::Env.spawn_overrides(@env_path),
          'docker', 'compose', 'config', '--format', 'json',
          chdir: tmpdir
        )
        raise Error, compose_error(stderr.presence || stdout) unless status.success?

        JSON.parse(stdout)
      end
    end

    # docker emits progress/warning lines (`time=... level=warning ...`) to
    # stderr alongside the actual error; drop them so only the error remains.
    def compose_error(output)
      filtered = output.each_line.reject { |line| line.include?('level=warning') }.join.strip
      filtered.presence || output.strip
    end
  end
end
