class FilesController < ApplicationController
  before_action :require_expert_mode

  def index
    configuration = Configuration.current
    @stack_builder = Export::Builder.new(configuration)
    @stack_builder.write!
  end
end
