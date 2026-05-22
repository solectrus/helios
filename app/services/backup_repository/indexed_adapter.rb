class BackupRepository
  # Index-query layer shared by every storage adapter (Local, External, S3).
  # The /backups page renders from the JSON index instead of re-reading
  # archives on each visit; this module holds the read/query half, which is
  # identical across all three adapters.
  #
  # Including adapters must provide: `ensure_index_fresh!`, `cache_fresh?`,
  # `read_index`, `read_archive_for` and `destination_configured?`.
  module IndexedAdapter
    # Tar-sidecar text files an adapter tracks: their contents surface as
    # the backup / restore failure banner. Keyed by on-disk filename,
    # valued by the index field the text is stored under.
    ERROR_FILES = {
      BackupRepository::ERROR_FILENAME => 'error_message',
      RestoreRunner::ERROR_FILENAME => 'restore_error_message',
    }.freeze

    def all
      ensure_index_fresh!
      deserialize_backups(read_index['backups'])
    end

    def find!(filename)
      raise BackupRepository::NotFound unless BackupRepository.valid_filename?(filename)

      ensure_index_fresh!
      raw = read_index['backups'].find { |entry| entry['filename'] == filename }
      raise BackupRepository::NotFound unless raw

      deserialize_backup(raw)
    end

    def error_message(filename = BackupRepository::ERROR_FILENAME)
      return nil unless destination_configured?

      index_key = error_files[filename]
      return nil unless index_key

      ensure_index_fresh!
      read_index[index_key].presence
    end

    # True when the cached index already matches the configured destination.
    # A cheap, Docker-free check — it only reads the index file. False means
    # the next listing would trigger a (for remote destinations slow) refresh;
    # the /backups page consults this to decide whether to defer that refresh
    # behind a loading spinner.
    def index_fresh?
      cache_fresh?
    end

    private

    # Instance-method accessor for ERROR_FILES so methods mixed in from a
    # sibling module (SidecarAdapter) can reach it without tripping over
    # Ruby's lexical constant lookup.
    def error_files
      ERROR_FILES
    end

    def deserialize_backups(raw_entries)
      Array(raw_entries).map { |raw| deserialize_backup(raw) }
    end

    def deserialize_backup(raw)
      BackupRepository::Backup.new(
        filename: raw['filename'],
        bytes: raw['bytes'],
        created_at: Time.zone.parse(raw['mtime']),
        files: Array(raw['files']).map do |file|
          BackupRepository::Entry.new(name: file['name'], bytes: file['bytes'])
        end,
        influxdb_image: raw['influxdb_image'],
        postgresql_image: raw['postgresql_image'],
      )
    end

    # Rebuilds the index entry list, reusing cached entries whose size and
    # mtime are unchanged since the last refresh. A cached entry with empty
    # `files` is always rebuilt: empty files means a previous metadata read
    # failed, and size+mtime alone would otherwise pin that failure forever.
    def merge_with_cache(listing)
      previous = (Index.read || {}).fetch('backups', []).index_by { |entry| entry['filename'] }
      listing.map { |meta| reuse_or_build(meta, previous[meta[:filename]]) }
    end

    def reuse_or_build(meta, cached)
      return build_entry(meta) unless cached
      return build_entry(meta) unless cached['bytes'] == meta[:bytes]
      return build_entry(meta) unless cached['mtime'] == meta[:mtime].iso8601
      return build_entry(meta) if Array(cached['files']).empty?

      cached
    end

    # False when any index entry has empty `files` — the trace of a failed
    # metadata read (see reuse_or_build), e.g. an S3 object not yet readable
    # in the moments right after upload. The `cache_fresh?` of every adapter
    # consults this, so the next /backups visit re-reads the archive and the
    # broken entry heals itself instead of staying empty until the next
    # unrelated refresh.
    def index_complete?(index)
      Array(index['backups']).all? { |entry| Array(entry['files']).any? }
    end

    # Reads one archive's metadata (entry list + image versions) into an
    # index entry. The External adapter overrides this: streaming a whole
    # tar over the docker socket just to read a 10 KB config would be
    # wasteful, so it uses a `tar -tvf` sidecar instead.
    def build_entry(meta)
      archive = read_archive_for(meta[:filename])
      images = BackupRepository.images_from_config(archive.config)
      {
        'filename' => meta[:filename],
        'bytes' => meta[:bytes],
        'mtime' => meta[:mtime].iso8601,
        'files' => archive.entries.map { |entry| { 'name' => entry.name, 'bytes' => entry.bytes } },
        'influxdb_image' => images[:influxdb],
        'postgresql_image' => images[:postgresql],
      }
    end
  end
end
