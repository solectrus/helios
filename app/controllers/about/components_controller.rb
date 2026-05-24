module About
  class ComponentsController < ApplicationController
    def show
      @payload = ::About::ComponentText.for(category: params[:category], name: params[:name])
      raise ActionController::RoutingError, 'Component not found' unless @payload
    end
  end
end
