module Configurations
  class ResetsController < ApplicationController
    before_action :require_backups

    def create
      if StackReset.postgresql_downgrade?
        return redirect_to(sensors_path, alert: t('.postgresql_downgrade'))
      end

      StackReset.perform!
      redirect_to sensors_path, notice: t('.success')
    end

    def destroy
      StackBackup.discard!
      redirect_to sensors_path, notice: t('.success')
    end

    private

    def require_backups
      return if StackBackup.exist?

      redirect_to(sensors_path, alert: t('configurations.resets.create.unavailable'))
    end
  end
end
