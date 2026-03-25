module ApplicationCable
  class Connection < ActionCable::Connection::Base
    def connect
      reject_unauthorized_connection unless authenticated?
      Orchestration::EventsListener.subscriber_connected
    end

    def disconnect
      Orchestration::EventsListener.subscriber_disconnected
    end

    private

    def authenticated?
      # When no password is configured, all connections are allowed
      return true if ENV['ADMIN_PASSWORD'].blank?

      request.session[:authenticated] == true
    end
  end
end
