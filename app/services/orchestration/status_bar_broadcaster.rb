module Orchestration
  class StatusBarBroadcaster
    def broadcast
      # Executor needed in background threads for auto-loading and
      # DB connection management. Scope kept minimal to avoid blocking
      # the Rails reloader via the interlock shared lock.
      Rails.application.executor.wrap do
        # Rendered with the default locale but delivered to clients of either
        # language, so the per-locale `hidden` hint must stay off — visibility
        # is left entirely to the per-client CSS.
        html = ApplicationController.render(
          StatusBar::Component.new(mark_active_locale: false),
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
