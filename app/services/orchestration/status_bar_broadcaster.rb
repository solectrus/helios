module Orchestration
  class StatusBarBroadcaster
    def broadcast
      # Executor needed in background threads for auto-loading and
      # DB connection management. Scope kept minimal to avoid blocking
      # the Rails reloader via the interlock shared lock.
      Rails.application.executor.wrap do
        html = ApplicationController.render(
          StatusBar::Component.new,
          layout: false,
        )

        Turbo::StreamsChannel.broadcast_replace_to(
          'status_bar',
          target: 'status-bar',
          html:,
        )
      end
    end
  end
end
