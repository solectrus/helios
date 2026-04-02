module Services
  class FilesController < ApplicationController
    before_action :require_expert_mode

    ALLOWED_FILES = {
      'compose' => { label: 'compose.yaml', language_class: 'language-yaml', method: :compose_content },
      'env' => { label: '.env', language_class: 'language-properties', method: :env_content },
    }.freeze

    def show
      file_config = ALLOWED_FILES[params[:id]]
      raise ActionController::RoutingError, 'Not Found' unless file_config

      stack_builder = Export::Builder.new(Configuration.current)
      stack_builder.write!

      @label = file_config[:label]
      @language_class = file_config[:language_class]
      @content = stack_builder.public_send(file_config[:method])
    end
  end
end
