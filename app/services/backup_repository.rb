require 'rubygems/package'

# Facade over the configured backup storage (local filesystem, an external
# host mount, or S3). The storage choice is read from
# `config.yaml.backup.destination` at every call so a freshly-saved survey
# applies immediately without a HELIOS restart. All destination-aware
# operations are delegated to the matching adapter (Local / External / S3);
# tar parsing and the data classes live here because they are
# storage-agnostic.
#
# Backup rows are written exactly once when a detached run completes —
# never by retroactive filesystem/S3 scans — and removed only by explicit
# destroy or prune. Destination switches therefore preserve the previous
# list: a user who moves local → S3 → local sees the local list again as
# soon as the destination is switched back.
class BackupRepository
  class NotFound < StandardError; end

  # Raised when a destination IO operation (e.g. a sidecar `rm`) fails.
  # The message carries the underlying tool output so the controller can
  # surface it.
  class Error < StandardError; end

  MAX_BACKUPS = 5
  ERROR_FILENAME = 'error.txt'.freeze
  CONFIG_ENTRY_PATH = 'helios/config.yaml'.freeze

  # Capture groups isolate the date (yyyymmdd) and time (hhmmss) digits so a
  # validated filename can be rebuilt from integers — see External#sidecar_path.
  FILENAME_PATTERN = /\Asolectrus-backup-(\d{8})-(\d{6})\.tar\z/
  POSTGRESQL_ENTRY_PATTERN = /\Asolectrus-postgresql-backup-\d{4}-\d{2}-\d{2}\.sql\.gz\z/
  INFLUXDB_ENTRY_PATTERN = /\Asolectrus-influxdb-backup-\d{4}-\d{2}-\d{2}\.tar\.gz\z/

  Entry = Data.define(:name, :bytes)
  ArchiveContents = Data.define(:entries, :config)
  EMPTY_ARCHIVE = ArchiveContents.new(entries: [], config: nil).freeze

  # `phase` discriminates the detached BackupRunner container (:running,
  # the dump+tar work in the docker:cli sidecar) from the HELIOS-side
  # S3 upload (:uploading, driven by BackupRepository::S3::Uploader).
  # `progress` is a Float 0.0..1.0 during :uploading, nil otherwise.
  InProgress = Data.define(:started_at, :filename, :phase, :progress) do
    def initialize(started_at:, filename:, phase: :running, progress: nil)
      super
    end
  end

  class << self
    delegate :all, :directory, :host_directory, :destroy!, :prune!, :download,
             :mark_pending!, :detect_completion!, :record_backup!,
             :clear_error!, :read_archive_for, to: :storage

    def find!(filename)
      raise NotFound unless valid_filename?(filename)

      storage.find!(filename)
    end

    def error_message(filename = ERROR_FILENAME)
      RunnerLog.message_for(RunnerLog.kind_for(filename))
    end

    def valid_filename?(filename)
      filename.to_s.match?(FILENAME_PATTERN)
    end

    # The active storage adapter, picked from configuration at every call.
    # Survey changes therefore take effect immediately, without restarting
    # HELIOS — external and S3 route every IO through a short-lived
    # sidecar, so they do not depend on any HELIOS bind-mount that would
    # only refresh on container recreation.
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

    def s3? = destination == 's3'

    # True when the active destination is reached only through a short-lived
    # sidecar (external mount, S3) — never the locally mounted backups dir.
    def remote? = destination != 'local'

    # Parses the filename's embedded timestamp as the backup's `created_at`.
    # The filename is produced by BackupRunner with Time.zone, so reading
    # it back as a Time.zone time is consistent end-to-end. Returns nil
    # when the filename does not match the pattern.
    def created_at_from(filename)
      match = filename.to_s.match(FILENAME_PATTERN)
      return nil unless match

      Time.zone.strptime("#{match[1]}-#{match[2]}", '%Y%m%d-%H%M%S')
    rescue ArgumentError
      nil
    end

    def read_archive(path)
      ::File.open(path, 'rb') do |io|
        parse_tar_stream(io)
      end
    rescue Errno::ENOENT, Gem::Package::TarInvalidError
      EMPTY_ARCHIVE
    end

    # TarReader seeks past file bodies, so this stays cheap even for multi-GB
    # backups — only the inner helios/config.yaml is actually read.
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
