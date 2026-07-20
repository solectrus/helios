module Orchestration
  class StatusBarBroadcaster
    # Rendering and publishing must stay atomic across threads. The events
    # listener, ComposeJob and request threads all broadcast concurrently, and
    # rendering is slow enough that a thread which read an older status can
    # finish *after* a thread that read the newer one, leaving the client stuck
    # on stale HTML (e.g. "starting" forever after an update succeeded).
    # Reentrant, because rendering may lazily trigger StackStatus#refresh!,
    # which broadcasts again.
    MONITOR = Monitor.new

    def broadcast
      # Executor needed in background threads for auto-loading and
      # DB connection management. Scope kept minimal to avoid blocking
      # the Rails reloader via the interlock shared lock.
      MONITOR.synchronize do
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
end
