module ApplicationCable
  class Connection < ActionCable::Connection::Base
    include Authentication

    def connect
      reject_unauthorized_connection unless authorized?
      Orchestration::EventsListener.subscriber_connected(locale: subscriber_locale)
    end

    def disconnect
      Orchestration::EventsListener.subscriber_disconnected
    end

    private

    def session
      request.session
    end

    def subscriber_locale
      UserPreferences.new(cookies).locale.to_sym
    end
  end
end
