require 'rubygems/package'

RSpec.describe 'Backups', :with_admin_password do
  let(:data_path) { Dir.mktmpdir }

  before do
    login
    allow(Rails.configuration).to receive(:data_path).and_return(data_path)
    allow(BackupRunner).to receive(:in_progress).and_return(nil)
    allow(RestoreRunner).to receive(:in_progress).and_return(nil)
  end

  after { FileUtils.remove_entry(data_path) }

  describe 'GET /backups' do
    it 'renders the backup page' do
      get backups_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t('backups.index.title'))
      expect(response.body).to include(I18n.t('backups.index.download'))
      expect(response.body).to include(I18n.t('backups.index.note'))
      expect(response.body).not_to include('helios/config.yaml')
    end

    it 'renders existing backups with database sizes' do
      persist_backup('solectrus-backup-20260508-110000.tar')

      get backups_path

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('3 KB')
        expect(response.body).to include('7 KB')
        expect(response.body).not_to include('helios/config.yaml')
      end
    end

    it 'offers a restore action with confirmation dialog' do
      persist_backup('solectrus-backup-20260508-110000.tar')

      get backups_path

      aggregate_failures do
        expect(response.body).to include(I18n.t('backups.index.restore_existing'))
        expect(response.body).to include(
          ERB::Util.html_escape(
            I18n.t('backups.index.restore_confirm', date: '2026-05-08', time: '11:00'),
          ),
        )
        expect(response.body).to include(I18n.t('backups.index.restore_confirm_button'))
        expect(response.body).to include('data-turbo-confirm-variant="error"')
      end
    end

    it 'offers a delete action with confirmation dialog' do
      persist_backup('solectrus-backup-20260508-110000.tar')

      get backups_path

      aggregate_failures do
        expect(response.body).to include(I18n.t('backups.index.delete_existing'))
        expect(response.body).to include(
          ERB::Util.html_escape(
            I18n.t('backups.index.delete_confirm', date: '2026-05-08', time: '11:00'),
          ),
        )
        expect(response.body).to include(I18n.t('backups.index.delete_confirm_button'))
      end
    end

    it 'shows when a backup was restored' do
      filename = 'solectrus-backup-20260508-110000.tar'
      restored_at = Time.zone.local(2026, 5, 9, 8, 30, 0)
      persist_backup(filename, restored_at: restored_at.utc.iso8601)

      get backups_path

      expect(response.body).to include(
        I18n.t('backups.index.restored_at',
               date: I18n.l(restored_at, format: :backup_date),
               time: I18n.l(restored_at, format: :backup_time)),
      )
    end

    it 'disables the create button and explains why when preconditions are unmet' do
      reason = I18n.t('backups.runner.unavailable_reasons.postgres_not_running')
      allow(BackupRunner).to receive(:unavailable_reason).and_return(reason)

      get backups_path

      expect(response.body).to include(I18n.t('backups.index.unavailable', message: reason))
      expect(response.body).to match(/<button[^>]*disabled/)
    end

    it 'shows the in-progress row and disables the create button while running' do
      allow(BackupRunner).to receive(:in_progress).and_return(
        BackupRepository::InProgress.new(
          started_at: Time.zone.local(2026, 5, 8, 14, 30, 0),
          filename: 'solectrus-backup-20260508-143000.tar',
        ),
      )

      get backups_path

      expect(response.body).to include(I18n.t('backups.index.in_progress'))
      expect(response.body).to match(/<button[^>]*disabled/)
    end

    it 'shows the backup hint in the status bar while a backup is running' do
      write_status_bar_config!
      allow(BackupRunner).to receive(:in_progress).and_return(
        BackupRepository::InProgress.new(
          started_at: Time.zone.local(2026, 5, 8, 14, 30, 0),
          filename: 'solectrus-backup-20260508-143000.tar',
        ),
      )

      get backups_path

      status_bar = response.body[%r{<turbo-frame id="status-bar".*?</turbo-frame>}m]
      expect(status_bar).to include('Backup in progress…')
      expect(status_bar).to include('Backup wird erstellt…')
      expect(status_bar).not_to match(%r{<form[^>]*action="/services/batch"})
    end

    it 'switches the status bar to restore mode while a restore is running' do
      write_status_bar_config!
      allow(RestoreRunner).to receive(:in_progress).and_return(
        BackupRepository::InProgress.new(
          started_at: Time.zone.local(2026, 5, 8, 14, 30, 0),
          filename: 'solectrus-backup-20260508-110000.tar',
        ),
      )

      get backups_path

      status_bar = response.body[%r{<turbo-frame id="status-bar".*?</turbo-frame>}m]
      expect(status_bar).to include('Restore in progress…')
      expect(status_bar).to include('Wiederherstellung läuft…')
      expect(status_bar).not_to include('All services operational')
      expect(status_bar).not_to include('No services operational')
      expect(status_bar).not_to match(%r{<form[^>]*action="/services/batch"})
    end

    it 'shows a failure alert when error.txt exists' do
      backups_dir = File.join(data_path, 'helios', 'backups')
      FileUtils.mkdir_p(backups_dir)
      File.write(File.join(backups_dir, 'error.txt'), 'PostgreSQL dump failed')

      get backups_path

      expect(response.body).to include(I18n.t('backups.index.error', message: 'PostgreSQL dump failed'))
      expect(response.body).to include('role="alert"')
    end

    it 'shows a restore failure alert when restore-error.txt exists' do
      backups_dir = File.join(data_path, 'helios', 'backups')
      FileUtils.mkdir_p(backups_dir)
      File.write(File.join(backups_dir, 'restore-error.txt'), 'InfluxDB restore failed')

      get backups_path

      expect(response.body).to include(I18n.t('backups.index.restore_error', message: 'InfluxDB restore failed'))
      expect(response.body).to include('role="alert"')
    end

    it 'shows restore progress inside the matching backup row and keeps the create button label' do
      allow(RestoreRunner).to receive(:in_progress).and_return(
        BackupRepository::InProgress.new(
          started_at: Time.zone.local(2026, 5, 8, 14, 30, 0),
          filename: 'solectrus-backup-20260508-110000.tar',
        ),
      )
      persist_backup('solectrus-backup-20260508-110000.tar')

      get backups_path

      document = Capybara.string(response.body)
      row = document.find('li', visible: false) do |li|
        li.has_css?("[aria-label='#{I18n.t('backups.index.restore_in_progress')}']", visible: false)
      end

      expect(row).to have_text('08.05.2026').or have_text('2026-05-08')
      expect(document).to have_button(I18n.t('backups.index.download'), disabled: true)
      expect(response.body).to match(/<button[^>]*disabled/)
      visible_restore_text = ">\n                        #{I18n.t('backups.index.restore_in_progress')}\n"
      expect(response.body).not_to include(visible_restore_text)
    end
  end

  describe 'POST /backups' do
    it 'starts the runner and redirects with a flash notice' do
      allow(BackupRunner).to receive(:start)

      post backups_path

      expect(BackupRunner).to have_received(:start)
      expect(response).to redirect_to(backups_path)
      expect(flash[:notice]).to eq(I18n.t('backups.create.started'))
    end

    it 'renders an error on the page when the runner cannot start' do
      allow(BackupRunner).to receive(:start).and_raise(
        BackupRunner::Error,
        'A backup is already in progress.',
      )

      post backups_path

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(
        I18n.t('backups.create.error', message: 'A backup is already in progress.'),
      )
      expect(response.body).to include('role="alert"')
      expect(flash).to be_empty
    end
  end

  describe 'GET /backups/:id' do
    it 'downloads a stored backup' do
      filename = 'solectrus-backup-20260508-110000.tar'
      persist_backup(filename)
      stored_path = File.join(File.dirname(Configuration.path), 'backups', filename)

      get backup_path('solectrus-backup-20260508-110000')

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/x-tar')
      expect(response.headers['Content-Disposition']).to include(filename)
      expect(response.body.b).to eq(File.binread(stored_path).b)
    end

    it 'returns 404 for an unknown backup' do
      get backup_path('solectrus-backup-20260508-110000')

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /backups/:id' do
    it 'removes the backup file and its manifest, then redirects' do
      filename = 'solectrus-backup-20260508-110000.tar'
      persist_backup(filename)
      stored_path = File.join(data_path, 'helios', 'backups', filename)

      delete backup_path('solectrus-backup-20260508-110000')

      expect(File).not_to exist(stored_path)
      expect(File).not_to exist("#{stored_path}.json")
      expect(response).to redirect_to(backups_path)
      expect(flash[:notice]).to eq(I18n.t('backups.destroy.deleted'))
    end

    it 'returns 404 for an unknown backup' do
      delete backup_path('solectrus-backup-20260508-110000')

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects ids not matching the pattern' do
      delete '/backups/not-a-backup'

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /backups/upload' do
    it 'forwards the upload to the uploader and redirects with a notice' do
      allow(BackupUploader).to receive(:start)

      post backups_upload_path, params: { file: tar_upload('solectrus-backup-20260507-101234.tar') }

      expect(BackupUploader).to have_received(:start).with(
        an_object_having_attributes(original_filename: 'solectrus-backup-20260507-101234.tar'),
      )
      expect(response).to redirect_to(backups_path)
      expect(flash[:notice]).to eq(I18n.t('backups.uploads.create.uploaded'))
    end

    it 'redirects with an alert when the uploader rejects the file' do
      allow(BackupUploader).to receive(:start).and_raise(
        BackupUploader::Error,
        I18n.t('backups.uploader.errors.invalid_archive'),
      )

      post backups_upload_path, params: { file: tar_upload('migration.tar') }

      expect(response).to redirect_to(backups_path)
      expect(flash[:alert]).to eq(
        I18n.t('backups.uploads.create.error', message: I18n.t('backups.uploader.errors.invalid_archive')),
      )
    end

    it 'renders the upload button on the index page' do
      get backups_path

      expect(response.body).to include(I18n.t('backups.index.upload'))
      expect(response.body).to include(backups_upload_path)
    end

    it 'disables the upload button while a backup is in progress' do
      allow(BackupRunner).to receive(:in_progress).and_return(
        BackupRepository::InProgress.new(
          started_at: Time.zone.local(2026, 5, 8, 14, 30, 0),
          filename: 'solectrus-backup-20260508-143000.tar',
        ),
      )

      get backups_path

      document = Capybara.string(response.body)
      expect(document).to have_button(I18n.t('backups.index.upload'), disabled: true)
    end
  end

  describe 'DELETE /backups/failure' do
    it 'clears the backup error file and redirects' do
      backups_dir = File.join(data_path, 'helios', 'backups')
      FileUtils.mkdir_p(backups_dir)
      error_path = File.join(backups_dir, 'error.txt')
      File.write(error_path, 'PostgreSQL dump failed')

      delete backups_failure_path

      expect(File).not_to exist(error_path)
      expect(response).to redirect_to(backups_path)
    end
  end

  describe 'DELETE /backups/restore_failure' do
    it 'clears the restore error file and redirects' do
      backups_dir = File.join(data_path, 'helios', 'backups')
      FileUtils.mkdir_p(backups_dir)
      error_path = File.join(backups_dir, 'restore-error.txt')
      File.write(error_path, 'InfluxDB restore failed')

      delete backups_restore_failure_path

      expect(File).not_to exist(error_path)
      expect(response).to redirect_to(backups_path)
    end
  end

  describe 'POST /backups/:backup_id/restore' do
    it 'starts the restore runner and redirects with a flash notice' do
      allow(RestoreRunner).to receive(:start)

      post backup_restore_path('solectrus-backup-20260508-110000')

      expect(RestoreRunner).to have_received(:start).with('solectrus-backup-20260508-110000.tar')
      expect(response).to redirect_to(backups_path)
      expect(flash).to be_empty
    end

    it 'redirects with an alert when the restore cannot start' do
      allow(RestoreRunner).to receive(:start).and_raise(
        RestoreRunner::Error,
        'A restore is already in progress.',
      )

      post backup_restore_path('solectrus-backup-20260508-110000')

      expect(response).to redirect_to(backups_path)
      expect(flash[:alert]).to eq(
        I18n.t('backups.restores.create.error', message: 'A restore is already in progress.'),
      )
    end
  end

  def write_status_bar_config!
    FileUtils.mkdir_p(File.dirname(Configuration.path))
    File.write(Configuration.path, YAML.dump('system' => { 'admin_password' => 'test' }))
  end

  def persist_backup(filename, restored_at: nil)
    entries = {
      'solectrus-postgresql-backup-2026-05-08.sql.gz' => 'p' * 2816,
      'solectrus-influxdb-backup-2026-05-08.tar.gz' => 'i' * 7168,
      'helios/config.yaml' => 'system: {}',
    }

    backups_dir = File.join(data_path, 'helios', 'backups')
    FileUtils.mkdir_p(backups_dir)
    path = File.join(backups_dir, filename)
    File.binwrite(path, tar_archive(entries))
    manifest = { entries: entries.map { |name, content| { name: name, bytes: content.bytesize } } }
    manifest[:restored_at] = restored_at if restored_at
    File.write("#{path}.json", JSON.generate(manifest))

    # Pin mtime to the filename's timestamp so the rendered date is deterministic
    # regardless of when the test runs. Parse in Time.zone so the round-trip
    # through `stat.mtime.in_time_zone` (in BackupRepository) yields the same
    # wall-clock time the filename advertises, independent of the host TZ.
    time = Time.zone.strptime(filename[/\d{8}-\d{6}/], '%Y%m%d-%H%M%S').to_time
    File.utime(time, time, path)
  end

  def tar_upload(filename)
    tempfile = Tempfile.new(['upload', '.tar']).tap do |f|
      f.binmode
      f.write(tar_archive('helios/config.yaml' => 'system: {}'))
      f.flush
      f.rewind
    end
    Rack::Test::UploadedFile.new(tempfile.path, 'application/x-tar', true, original_filename: filename)
  end

  def tar_archive(entries)
    StringIO.new.tap do |io|
      Gem::Package::TarWriter.new(io) do |tar|
        entries.each do |name, content|
          tar.add_file_simple(name, 0o644, content.bytesize) { |entry| entry.write(content) }
        end
      end
    end.string
  end
end
