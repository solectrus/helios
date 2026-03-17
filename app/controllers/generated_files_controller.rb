class GeneratedFilesController < ApplicationController
  before_action :require_expert_mode

  def show
    configuration = Configuration.current
    @stack_builder = StackBuilder.new(configuration)
    @stack_builder.write!
  end
end
