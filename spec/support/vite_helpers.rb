module ViteTestHelpers
  def vite_client_tag
    ''
  end

  def vite_javascript_tag(_name, **_options)
    ''
  end

  def vite_stylesheet_tag(_name, **_options)
    ''
  end
end

RSpec.configure do |config|
  config.before(:each, type: :request) do
    ApplicationController.helper ViteTestHelpers
  end
end
