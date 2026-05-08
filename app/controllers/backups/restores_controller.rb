module Backups
  class RestoresController < ApplicationController
    def create
      RestoreRunner.start("#{params[:backup_id]}.tar")
      Orchestration::StatusBarBroadcaster.new.broadcast
      redirect_to backups_path
    rescue RestoreRunner::Error => e
      redirect_to backups_path, alert: t('.error', message: e.message)
    end
  end
end
