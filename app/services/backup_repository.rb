require 'rubygems/package'

class BackupRepository
  class NotFound < StandardError; end

  MAX_BACKUPS = 5
  ERROR_FILENAME = 'error.txt'.freeze
  CONFIG_ENTRY_PATH = 'helios/config.yaml'.freeze

  # Per-backup `<archive>.tar.json` sidecars written by older HELIOS versions.
  # No longer produced; only cleaned up when their backup is deleted/pruned.
  LEGACY_MANIFEST_SUFFIX = '.json'.freeze

  FILENAME_PATTERN = /\Asolectrus-backup-\d{8}-\d{6}\.tar\z/
  POSTGRESQL_ENTRY_PATTERN = /\Asolectrus-postgresql-backup-\d{4}-\d{2}-\d{2}\.sql\.gz\z/
  INFLUXDB_ENTRY_PATTERN = /\Asolectrus-influxdb-backup-\d{4}-\d{2}-\d{2}\.tar\.gz\z/

  Entry = Data.define(:name, :bytes)
  ArchiveContents = Data.define(:entries, :config)

  Backup = Data.define(:filename, :path, :bytes, :created_at, :files, :influxdb_image, :postgresql_image) do
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
    def all
      backup_paths_with_stats.map { |path, stat| backup_for(path, stat) }
    end

    def find!(filename)
      path = path_for(filename)
      backup_for(path, ::File.stat(path))
    rescue Errno::ENOENT
      raise NotFound
    end

    def valid_filename?(filename)
      filename.to_s.match?(FILENAME_PATTERN)
    end

    def destroy!(filename)
      path = path_for(filename)
      raise NotFound unless ::File.exist?(path)

      FileUtils.rm_f(path)
      FileUtils.rm_f("#{path}#{LEGACY_MANIFEST_SUFFIX}")
    end

    def directory
      ::File.join(Rails.configuration.data_path, 'helios', 'backups')
    end

    # Host-side equivalent of `directory`. Bind-mount sources for the docker
    # runners must be host paths even when HELIOS itself sees a different
    # container-internal mount.
    def host_directory
      ::File.join(Orchestration::Runner.host_data_path, 'helios', 'backups')
    end

    # Walks a HELIOS backup tar, capturing every entry plus the parsed
    # `helios/config.yaml`. Backs `.all` (file list + image versions) and
    # RestoreRunner / BackupUploader archive validation. TarReader seeks past
    # file bodies, so this stays cheap even for multi-GB backups.
    def read_archive(path)
      entries = []
      config = nil

      ::File.open(path, 'rb') do |io|
        Gem::Package::TarReader.new(io) do |tar|
          tar.each do |entry|
            next unless entry.file?

            name = entry.full_name.delete_prefix('./')
            entries << Entry.new(name: name, bytes: entry.header.size)
            config = parse_config_yaml(entry.read) if name == CONFIG_ENTRY_PATH
          end
        end
      end

      ArchiveContents.new(entries: entries, config: config)
    rescue Errno::ENOENT, Gem::Package::TarInvalidError
      ArchiveContents.new(entries: [], config: nil)
    end

    def error_message(filename = ERROR_FILENAME)
      ::File.read(::File.join(directory, filename)).strip.presence
    rescue Errno::ENOENT
      nil
    end

    def clear_error!(filename = ERROR_FILENAME)
      FileUtils.rm_f(::File.join(directory, filename))
    end

    def prune!(keep: MAX_BACKUPS - 1)
      backup_paths_with_stats.drop(keep).each do |(path, _stat)|
        FileUtils.rm_f(path)
        FileUtils.rm_f("#{path}#{LEGACY_MANIFEST_SUFFIX}")
      end
    end

    private

    def path_for(filename)
      raise NotFound unless filename.match?(FILENAME_PATTERN)

      ::File.join(directory, filename)
    end

    def backup_paths_with_stats
      return [] unless Dir.exist?(directory)

      Dir.children(directory)
         .grep(FILENAME_PATTERN)
         .map { |filename| ::File.join(directory, filename) }
         .map { |path| [path, ::File.stat(path)] }
         .sort_by { |path, stat| [stat.mtime, ::File.basename(path)] }
         .reverse
    end

    # File list, sizes and image versions all come straight from the archive.
    def backup_for(path, stat)
      archive = read_archive(path)
      images = images_from_config(archive.config)

      Backup.new(
        filename: ::File.basename(path),
        path: path,
        bytes: stat.size,
        created_at: stat.mtime.in_time_zone,
        files: archive.entries,
        influxdb_image: images[:influxdb],
        postgresql_image: images[:postgresql],
      )
    end

    # The configured InfluxDB / PostgreSQL image tags from the backed-up
    # `helios/config.yaml`, e.g. "influxdb:2.9-alpine".
    def images_from_config(config)
      { influxdb: config&.dig('influxdb', 'image').presence, postgresql: config&.dig('postgresql', 'image').presence }
    end

    def parse_config_yaml(raw)
      YAML.safe_load(raw, permitted_classes: [Date]) || {}
    rescue Psych::Exception
      nil
    end
  end
end
