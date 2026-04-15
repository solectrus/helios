module TurboHelpers
  def turbo_frame_headers(frame_id = 'tab-content')
    { 'Turbo-Frame' => frame_id }
  end
end

RSpec.configure do |config|
  config.include TurboHelpers, type: :request
end
