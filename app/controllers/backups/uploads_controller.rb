module Backups
  class UploadsController < ApplicationController
    def create
      BackupUploader.start(params[:file])
      redirect_to backups_path, notice: t('.uploaded')
    rescue BackupUploader::Error => e
      redirect_to backups_path, alert: t('.error', message: e.message)
    end
  end
end
