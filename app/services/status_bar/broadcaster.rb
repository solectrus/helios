module StatusBar
  class Broadcaster
    def broadcast
      html = ApplicationController.render(
        Component.new,
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
