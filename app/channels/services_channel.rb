class ServicesChannel < ApplicationCable::Channel
  def subscribed
    stream_from 'services'
  end
end
