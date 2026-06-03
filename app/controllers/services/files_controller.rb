module Services
  class FilesController < BaseController
    ALLOWED_FILES = {
      'compose' => { label: -> { ::Compose.filename }, language_class: 'language-yaml', method: :compose_content },
      'env' => { label: -> { '.env' }, language_class: 'language-properties', method: :env_content },
      'traefik' => { label: -> { 'traefik.yml' }, language_class: 'language-yaml', method: :traefik_content,
                     available: ->(config) { config.reverse_proxy_external? } },
    }.freeze

    def show
      file_config = ALLOWED_FILES[params[:id]]
      raise ActionController::RoutingError, 'Not Found' unless file_config

      available = file_config[:available]
      raise ActionController::RoutingError, 'Not Found' if available && !available.call(Configuration.current)

      # Preview only: resolve defaults so the content is accurate, but never
      # write compose.yaml/.env to disk. Writing them here would create the
      # stack files before setup is complete — making the stack look
      # configured (e.g. surfacing the Backup tab's create form instead of
      # its empty state).
      stack_builder = Export::Builder.new(Configuration.current)
      stack_builder.ensure_defaults!

      @label = file_config[:label].call
      @language_class = file_config[:language_class]
      @content = stack_builder.public_send(file_config[:method])
    end
  end
end
