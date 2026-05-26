module Backups
  class RestoreCompletionsController < ApplicationController
    def destroy
      RestoreRunner.clear_error!
      redirect_to backups_path
    end
  end
end
