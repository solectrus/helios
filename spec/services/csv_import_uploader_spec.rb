require 'zip'

RSpec.describe CsvImportUploader do
  let(:data_path) { Dir.mktmpdir }

  before do
    allow(Rails.configuration).to receive(:data_path).and_return(data_path)
  end

  after { FileUtils.remove_entry(data_path) }

  describe '.start' do
    it 'extracts CSVs into the staging directory, preserving subfolders' do
      uploaded = build_upload('senec.zip', zip_with('2024/week-01.csv' => 'a,b,c', '2024/week-02.csv' => 'd,e,f'))

      described_class.start(uploaded)

      expect(File).to exist(File.join(described_class.extract_directory, '2024/week-01.csv'))
      expect(File).to exist(File.join(described_class.extract_directory, '2024/week-02.csv'))
    end

    it 'keeps the original ZIP under upload.zip' do
      uploaded = build_upload('senec.zip', zip_with('week.csv' => 'a,b'))

      described_class.start(uploaded)

      expect(File).to exist(File.join(described_class.staging_directory, 'upload.zip'))
    end

    it 'cleans stale files from a previous upload before extracting' do
      FileUtils.mkdir_p(described_class.extract_directory)
      File.write(File.join(described_class.extract_directory, 'stale.csv'), 'old')

      uploaded = build_upload('senec.zip', zip_with('week.csv' => 'a,b'))
      described_class.start(uploaded)

      expect(File).not_to exist(File.join(described_class.extract_directory, 'stale.csv'))
      expect(File).to exist(File.join(described_class.extract_directory, 'week.csv'))
    end

    it 'rejects an unsupported extension' do
      uploaded = build_upload('senec.tar', zip_with('week.csv' => 'a,b'))

      expect { described_class.start(uploaded) }
        .to raise_error(CsvImportUploader::Error,
                        I18n.t('csv_imports.uploader.errors.invalid_extension'))
    end

    it 'rejects an oversized upload' do
      uploaded = build_upload('senec.zip', zip_with('week.csv' => 'a,b'))
      allow(uploaded).to receive(:size).and_return(described_class::MAX_UPLOAD_BYTES + 1)

      expect { described_class.start(uploaded) }
        .to raise_error(CsvImportUploader::Error,
                        I18n.t('csv_imports.uploader.errors.too_large'))
    end

    it 'accepts a bare CSV upload and writes it into the extract directory' do
      uploaded = build_upload('senec-2024.csv', "timestamp,value\n2024-01-01,42\n", content_type: 'text/csv')

      described_class.start(uploaded)

      destination = File.join(described_class.extract_directory, 'senec-2024.csv')
      expect(File).to exist(destination)
      expect(File.read(destination)).to include('2024-01-01,42')
      expect(File).not_to exist(described_class.upload_path)
    end

    # The csv-importer container runs as a non-root user and reads the
    # extract tree through a read-only bind mount: a non-readable file
    # (a moved Rack tempfile keeps its 0600 mode) raises EACCES, and a
    # non-listable directory makes Dir.glob return nothing ("Imported 0
    # files"). Both must end up world-readable. Issue #233.
    it 'makes a bare CSV world-readable for the non-root importer' do
      uploaded = build_upload('senec-2024.csv', "a,b\n1,2\n", content_type: 'text/csv')

      described_class.start(uploaded)

      mode = File.stat(File.join(described_class.extract_directory, 'senec-2024.csv')).mode
      expect(mode & 0o004).to eq(0o004)
    end

    it 'makes extracted directories listable and files readable for the importer' do
      uploaded = build_upload('senec.zip', zip_with('2024/week-01.csv' => 'a,b'))

      described_class.start(uploaded)

      dir_mode = File.stat(File.join(described_class.extract_directory, '2024')).mode
      file_mode = File.stat(File.join(described_class.extract_directory, '2024/week-01.csv')).mode
      expect(dir_mode & 0o005).to eq(0o005) # other read + execute (traversable)
      expect(file_mode & 0o004).to eq(0o004) # other read
    end

    # The csv-importer globs case-sensitively (**/*.csv); HELIOS accepts an
    # uppercase .CSV extension, so it must lowercase the extension on staging
    # or the importer never matches the file ("Imported 0 files"). Issue #233.
    it 'lowercases an uppercase .CSV extension on a bare upload' do
      uploaded = build_upload('Senec-2024.CSV', "a,b\n1,2\n", content_type: 'text/csv')

      described_class.start(uploaded)

      expect(File).to exist(File.join(described_class.extract_directory, 'Senec-2024.csv'))
      expect(Dir.glob("#{described_class.extract_directory}/**/*.csv")).not_to be_empty
    end

    it 'lowercases an uppercase .CSV extension on a ZIP entry, keeping subfolders' do
      uploaded = build_upload('senec.zip', zip_with('2024/WEEK-01.CSV' => 'a,b'))

      described_class.start(uploaded)

      expect(File).to exist(File.join(described_class.extract_directory, '2024/WEEK-01.csv'))
      expect(Dir.glob("#{described_class.extract_directory}/**/*.csv")).not_to be_empty
    end

    it 'strips path segments from the CSV filename to block path traversal' do
      uploaded = build_upload('../../etc/passwd.csv', "x\n", content_type: 'text/csv')

      described_class.start(uploaded)

      expect(File).to exist(File.join(described_class.extract_directory, 'passwd.csv'))
    end

    it 'rejects a corrupt archive' do
      uploaded = build_upload('senec.zip', 'not actually a zip')

      expect { described_class.start(uploaded) }
        .to raise_error(CsvImportUploader::Error,
                        I18n.t('csv_imports.uploader.errors.invalid_zip'))
    end

    it 'rejects an archive without CSVs' do
      uploaded = build_upload('senec.zip', zip_with('readme.txt' => 'no csvs here'))

      expect { described_class.start(uploaded) }
        .to raise_error(CsvImportUploader::Error,
                        I18n.t('csv_imports.uploader.errors.no_csv'))
    end

    it 'rejects zip-slip entries that escape the target directory' do
      uploaded = build_upload('senec.zip', zip_with('../escape.csv' => 'bad'))

      expect { described_class.start(uploaded) }
        .to raise_error(CsvImportUploader::Error, /rejected/i)
    end

    it 'aborts when extracted size exceeds the zip-bomb cap' do
      stub_const('CsvImportUploader::MAX_EXTRACTED_BYTES', 100)

      uploaded = build_upload('senec.zip', zip_with('big.csv' => 'x' * 200))

      expect { described_class.start(uploaded) }
        .to raise_error(CsvImportUploader::Error,
                        I18n.t('csv_imports.uploader.errors.too_large_extracted'))
    end

    it 'wipes the staging directory if extraction fails' do
      uploaded = build_upload('senec.zip', 'corrupt')

      expect { described_class.start(uploaded) }.to raise_error(CsvImportUploader::Error)

      expect(File).not_to exist(described_class.upload_path)
      expect(File).not_to exist(described_class.extract_directory)
    end
  end

  def zip_with(entries)
    Tempfile.create(['zip-fixture', '.zip']) do |t|
      Zip::File.open(t.path, create: true) do |zip|
        entries.each { |name, content| zip.get_output_stream(name) { |io| io.write(content) } }
      end
      File.binread(t.path)
    end
  end

  def build_upload(filename, content, content_type: 'application/zip')
    tempfile = Tempfile.new(['upload', File.extname(filename)]).tap do |f|
      f.binmode
      f.write(content)
      f.flush
      f.rewind
    end
    Rack::Test::UploadedFile.new(tempfile.path, content_type, true, original_filename: filename)
  end
end
