class StatusBarsController < ApplicationController
  include TurboFrameOnly

  before_action :require_turbo_frame, only: :show

  def show
    return unless stale?(etag: status_bar_etag)

    render StatusBar::Component.new, layout: false
  end

  private

  def require_turbo_frame
    redirect_unless_turbo_frame(services_path)
  end

  def status_bar_etag
    [
      Rails.configuration.x.git.commit_version,
      Orchestration::StackStatus.overall,
      Orchestration::StackStatus.service_counts,
      Orchestration::StackStatus.pending_restart_services,
      # The "Open dashboard" shortcut toggles on the dashboard's health, which
      # can change without overall/counts changing (e.g. while another service
      # is in error). Keying the etag on it keeps the button in sync.
      Orchestration::StackStatus.status_for('dashboard'),
      RestoreRunner.in_progress&.started_at,
      BackupRunner.in_progress&.started_at,
    ]
  end
end
