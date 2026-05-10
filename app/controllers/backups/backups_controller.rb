module Backups
  class BackupsController < ApplicationController
    before_action :load_state, only: :index
    before_action :set_backup, only: :show

    def index
      render 'backups/index'
    end

    def show
      send_file @backup.path,
                filename: @backup.filename,
                type: 'application/x-tar',
                disposition: 'attachment'
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
    end

    private

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
      @backups = BackupRepository.all
      @backup_in_progress = BackupRunner.in_progress
      @restore_in_progress = RestoreRunner.in_progress
      @backup_failure = BackupRepository.error_message
      @restore_failure = RestoreRunner.error_message
      @backup_unavailable_reason = BackupRunner.unavailable_reason unless @backup_in_progress || @restore_in_progress
    end
  end
end
