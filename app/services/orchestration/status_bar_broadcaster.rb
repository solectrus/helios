module Orchestration
  class StatusBarBroadcaster
    def broadcast
      html = ApplicationController.render(
        StatusBar::Component.new,
        layout: false,
      )

      Turbo::StreamsChannel.broadcast_replace_to(
        'services',
        target: 'status-bar',
        html:,
      )
    end
  end
end
