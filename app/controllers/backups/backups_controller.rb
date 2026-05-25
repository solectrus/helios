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
      @backups = BackupRepository.all.to_a
      @backup_in_progress = BackupRunner.in_progress
      @restore_in_progress = RestoreRunner.in_progress
      failures = RunnerLog.messages_for(%i[backup restore])
      @backup_failure = failures[:backup]
      @restore_failure = failures[:restore]
      @backup_databases_configured = BackupRunner.databases_configured?
      @backup_unavailable_reason = BackupRunner.unavailable_reason unless @backup_in_progress || @restore_in_progress
      @backup_destination_configured = Configuration.current.setting_data('backup').present?
      @backup_destination = BackupRepository.destination
      @backup_destination_remote = BackupRepository.remote?
    end
  end
end
