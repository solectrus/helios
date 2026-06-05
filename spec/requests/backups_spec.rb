require 'rubygems/package'

RSpec.describe 'Backups', :with_admin_password do
  include ActiveSupport::Testing::TimeHelpers

  let(:data_path) { Dir.mktmpdir }

  before do
    login
    allow(Rails.configuration).to receive(:data_path).and_return(data_path)
    allow(RestoreRunner).to receive(:in_progress).and_return(nil)
    allow(CsvImportRunner).to receive(:in_progress?).and_return(false)
    # Default to "backup available" so the create section renders; the
    # preconditions-unmet cases override this in their own examples.
    allow(BackupRunner).to receive_messages(
      in_progress: nil,
      unavailable_reason: nil,
      databases_configured?: true,
    )
  end

  after { FileUtils.remove_entry(data_path) }

  describe 'GET /backups' do
    it 'renders the backup page' do
      get backups_path, headers: turbo_frame_headers('backups-content')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t('backups.index.title'))
      expect(response.body).to include(I18n.t('backups.index.download'))
      expect(response.body).to include(I18n.t('backups.index.note'))
      expect(response.body).not_to include('helios/config.yaml')
    end

    # The shell request paints instantly: it defers the (potentially slow)
    # backup listing to the lazy content frame. The absent download button
    # proves load_state did not run on the shell render.
    it 'renders a lazy content frame on the shell request and defers the body' do
      get backups_path

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('id="backups-content"')
        expect(response.body).to include('loading="lazy"')
        expect(response.body).to include("src=\"#{backups_path}\"")
        expect(response.body).not_to include(I18n.t('backups.index.download'))
      end
    end

    it 'renders the page synchronously for a remote destination — the DB-backed listing needs no sidecar' do
      with_config_yaml('backup' => { 'destination' => 'external', 'external_path' => '/mnt/nas' })

      get backups_path, headers: turbo_frame_headers('backups-content')

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t('backups.index.note'))
      end
    end

    it 'shows the configured time on the schedule row when enabled' do
      with_config_yaml('backup_schedule' => { 'schedule_enabled' => true, 'schedule_time' => '03:00' })

      get backups_path, headers: turbo_frame_headers('backups-content')

      aggregate_failures do
        expect(response.body).to include(I18n.t('backups.index.schedule_value_on', time: '03:00'))
        expect(response.body).not_to include(I18n.t('backups.index.schedule_off'))
      end
    end

    it 'shows the schedule row as off when automatic backups are disabled' do
      with_config_yaml('backup' => { 'destination' => 'local' })

      get backups_path, headers: turbo_frame_headers('backups-content')

      aggregate_failures do
        expect(response.body).to include(I18n.t('backups.index.schedule_off'))
        expect(response.body).not_to include(I18n.t('backups.index.schedule_value_on', time: '03:00'))
      end
    end

    it 'renders existing backups with database sizes' do
      persist_backup('solectrus-backup-20260508-110000.tar')

      get backups_path, headers: turbo_frame_headers('backups-content')

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('3 KB')
        expect(response.body).to include('7 KB')
        expect(response.body).not_to include('helios/config.yaml')
      end
    end

    it 'offers a restore action with confirmation dialog' do
      persist_backup('solectrus-backup-20260508-110000.tar')

      get backups_path, headers: turbo_frame_headers('backups-content')

      aggregate_failures do
        expect(response.body).to include(I18n.t('backups.index.restore_existing'))
        expect(response.body).to include(
          ERB::Util.html_escape(
            I18n.t('backups.index.restore_confirm', date: '2026-05-08', time: '11:00'),
          ),
        )
        expect(response.body).to include(I18n.t('backups.index.restore_confirm_button'))
        expect(response.body).to include('data-turbo-confirm-variant="error"')
        expect(response.body).to include(
          %(data-turbo-submits-with="#{I18n.t('backups.index.restore_in_progress')}"),
        )
      end
    end

    it 'offers a delete action with confirmation dialog' do
      persist_backup('solectrus-backup-20260508-110000.tar')

      get backups_path, headers: turbo_frame_headers('backups-content')

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

    it 'shows the InfluxDB and PostgreSQL versions of each backup' do
      persist_backup(
        'solectrus-backup-20260508-110000.tar',
        influxdb_image: 'influxdb:2.7-alpine',
        postgresql_image: 'postgres:14-alpine',
      )

      get backups_path, headers: turbo_frame_headers('backups-content')

      aggregate_failures do
        expect(response.body).to include(I18n.t('backups.index.influxdb_version', version: '2.7'))
        expect(response.body).to include(I18n.t('backups.index.postgresql_version', version: '14'))
      end
    end

    it 'offers a link to configure the backup destination, showing the current one' do
      get backups_path, headers: turbo_frame_headers('backups-content')

      aggregate_failures do
        expect(response.body).to include(I18n.t('backups.index.destination_label'))
        expect(response.body).to include(I18n.t('backups.index.destinations.local'))
        expect(response.body).to include(new_configuration_setting_path(setting: 'backup'))
      end
    end

    it 'offers a link to configure the automatic-backup schedule' do
      get backups_path, headers: turbo_frame_headers('backups-content')

      aggregate_failures do
        expect(response.body).to include(I18n.t('backups.index.configure_schedule'))
        expect(response.body).to include(new_configuration_setting_path(setting: 'backup_schedule'))
      end
    end

    it 'disables the create button and explains why when the databases are not running' do
      reason = I18n.t('backups.runner.unavailable_reasons.postgres_not_running')
      allow(BackupRunner).to receive(:unavailable_reason).and_return(reason)

      get backups_path, headers: turbo_frame_headers('backups-content')

      aggregate_failures do
        expect(response.body).to include(I18n.t('backups.index.create_title'))
        expect(response.body).to include(I18n.t('backups.index.unavailable', message: reason))
        expect(response.body).to match(/<button[^>]*disabled/)
      end
    end

    it 'shows an empty state when the database services do not exist yet' do
      allow(BackupRunner).to receive(:databases_configured?).and_return(false)

      get backups_path, headers: turbo_frame_headers('backups-content')

      aggregate_failures do
        expect(response.body).to include(I18n.t('backups.index.unavailable_title'))
        expect(response.body).to include(I18n.t('backups.index.unavailable_description'))
        expect(response.body).not_to include(I18n.t('backups.index.create_title'))
      end
    end

    it 'replaces the page with the backup progress takeover while a backup is running' do
      allow(BackupRunner).to receive(:in_progress).and_return(
        BackupRepository::InProgress.new(
          started_at: Time.zone.local(2026, 5, 8, 14, 30, 0),
          filename: 'solectrus-backup-20260508-143000.tar',
          phase: :dumping_influx,
        ),
      )
      persist_backup('solectrus-backup-20260508-110000.tar')

      get backups_path, headers: turbo_frame_headers('backups-content')

      aggregate_failures do
        expect(response.body).to include('Creating backup')
        expect(response.body).to include('Back up PostgreSQL')
        expect(response.body).to include('Back up InfluxDB')
        # The currently-running phase carries the spinner; an earlier phase shows the done checkmark.
        expect(response.body).to include('fa-circle-check')
        expect(response.body).to include('loading-spinner')
        # Takeover hides the existing list and the create/upload buttons entirely.
        expect(response.body).not_to include(
          I18n.t('backups.index.existing_titles.local'),
        )
        expect(response.body).not_to include(I18n.t('backups.index.download'))
      end
    end

    it 'shows the backup hint in the status bar while a backup is running' do
      write_status_bar_config!
      allow(BackupRunner).to receive(:in_progress).and_return(
        BackupRepository::InProgress.new(
          started_at: Time.zone.local(2026, 5, 8, 14, 30, 0),
          filename: 'solectrus-backup-20260508-143000.tar',
        ),
      )

      # Status bar lives in the app chrome (shell), so this asserts on the
      # full-layout shell render, not the lazy content frame.
      get backups_path

      status_bar = response.body[%r{<turbo-frame[^>]*id="status-bar"[^>]*>.*?</turbo-frame>}m]
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

      # Status bar lives in the app chrome (shell), so this asserts on the
      # full-layout shell render, not the lazy content frame.
      get backups_path

      status_bar = response.body[%r{<turbo-frame[^>]*id="status-bar"[^>]*>.*?</turbo-frame>}m]
      expect(status_bar).to include('Restore in progress…')
      expect(status_bar).to include('Wiederherstellung läuft…')
      expect(status_bar).not_to include('All services operational')
      expect(status_bar).not_to include('No services operational')
      expect(status_bar).not_to match(%r{<form[^>]*action="/services/batch"})
    end

    it 'shows a failure alert when a backup error was recorded' do
      RunnerLog.record_error!(:backup, 'PostgreSQL dump failed')

      get backups_path, headers: turbo_frame_headers('backups-content')

      expect(response.body).to include(I18n.t('backups.index.error', message: 'PostgreSQL dump failed'))
      expect(response.body).to include('role="alert"')
    end

    it 'shows a restore failure alert when a restore error was recorded' do
      RunnerLog.record_error!(:restore, 'InfluxDB restore failed')

      get backups_path, headers: turbo_frame_headers('backups-content')

      expect(response.body).to include(I18n.t('backups.index.restore_error', message: 'InfluxDB restore failed'))
      expect(response.body).to include('role="alert"')
    end

    it 'replaces the page with the restore progress takeover while a restore is running' do
      allow(RestoreRunner).to receive(:in_progress).and_return(
        BackupRepository::InProgress.new(
          started_at: Time.zone.local(2026, 5, 8, 14, 30, 0),
          filename: 'solectrus-backup-20260508-110000.tar',
          phase: :restoring_postgres,
        ),
      )
      persist_backup('solectrus-backup-20260508-110000.tar')

      get backups_path, headers: turbo_frame_headers('backups-content')

      aggregate_failures do
        expect(response.body).to include('Restoring backup')
        expect(response.body).to include('Extract archive')
        expect(response.body).to include('Restore PostgreSQL')
        expect(response.body).not_to include(
          I18n.t('backups.index.existing_titles.local'),
        )
        expect(response.body).not_to include(I18n.t('backups.index.download'))
      end
    end

    it 'shows the S3 download progress bar with percentage while HELIOS fetches the tar from S3' do
      with_config_yaml('backup' => { 'destination' => 's3',
                                     's3_bucket' => 'b', 's3_region' => 'r', 's3_endpoint' => 'https://e',
                                     's3_access_key_id' => 'a', 's3_secret_access_key' => 's' })
      allow(RestoreRunner).to receive(:in_progress).and_return(
        BackupRepository::InProgress.new(
          started_at: Time.zone.local(2026, 5, 8, 14, 30, 0),
          filename: 'solectrus-backup-20260508-110000.tar',
          phase: :downloading, progress: 0.42
        ),
      )

      get backups_path, headers: turbo_frame_headers('backups-content')

      aggregate_failures do
        expect(response.body).to include('Download backup from S3')
        expect(response.body).to include('42%')
        expect(response.body).to match(/<progress[^>]*value="42"[^>]*max="100"/)
      end
    end

    it 'shows the success takeover right after a backup finishes' do
      filename = 'solectrus-backup-20260508-143000.tar'
      persist_backup(filename)
      RunnerLog.record_finished!(:backup)

      get backups_path, headers: turbo_frame_headers('backups-content')

      aggregate_failures do
        expect(response.body).to include('Backup successful')
        expect(response.body).to include(filename)
      end
    end

    it 'leaves no completion card after a successful automatic backup' do
      filename = 'solectrus-backup-20260508-143000.tar'
      persist_backup(filename)
      RunnerLog.record_started!(:backup, automatic: true)
      RunnerLog.record_finished!(:backup)

      get backups_path, headers: turbo_frame_headers('backups-content')

      aggregate_failures do
        # No card to acknowledge — the backup just lands in the list.
        expect(response.body).not_to include('Backup successful')
        expect(response.body).to include(
          I18n.t('backups.index.existing_titles.local'),
        )
        expect(response.body).to include(%(href="#{backup_path('solectrus-backup-20260508-143000')}"))
      end
    end

    it 'still surfaces a failed automatic backup so the problem stays visible' do
      RunnerLog.record_started!(:backup, automatic: true)
      RunnerLog.record_error!(:backup, 'PostgreSQL dump failed')
      RunnerLog.record_finished!(:backup)

      get backups_path, headers: turbo_frame_headers('backups-content')

      aggregate_failures do
        expect(response.body).to include('Backup failed')
        expect(response.body).to include('PostgreSQL dump failed')
      end
    end

    it 'shows headline stats (size + duration) on the success takeover' do
      filename = 'solectrus-backup-20260508-143000.tar'
      travel_to(Time.zone.local(2026, 5, 8, 14, 30, 0)) { RunnerLog.record_started!(:backup) }
      travel_to(Time.zone.local(2026, 5, 8, 14, 32, 30)) do
        persist_backup(filename)
        RunnerLog.record_finished!(:backup)

        get backups_path, headers: turbo_frame_headers('backups-content')
      end

      aggregate_failures do
        expect(response.body).to include('2:30 min')
        # Exact archive size depends on tar padding; assert label + a KB figure.
        expect(response.body).to include('Size')
        expect(response.body).to match(/\d+ KB/)
      end
    end

    it 'shows the failure takeover with a manual dismiss link when a backup failed' do
      RunnerLog.record_error!(:backup, 'PostgreSQL dump failed')
      RunnerLog.record_finished!(:backup)

      get backups_path, headers: turbo_frame_headers('backups-content')

      aggregate_failures do
        expect(response.body).to include('Backup failed')
        expect(response.body).to include('PostgreSQL dump failed')
      end
    end

    it 'keeps the completion card visible across the broadcast burst' do
      persist_backup('solectrus-backup-20260508-143000.tar')
      RunnerLog.record_finished!(:backup)

      # Three back-to-back refreshes simulate the burst of Docker-event
      # broadcasts (die + destroy) that hit the page when a runner container
      # exits — all of them must still render the completion card.
      3.times do
        get backups_path, headers: turbo_frame_headers('backups-content')
        expect(response.body).to include('Backup successful')
      end
    end

    it 'keeps the completion card visible indefinitely until the user dismisses it' do
      persist_backup('solectrus-backup-20260508-143000.tar')
      RunnerLog.record_finished!(:backup)
      get backups_path, headers: turbo_frame_headers('backups-content')
      expect(response.body).to include('Backup successful')

      # Days later — still the same card, no auto-dismiss.
      travel_to(3.days.from_now) do
        get backups_path, headers: turbo_frame_headers('backups-content')
        expect(response.body).to include('Backup successful')
      end
    end

    it 'shows the completion card again on a second backup cycle' do
      persist_backup('solectrus-backup-20260508-110000.tar')
      RunnerLog.record_finished!(:backup)
      get backups_path, headers: turbo_frame_headers('backups-content')
      expect(response.body).to include('Backup successful')

      # User dismisses, normal page is back.
      delete backups_completion_path
      get backups_path, headers: turbo_frame_headers('backups-content')
      expect(response.body).not_to include('Backup successful')

      # Second backup finishes — completion card returns.
      persist_backup('solectrus-backup-20260509-120000.tar')
      RunnerLog.record_finished!(:backup)
      get backups_path, headers: turbo_frame_headers('backups-content')
      expect(response.body).to include('Backup successful')
    end

    it 'shows a restore-success card when the restore runner finished cleanly' do
      RunnerLog.record_finished!(:restore)

      get backups_path, headers: turbo_frame_headers('backups-content')

      expect(response.body).to include('Restore successful')
    end

    it 'offers a direct download link on a backup-success card' do
      persist_backup('solectrus-backup-20260510-090000.tar')
      RunnerLog.record_finished!(:backup)

      get backups_path, headers: turbo_frame_headers('backups-content')

      expect(response.body).to include(%(href="#{backup_path('solectrus-backup-20260510-090000')}"))
      expect(response.body).to include('Download backup')
    end

    it 'omits the download link on a restore-success card' do
      RunnerLog.record_finished!(:restore)

      get backups_path, headers: turbo_frame_headers('backups-content')

      expect(response.body).not_to include('Download backup')
    end

    it 'dismisses the success card via the OK button' do
      persist_backup('solectrus-backup-20260508-143000.tar')
      RunnerLog.record_started!(:backup)
      RunnerLog.record_finished!(:backup)
      get backups_path, headers: turbo_frame_headers('backups-content')

      expect(response.body).to include(%(action="#{backups_completion_path}"))

      delete backups_completion_path

      aggregate_failures do
        expect(RunnerLog.find_by(kind: :backup)).to be_nil
        get backups_path, headers: turbo_frame_headers('backups-content')
        expect(response.body).not_to include('Backup successful')
      end
    end

    it 'dismissing a backup-failure card deletes the runner-log row' do
      RunnerLog.record_error!(:backup, 'Disk full')
      RunnerLog.record_finished!(:backup)

      delete backups_completion_path

      aggregate_failures do
        expect(RunnerLog.find_by(kind: :backup)).to be_nil
        # Next GET shows the normal page, not a phantom success card.
        get backups_path, headers: turbo_frame_headers('backups-content')
        expect(response.body).not_to include('Backup successful')
        expect(response.body).to include(
          I18n.t('backups.index.existing_titles.local'),
        )
      end
    end
  end

  describe 'POST /backups' do
    it 'starts the runner and redirects without a flash notice' do
      allow(BackupRunner).to receive(:start)

      post backups_path

      expect(BackupRunner).to have_received(:start)
      expect(response).to redirect_to(backups_path)
      expect(flash[:notice]).to be_nil
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

    it 'redirects to the presigned URL when the storage adapter exposes one' do
      filename = 'solectrus-backup-20260508-110000.tar'
      persist_backup(filename)
      presigned = 'https://example.invalid/presigned'
      allow(BackupRepository).to receive(:direct_download_url).with(filename).and_return(presigned)

      get backup_path('solectrus-backup-20260508-110000')

      expect(response).to redirect_to(presigned)
    end
  end

  describe 'DELETE /backups/:id' do
    it 'removes the backup file, then redirects' do
      filename = 'solectrus-backup-20260508-110000.tar'
      persist_backup(filename)
      stored_path = File.join(data_path, 'helios', 'backups', filename)

      delete backup_path('solectrus-backup-20260508-110000')

      expect(File).not_to exist(stored_path)
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
      get backups_path, headers: turbo_frame_headers('backups-content')

      expect(response.body).to include(I18n.t('backups.index.upload'))
      expect(response.body).to include(backups_upload_path)
    end

    it 'hides the upload button entirely while a backup is in progress (takeover replaces the page)' do
      allow(BackupRunner).to receive(:in_progress).and_return(
        BackupRepository::InProgress.new(
          started_at: Time.zone.local(2026, 5, 8, 14, 30, 0),
          filename: 'solectrus-backup-20260508-143000.tar',
        ),
      )

      get backups_path, headers: turbo_frame_headers('backups-content')

      expect(response.body).not_to include(I18n.t('backups.index.upload'))
    end

    it 'disables the upload button with a tooltip for a remote destination' do
      with_config_yaml('backup' => { 'destination' => 'external', 'external_path' => '/mnt/nas' })

      get backups_path, headers: turbo_frame_headers('backups-content')

      document = Capybara.string(response.body)
      aggregate_failures do
        expect(document).to have_button(I18n.t('backups.index.upload'), disabled: true)
        expect(response.body).to include(I18n.t('backups.index.upload_unavailable_remote'))
      end
    end
  end

  describe 'DELETE /backups/completion' do
    it 'clears the backup error file and redirects' do
      runtime_dir = File.join(data_path, 'helios', 'runners')
      FileUtils.mkdir_p(runtime_dir)
      error_path = File.join(runtime_dir, 'error.txt')
      File.write(error_path, 'PostgreSQL dump failed')

      delete backups_completion_path

      expect(File).not_to exist(error_path)
      expect(response).to redirect_to(backups_path)
    end
  end

  describe 'DELETE /backups/restore_completion' do
    it 'clears the restore error file and redirects' do
      runtime_dir = File.join(data_path, 'helios', 'runners')
      FileUtils.mkdir_p(runtime_dir)
      error_path = File.join(runtime_dir, 'restore-error.txt')
      File.write(error_path, 'InfluxDB restore failed')

      delete backups_restore_completion_path

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

  def persist_backup(filename, influxdb_image: nil, postgresql_image: nil)
    entries = {
      'solectrus-postgresql-backup-2026-05-08.sql.gz' => 'p' * 2816,
      'solectrus-influxdb-backup-2026-05-08/data.tar.gz' => 'i' * 7168,
      'helios/config.yaml' => backup_config_yaml(influxdb_image, postgresql_image),
    }

    backups_dir = File.join(data_path, 'helios', 'backups')
    FileUtils.mkdir_p(backups_dir)
    path = File.join(backups_dir, filename)
    File.binwrite(path, tar_archive(entries))

    # Pin mtime to the filename's timestamp so the rendered date is deterministic
    # regardless of when the test runs and of the host TZ.
    time = Time.zone.strptime(filename[/\d{8}-\d{6}/], '%Y%m%d-%H%M%S').to_time
    File.utime(time, time, path)

    BackupRepository.record_backup!(filename)
  end

  # config.yaml as stored inside the backup archive — the source of truth for
  # the InfluxDB / PostgreSQL versions shown in the backup list.
  def backup_config_yaml(influxdb_image, postgresql_image)
    config = { 'system' => {} }
    config['influxdb'] = { 'image' => influxdb_image } if influxdb_image
    config['postgresql'] = { 'image' => postgresql_image } if postgresql_image
    YAML.dump(config)
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
