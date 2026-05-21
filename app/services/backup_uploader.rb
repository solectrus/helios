# Stores a tar archive uploaded by the user as a regular HELIOS backup.
# The file is validated to look like a HELIOS backup (PostgreSQL dump,
# InfluxDB dump, helios/config.yaml) before it is moved into the backups
# directory.
class BackupUploader
  class Error < StandardError; end

  MAX_BYTES = 5 * 1024 * 1024 * 1024 # 5 GB

  class << self
    delegate :start, to: :new
  end

  def start(uploaded_file)
    @uploaded_file = uploaded_file
    validate_runtime!
    validate_upload!

    target_filename = pick_filename
    target_path = ::File.join(BackupRepository.directory, target_filename)
    raise Error, error(:already_exists) if ::File.exist?(target_path)

    BackupRepository.prune!
    BackupRepository.clear_error!
    persist!(target_path)
  end

  private

  attr_reader :uploaded_file

  def error(key, **)
    I18n.t("backups.uploader.errors.#{key}", **)
  end

  def validate_runtime!
    # Upload writes directly into HELIOS's own backups dir; for a non-local
    # destination the tar would land in the wrong place and never show up in
    # the listing. The workaround (place the file at the destination
    # manually, or switch the destination back to local) is documented in
    # the message.
    raise Error, error(:remote_destination) if BackupRepository.remote?
    raise Error, error(:backup_in_progress) if BackupRunner.in_progress
    raise Error, error(:restore_in_progress) if RestoreRunner.in_progress
  end

  def validate_upload!
    validate_metadata!
    validate_archive!
  end

  def validate_metadata!
    raise Error, error(:missing) if uploaded_file.blank?
    raise Error, error(:not_tar) unless uploaded_file.original_filename.to_s.downcase.end_with?('.tar')
    raise Error, error(:too_large) if uploaded_file.size.to_i > MAX_BYTES
    raise Error, error(:invalid_archive) unless ustar_archive?
  end

  def validate_archive!
    @archive = BackupRepository.read_archive(uploaded_file.tempfile.path)
    raise Error, error(:invalid_archive) if @archive.entries.empty?
    raise Error, error(:missing_postgres) unless entry_matches?(BackupRepository::POSTGRESQL_ENTRY_PATTERN)
    raise Error, error(:missing_influx) unless entry_matches?(BackupRepository::INFLUXDB_ENTRY_PATTERN)
    raise Error, error(:missing_config) if @archive.config.blank?
  end

  # Posix tar headers carry "ustar" at offset 257. We reject anything without
  # it — an older v7 tar would slip through, but `Gem::Package::TarWriter`
  # (which produced every legitimate HELIOS backup) always writes the ustar
  # magic, so anything else is much more likely to be junk than a real backup.
  def ustar_archive?
    ::File.open(uploaded_file.tempfile.path, 'rb') do |io|
      io.seek(257)
      io.read(5) == 'ustar'
    end
  rescue Errno::ENOENT
    false
  end

  def entry_matches?(pattern)
    @archive.entries.any? { |entry| entry.name.match?(pattern) }
  end

  def pick_filename
    candidate = uploaded_file.original_filename.to_s
    return candidate if BackupRepository.valid_filename?(candidate)

    "solectrus-backup-#{Time.current.strftime('%Y%m%d-%H%M%S')}.tar"
  end

  def persist!(target_path)
    FileUtils.mkdir_p(BackupRepository.directory)
    part_path = "#{target_path}.part"

    FileUtils.mv(uploaded_file.tempfile.path, part_path)
    ::File.rename(part_path, target_path)
    apply_mtime_from_filename!(target_path)
  rescue SystemCallError => e
    FileUtils.rm_f(part_path) if part_path
    raise Error, error(:write_failed, message: e.message)
  end

  # The list view sorts by mtime and shows it as the backup's creation date,
  # so the file's mtime must match the timestamp baked into the filename
  # rather than the time of the upload.
  def apply_mtime_from_filename!(target_path)
    match = ::File.basename(target_path).match(/(\d{8})-(\d{6})/)
    return unless match

    timestamp = Time.zone.strptime("#{match[1]}-#{match[2]}", '%Y%m%d-%H%M%S').to_i
    ::File.utime(timestamp, timestamp, target_path)
  rescue ArgumentError
    nil
  end
end
