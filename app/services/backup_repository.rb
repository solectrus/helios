require 'rubygems/package'

# Facade over the configured backup storage (local filesystem or an external
# host mount). The storage choice is read from `config.yaml.backup.destination`
# at every call so a freshly-saved survey applies immediately without a HELIOS
# restart. All filesystem-aware operations are delegated to the matching
# storage adapter (`Local` or `External`); tar parsing and the data classes
# live here because they are storage-agnostic.
class BackupRepository
  class NotFound < StandardError; end

  # Raised when a storage operation (e.g. an external docker:cli sidecar
  # call) fails. The message carries the underlying tool output so the
  # controller can surface it.
  class Error < StandardError; end

  MAX_BACKUPS = 5
  ERROR_FILENAME = 'error.txt'.freeze
  CONFIG_ENTRY_PATH = 'helios/config.yaml'.freeze

  # Per-backup `<archive>.tar.json` sidecars written by older HELIOS versions.
  # No longer produced; only cleaned up when their backup is deleted/pruned.
  LEGACY_MANIFEST_SUFFIX = '.json'.freeze

  # Capture groups isolate the date (yyyymmdd) and time (hhmmss) digits so a
  # validated filename can be rebuilt from integers — see External#sidecar_path.
  FILENAME_PATTERN = /\Asolectrus-backup-(\d{8})-(\d{6})\.tar\z/
  POSTGRESQL_ENTRY_PATTERN = /\Asolectrus-postgresql-backup-\d{4}-\d{2}-\d{2}\.sql\.gz\z/
  INFLUXDB_ENTRY_PATTERN = /\Asolectrus-influxdb-backup-\d{4}-\d{2}-\d{2}\.tar\.gz\z/

  Entry = Data.define(:name, :bytes)
  ArchiveContents = Data.define(:entries, :config)
  EMPTY_ARCHIVE = ArchiveContents.new(entries: [], config: nil).freeze

  Backup = Data.define(:filename, :bytes, :created_at, :files, :influxdb_image, :postgresql_image) do
    def in_progress? = false

    def to_param = ::File.basename(filename, '.tar')

    def postgresql_bytes
      entry_bytes(POSTGRESQL_ENTRY_PATTERN)
    end

    def influxdb_bytes
      entry_bytes(INFLUXDB_ENTRY_PATTERN)
    end

    private

    def entry_bytes(pattern)
      files.find { |entry| entry.name.match?(pattern) }&.bytes
    end
  end

  InProgress = Data.define(:started_at, :filename) do
    def in_progress? = true
  end

  class << self
    delegate :directory, :host_directory, :all, :find!, :destroy!,
             :error_message, :clear_error!, :prune!, :read_archive_for,
             :download, :mark_pending!, to: :storage

    def valid_filename?(filename)
      filename.to_s.match?(FILENAME_PATTERN)
    end

    # The active storage adapter, picked from configuration at every call.
    # Survey changes therefore take effect immediately, without restarting
    # HELIOS — the external and S3 adapters route every IO through a
    # short-lived sidecar, so they do not depend on any HELIOS bind-mount
    # that would only refresh on container recreation.
    def storage
      case destination
      when 'external' then External
      when 's3' then S3
      else Local
      end
    end

    def destination
      Configuration.current.backup.destination.to_s.presence || ConfigSchema::BACKUP_DEFAULT_DESTINATION
    end

    def local?
      destination == 'local'
    end

    def external?
      destination == 'external'
    end

    def s3?
      destination == 's3'
    end

    # True when the active destination is not the locally mounted backups
    # directory — i.e. when the destination is reached only through a
    # short-lived sidecar (external mount, S3). Used by callers that need
    # to mark a detached run as pending or reject local-only operations.
    def remote?
      !local?
    end

    # AWS credential `-e` docker args forwarded to the detached runners'
    # outer docker:cli container, or [] for non-S3 destinations — keeps
    # credentials out of unrelated runs.
    def s3_env_args
      s3? ? S3.runner_env_args : []
    end

    # Trailing-slash `s3://bucket/prefix/` URI passed to the runner shell
    # scripts, or '' for non-S3 destinations (the scripts ignore it then).
    def s3_dir_uri
      s3? ? S3.s3_dir_uri : ''
    end

    # Reads a tar at an arbitrary local path. Used by `BackupUploader` for
    # validating uploaded tempfiles (which always sit inside the HELIOS
    # container) and by the local adapter for its stored archives.
    def read_archive(path)
      ::File.open(path, 'rb') do |io|
        parse_tar_stream(io)
      end
    rescue Errno::ENOENT, Gem::Package::TarInvalidError
      EMPTY_ARCHIVE
    end

    # Walks a HELIOS backup tar from an IO, capturing every entry plus the
    # parsed `helios/config.yaml`. Shared between local file IO and the
    # external adapter's `docker run cat` pipe — TarReader seeks past file
    # bodies, so this stays cheap even for multi-GB backups.
    def parse_tar_stream(io)
      entries = []
      config = nil

      Gem::Package::TarReader.new(io) do |tar|
        tar.each do |entry|
          next unless entry.file?

          name = entry.full_name.delete_prefix('./')
          entries << Entry.new(name: name, bytes: entry.header.size)
          config = parse_config_yaml(entry.read) if name == CONFIG_ENTRY_PATH
        end
      end

      ArchiveContents.new(entries: entries, config: config)
    end

    # The configured InfluxDB / PostgreSQL image tags from the backed-up
    # `helios/config.yaml`, e.g. "influxdb:2.9-alpine".
    def images_from_config(config)
      { influxdb: config&.dig('influxdb', 'image').presence,
        postgresql: config&.dig('postgresql', 'image').presence }
    end

    def parse_config_yaml(raw)
      YAML.safe_load(raw, permitted_classes: [Date]) || {}
    rescue Psych::Exception
      nil
    end
  end
end
