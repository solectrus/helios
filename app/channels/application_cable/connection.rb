module ApplicationCable
  class Connection < ActionCable::Connection::Base
    def connect
      reject_unauthorized_connection unless authenticated?
    end

    private

    def authenticated?
      # When no password is configured, all connections are allowed
      return true if ENV['ADMIN_PASSWORD'].blank?

      request.session[:authenticated] == true
    end
  end
end
