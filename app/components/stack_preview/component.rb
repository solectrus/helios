module StackPreview
  class Component < ViewComponent::Base
    def initialize(compose_content:, env_content:)
      super()
      @compose_content = compose_content
      @env_content = env_content
    end

    private

    attr_reader :compose_content, :env_content

    def files
      [
        { label: 'compose.yaml', language_class: 'language-yaml', content: compose_content },
        { label: '.env', language_class: 'language-properties', content: env_content },
      ]
    end
  end
end
