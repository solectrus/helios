module Services
  class FilesController < BaseController
    ALLOWED_FILES = {
      'compose' => { label: -> { ::Compose.filename }, language_class: 'language-yaml', method: :compose_content },
      'env' => { label: -> { '.env' }, language_class: 'language-properties', method: :env_content },
      # The file routes the published host ports of the stack, so it exists for
      # the proxy that reaches it that way alone. On a shared network HELIOS
      # writes the routers as labels on the services instead, which that proxy
      # reads off the network (see ConfigNav::Component#show_traefik_file?).
      'traefik' => { label: -> { 'traefik.yml' }, language_class: 'language-yaml', method: :traefik_content,
                     available: lambda { |config|
                       config.reverse_proxy_external? && !config.reverse_proxy_on_shared_network?
                     } },
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
