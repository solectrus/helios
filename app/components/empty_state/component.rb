module EmptyState
  # Generic centered placeholder card shown when a page has no content yet
  # (e.g. Services before setup, Backups before the databases exist).
  # Callers supply already-translated strings, so the component stays i18n-free.
  # `cta`, when given, is a { label:, path: } hash for an optional button.
  class Component < ViewComponent::Base
    def initialize(icon:, title:, description:, cta: nil)
      super()
      @icon = icon
      @title = title
      @description = description
      @cta = cta
    end

    private

    attr_reader :icon, :title, :description, :cta
  end
end
