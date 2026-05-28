module Backups
  class BackupsController < ApplicationController
    before_action :set_backup, only: :show

    def index
      BackupRepository.detect_completion!
      load_state
      render 'backups/index'
    end

    def show
      if (url = BackupRepository.direct_download_url(@backup.filename))
        redirect_to url, allow_other_host: true, status: :found
        return
      end

      prepare_download_response(@backup)
      self.response_body = Enumerator.new do |yielder|
        BackupRepository.download(@backup.filename) { |chunk| yielder << chunk }
      end
    end

    def create
      BackupRunner.start
      Orchestration::StatusBarBroadcaster.new.broadcast
      redirect_to backups_path
    rescue BackupRunner::Error => e
      @backup_error = t('backups.create.error', message: e.message)
      load_state
      render 'backups/index', status: :unprocessable_content
    end

    def destroy
      BackupRepository.destroy!(backup_filename_param)
      redirect_to backups_path, notice: t('backups.destroy.deleted')
    rescue BackupRepository::NotFound
      head :not_found
    rescue BackupRepository::Error => e
      redirect_to backups_path, alert: t('backups.destroy.error', message: e.message)
    end

    private

    def prepare_download_response(backup)
      response.headers['Content-Type'] = 'application/x-tar'
      response.headers['Content-Disposition'] =
        ActionDispatch::Http::ContentDisposition.format(disposition: 'attachment', filename: backup.filename)
      response.headers['Content-Length'] = backup.bytes.to_s
      response.headers['X-Accel-Buffering'] = 'no'
    end

    def set_backup
      @backup = BackupRepository.find!(backup_filename_param)
    rescue BackupRepository::NotFound
      head :not_found
    end

    def backup_filename_param
      filename = "#{params[:id]}.tar"
      raise BackupRepository::NotFound unless BackupRepository.valid_filename?(filename)

      filename
    end

    def load_state
      load_runner_state!
      load_destination_state!
      return if @in_progress || @completion

      @backups = BackupRepository.all.to_a
      @backup_databases_configured = BackupRunner.databases_configured?
      @backup_unavailable_reason = BackupRunner.unavailable_reason
    end

    def load_runner_state!
      @backup_in_progress = BackupRunner.in_progress
      @restore_in_progress = RestoreRunner.in_progress
      @csv_import_running = CsvImportRunner.in_progress?
      @in_progress = @backup_in_progress || @restore_in_progress
      @actions_disabled_reason = actions_disabled_reason
      failures = RunnerLog.messages_for(%i[backup restore])
      @backup_failure = failures[:backup]
      @restore_failure = failures[:restore]
      @completion = evaluate_completion
      @progress_kind = progress_kind
    end

    # Localized reason the per-backup action dropdown is disabled, or nil
    # if actions are available. Determines both the disabled state of the
    # trigger and its hover tooltip.
    def actions_disabled_reason
      return t('backups.index.actions_disabled.backup_in_progress') if @backup_in_progress
      return t('backups.index.actions_disabled.restore_in_progress') if @restore_in_progress
      return t('backups.index.actions_disabled.csv_import_in_progress') if @csv_import_running

      nil
    end

    def progress_kind
      return :restore if @restore_in_progress
      return :backup if @backup_in_progress

      @completion&.kind
    end

    def load_destination_state!
      @backup_destination_configured = Configuration.current.setting_data('backup').present?
      @backup_destination = BackupRepository.destination
      @backup_destination_remote = BackupRepository.remote?
    end

    # The completion card sticks around until the user dismisses it — even
    # across HELIOS restarts or days of inactivity. clear!/clear_error! on
    # dismiss wipes last_finished_at, and the next record_started! does the
    # same for the kind that's running again, so a fresh operation always
    # supersedes the previous result.
    def evaluate_completion
      return if @in_progress

      row = RunnerLog.latest_completion(%i[backup restore])
      row && completion_for(row)
    end

    def completion_for(row)
      kind = row.kind.to_sym
      failure = kind == :backup ? @backup_failure : @restore_failure
      status = failure.present? ? :failure : :success
      backup = kind == :backup && status == :success ? BackupRepository.latest : nil
      BackupProgress::Completion.new(
        kind: kind, status: status, backup: backup, message: failure,
        started_at: row.created_at, finished_at: row.last_finished_at
      )
    end
  end
end
