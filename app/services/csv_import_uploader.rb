# Accepts either a ZIP of CSV exports (SENEC, Sungrow, SolarEdge) or a
# single bare CSV file and stages it where the csv-importer container
# reads it via bind mount.
#
# ZIP path: HELIOS validates the archive, extracts CSVs (recursively,
# preserving subfolders) into `<data>/helios/csv-imports/extracted/` and
# keeps the original at `<data>/helios/csv-imports/upload.zip` until the
# import has run. CSV path (intended for quick tests of a single file):
# skip the archive intermediate and drop the file straight into the
# extract directory under its basename. Either way CsvImportRunner.start
# then bind-mounts the extract directory as `/data` into the importer.
#
# Zip-Slip and zip-bomb protection are mandatory here: a 50 KB hostile
# archive could otherwise overwrite arbitrary files or fill the disk.
class CsvImportUploader
  class Error < StandardError; end

  MAX_UPLOAD_BYTES = 100 * 1024 * 1024 # 100 MB upload cap (covers ZIP and bare CSV)
  MAX_EXTRACTED_BYTES = 1024 * 1024 * 1024 # 1 GB extract cap (zip-bomb guard)
  UPLOAD_FILENAME = 'upload.zip'.freeze
  EXTRACT_DIRNAME = 'extracted'.freeze
  STAGING_DIRNAME = 'csv-imports'.freeze
  ZIP_EXTENSION = '.zip'.freeze
  CSV_EXTENSION = '.csv'.freeze
  ALLOWED_EXTENSIONS = [ZIP_EXTENSION, CSV_EXTENSION].freeze

  class << self
    delegate :start, to: :new

    def staging_directory
      ::File.join(Rails.configuration.data_path, 'helios', STAGING_DIRNAME)
    end

    def host_staging_directory
      ::File.join(Orchestration::Runner.host_data_path, 'helios', STAGING_DIRNAME)
    end

    def upload_path
      ::File.join(staging_directory, UPLOAD_FILENAME)
    end

    def extract_directory
      ::File.join(staging_directory, EXTRACT_DIRNAME)
    end

    def host_extract_directory
      ::File.join(host_staging_directory, EXTRACT_DIRNAME)
    end

    def cleanup!
      FileUtils.rm_f(upload_path)
      FileUtils.rm_rf(extract_directory)
    end
  end

  def start(uploaded_file)
    @uploaded_file = uploaded_file
    validate_metadata!

    self.class.cleanup!
    FileUtils.mkdir_p(self.class.staging_directory)

    if csv_upload?
      store_csv!
    else
      persist_zip!
      validate_archive!
      extract!
    end

    grant_importer_read_access!
  rescue Error
    self.class.cleanup!
    raise
  end

  private

  attr_reader :uploaded_file

  # The csv-importer image runs as a non-root user (`USER app`). HELIOS runs
  # as root, so the files it stages inherit root ownership and a mode that
  # depends on the ambient umask — and a moved Rack tempfile even keeps its
  # restrictive 0600 mode. Inside the read-only bind mount the importer's UID
  # then either cannot list the directory (`Dir.glob` returns nothing, logged
  # as "Imported 0 files") or cannot open the file (EACCES). Widen the whole
  # extract tree to world-readable, directories also traversable (`X` adds
  # execute only to directories). The tree is HELIOS' private, transient
  # staging area holding user-supplied CSVs, so this is harmless. Issue #233.
  def grant_importer_read_access!
    FileUtils.chmod_R('a+rX', self.class.extract_directory)
  end

  def error(key, **)
    I18n.t("csv_imports.uploader.errors.#{key}", **)
  end

  def validate_metadata!
    raise Error, error(:missing) if uploaded_file.blank?
    raise Error, error(:invalid_extension) unless ALLOWED_EXTENSIONS.include?(upload_extension)
    raise Error, error(:too_large) if uploaded_file.size.to_i > MAX_UPLOAD_BYTES
  end

  def upload_extension
    ::File.extname(uploaded_file.original_filename.to_s).downcase
  end

  def csv_upload?
    upload_extension == CSV_EXTENSION
  end

  # Single-CSV path: write straight into the extract dir under the
  # sanitized basename of the upload, so the importer log echoes the
  # user's filename instead of an opaque placeholder.
  def store_csv!
    FileUtils.mkdir_p(self.class.extract_directory)
    destination = ::File.join(self.class.extract_directory, csv_destination_basename)
    FileUtils.mv(uploaded_file.tempfile.path, destination)
  rescue SystemCallError => e
    raise Error, error(:write_failed, message: e.message)
  end

  def csv_destination_basename
    ::File.basename(uploaded_file.original_filename.to_s).presence || 'upload.csv'
  end

  def persist_zip!
    FileUtils.mv(uploaded_file.tempfile.path, self.class.upload_path)
  rescue SystemCallError => e
    raise Error, error(:write_failed, message: e.message)
  end

  # Quick structural check on the uploaded archive — confirms it parses as
  # a ZIP and contains at least one .csv anywhere in the tree.
  def validate_archive!
    Zip::File.open(self.class.upload_path) do |zip|
      raise Error, error(:no_csv) unless zip.any? { |entry| entry.file? && csv_entry?(entry.name) }
    end
  rescue Zip::Error
    raise Error, error(:invalid_zip)
  end

  def extract!
    target_root = self.class.extract_directory
    FileUtils.mkdir_p(target_root)
    written = 0

    Zip::File.open(self.class.upload_path) do |zip|
      zip.each do |entry|
        next unless extractable?(entry)

        written = extract_with_cap!(entry, target_root, written)
      end
    end
  rescue Zip::Error => e
    raise Error, error(:extract_failed, message: e.message)
  end

  # Enforces MAX_EXTRACTED_BYTES both on the declared size (cheap pre-check
  # against an honest archive) AND on the actual bytes streamed (mid-stream
  # cap against a malicious archive that lies in its central directory).
  def extract_with_cap!(entry, target_root, written)
    raise Error, error(:too_large_extracted) if written + entry.size.to_i > MAX_EXTRACTED_BYTES

    written + extract_entry!(entry, target_root, budget: MAX_EXTRACTED_BYTES - written)
  end

  def extractable?(entry)
    entry.file? && csv_entry?(entry.name)
  end

  def extract_entry!(entry, target_root, budget:)
    destination = safe_destination!(target_root, entry.name)
    FileUtils.mkdir_p(::File.dirname(destination))
    write_entry!(entry, destination, budget: budget)
  end

  # macOS Finder's "Compress" wraps the archive with AppleDouble metadata
  # entries under `__MACOSX/._<file>.csv` — these are binary metadata, not
  # CSVs, and would crash the importer if parsed. Filtering them on entry
  # name also avoids extracting them in the first place.
  def csv_entry?(name)
    basename = ::File.basename(name)
    return false if name.start_with?('__MACOSX/') || basename.start_with?('._')

    name.downcase.end_with?('.csv')
  end

  # Stream the entry to disk directly instead of `entry.extract` — that API
  # only *warns* on unsafe paths and returns silently; we want a hard error
  # (handled by `safe_destination!`) and full control over the output path.
  #
  CHUNK_SIZE = 64 * 1024
  private_constant :CHUNK_SIZE

  # The chunked loop enforces `budget` (remaining bytes against
  # MAX_EXTRACTED_BYTES) mid-stream so an entry whose declared size lied
  # cannot fill the disk before the post-write check fires: IO.copy_stream
  # would otherwise inflate the deflate stream to EOF, ignoring our cap.
  def write_entry!(entry, destination, budget:)
    written = 0
    ::File.open(destination, 'wb') do |out|
      entry.get_input_stream do |io|
        while (chunk = io.read(CHUNK_SIZE))
          written += chunk.bytesize
          if written > budget
            out.close
            ::File.unlink(destination)
            raise Error, error(:too_large_extracted)
          end
          out.write(chunk)
        end
      end
    end
    written
  end

  # Zip-slip guard: resolve the entry path against the extract root and
  # reject anything that escapes. `expand_path` collapses `..` segments,
  # absolute paths and symlink-like trickery before the start-with check.
  def safe_destination!(root, entry_name)
    resolved = ::File.expand_path(entry_name, root)
    raise Error, error(:unsafe_entry, name: entry_name) unless resolved.start_with?("#{root}/")

    resolved
  end
end
