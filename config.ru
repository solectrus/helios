# This file is used by Rack-based servers to start the application.

require_relative 'config/environment'
use(ViteRuby::DevServerProxy, ssl_verify_none: true) if ViteRuby.run_proxy?

run Rails.application
Rails.application.load_server
