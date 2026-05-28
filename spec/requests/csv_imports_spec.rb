require 'zip'

RSpec.describe 'CsvImports', :with_admin_password do
  before do
    login
    allow(CsvImportRunner).to receive(:detect_completion!)
    allow(CsvImportRunner).to receive(:precheck!)
    allow(CsvImportRunner).to receive_messages(
      in_progress?: false,
      error_message: nil,
      success_message: nil,
      unavailable_reason: nil,
    )
  end

  describe 'GET /csv-imports' do
    it 'renders the upload form' do
      get csv_imports_path

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t('csv_imports.show.title'))
        expect(response.body).to include(I18n.t('csv_imports.show.description'))
        expect(response.body).to include(I18n.t('csv_imports.form.submit'))
      end
    end

    it 'renders the running state with auto-reload, phases and a progress bar' do
      allow(CsvImportRunner).to receive_messages(
        in_progress?: true,
        progress: { phase: :importing, done: 5, total: 20 },
      )

      get csv_imports_path

      aggregate_failures do
        expect(response.body).to include('Import running')
        expect(response.body).to include('data-auto-reload-interval-value')
        expect(response.body).to include('<progress')
        expect(response.body).to include('value="25"')
        expect(response.body).to include('Preparing')
        expect(response.body).to include('Importing CSV files')
        expect(response.body).to include('Reset daily summaries')
        expect(response.body).to include('Flush Redis cache')
      end
    end

    it 'renders the success state with all phases done and the file count' do
      allow(CsvImportRunner).to receive(:success_message).and_return('12')

      get csv_imports_path

      aggregate_failures do
        expect(response.body).to include('Import complete')
        expect(response.body).to include('12 CSV files were imported.')
      end
    end

    it 'renders the error state with the error log and a dismiss button' do
      allow(CsvImportRunner).to receive(:error_message).and_return('csv-importer crashed: boom')

      get csv_imports_path

      aggregate_failures do
        expect(response.body).to include('Import failed')
        expect(response.body).to include('csv-importer crashed: boom')
      end
    end

    it 'renders the unavailable state when the .env is missing' do
      allow(CsvImportRunner).to receive(:unavailable_reason).and_return(
        I18n.t('csv_imports.runner.unavailable.env_missing'),
      )

      get csv_imports_path

      expect(response.body).to include(
        I18n.t('csv_imports.runner.unavailable.env_missing'),
      )
    end
  end

  describe 'POST /csv-imports' do
    let(:upload) do
      Rack::Test::UploadedFile.new(
        zip_fixture('week-01.csv' => 'a,b,c'), 'application/zip', original_filename: 'senec.zip'
      )
    end

    it 'starts the runner and redirects on success' do
      allow(CsvImportUploader).to receive(:start)
      allow(CsvImportRunner).to receive(:start)

      post csv_imports_path, params: { file: upload }

      aggregate_failures do
        expect(response).to redirect_to(csv_imports_path)
        expect(CsvImportUploader).to have_received(:start)
        expect(CsvImportRunner).to have_received(:start)
      end
    end

    it 'renders the error inline when the runner precheck refuses (e.g. concurrent backup)' do
      allow(CsvImportRunner).to receive(:precheck!).and_raise(CsvImportRunner::Error, 'backup running')
      allow(CsvImportUploader).to receive(:start)

      post csv_imports_path, params: { file: upload }

      aggregate_failures do
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include('backup running')
        # Precheck guards the destructive uploader cleanup — it must NOT run.
        expect(CsvImportUploader).not_to have_received(:start)
      end
    end

    it 'renders the error inline when the uploader validation fails' do
      allow(CsvImportUploader).to receive(:start).and_raise(CsvImportUploader::Error, 'bad zip')

      post csv_imports_path, params: { file: upload }

      aggregate_failures do
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include('bad zip')
      end
    end

    it 'renders the error inline when the runner refuses to start' do
      allow(CsvImportUploader).to receive(:start)
      allow(CsvImportRunner).to receive(:start).and_raise(CsvImportRunner::Error, 'docker not running')

      post csv_imports_path, params: { file: upload }

      aggregate_failures do
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include('docker not running')
      end
    end
  end

  describe 'DELETE /csv-imports' do
    it 'clears error/success state, cleans up and redirects to /datasources when idle' do
      allow(CsvImportRunner).to receive(:clear_error!)
      allow(CsvImportRunner).to receive(:clear_success!)
      allow(CsvImportUploader).to receive(:cleanup!)

      delete csv_imports_path

      aggregate_failures do
        expect(response).to redirect_to(datasources_path)
        expect(CsvImportRunner).to have_received(:clear_error!)
        expect(CsvImportRunner).to have_received(:clear_success!)
        expect(CsvImportUploader).to have_received(:cleanup!)
      end
    end

    it 'refuses to clean up while an import is in progress (would yank the live bind mount)' do
      allow(CsvImportRunner).to receive(:in_progress?).and_return(true)
      allow(CsvImportUploader).to receive(:cleanup!)

      delete csv_imports_path

      aggregate_failures do
        expect(response).to redirect_to(csv_imports_path)
        expect(CsvImportUploader).not_to have_received(:cleanup!)
      end
    end
  end

  def zip_fixture(entries)
    path = Tempfile.new(['fixture', '.zip']).path
    Zip::File.open(path, create: true) do |zip|
      entries.each { |name, content| zip.get_output_stream(name) { |io| io.write(content) } }
    end
    path
  end
end
