module Backups
  class CompletionsController < ApplicationController
    def destroy
      BackupRepository.clear_error!
      redirect_to backups_path
    end
  end
end
